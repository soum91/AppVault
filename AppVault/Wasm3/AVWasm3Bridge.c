// AVWasm3Bridge.c - wasm3 interpreter bridge for JSC WebAssembly polyfill
// MIT License (wasm3), project license (bridge code)
#include "AVWasm3Bridge.h"
#include "m3_env.h"

#include <string.h>
#include <stdlib.h>

struct AVWasm3Instance {
    IM3Environment env;
    IM3Runtime     runtime;
    IM3Module      module;
    AVWasm3ImportCallback callback;
    void* userdata;
    uint8_t*       wasmCopy; // persistent copy of WASM bytes
};

void AVWasm3SetImportCallback(AVWasm3InstanceRef instance,
                              AVWasm3ImportCallback callback, void* userdata) {
    instance->callback = callback;
    instance->userdata = userdata;
}

static const void* avGenericTrampoline(IM3Runtime runtime, IM3ImportContext context,
                                       uint64_t* stack, void* memory) {
    (void)memory;
    AVWasm3InstanceRef instance = m3_GetUserData(runtime);
    const uint32_t returns = m3_GetRetCount(context->function);
    if (!instance->callback || returns > 1) return "unsupported host callback";
    int32_t importID = (int32_t)(intptr_t)context->userdata;
    uint64_t result = 0;
    if (!instance->callback(instance->userdata, importID, context->function, stack + returns, &result)) {
        return "JavaScript host callback failed";
    }
    if (returns) stack[0] = result;
    return NULL;
}

// --- Instance lifecycle ---

AVWasm3InstanceRef AVWasm3Create(const uint8_t* wasmBytes, uint32_t wasmLength,
                                 uint32_t stackSize, const char** outError) {
    if (!wasmBytes || wasmLength == 0) {
        if (outError) *outError = "empty WASM input";
        return NULL;
    }
    AVWasm3InstanceRef inst = (AVWasm3InstanceRef)calloc(1, sizeof(struct AVWasm3Instance));
    if (!inst) {
        if (outError) *outError = "allocation failed";
        return NULL;
    }
    // wasm3 requires the WASM bytes to persist for the module's lifetime
    inst->wasmCopy = (uint8_t*)malloc(wasmLength);
    if (!inst->wasmCopy) {
        free(inst);
        if (outError) *outError = "allocation failed";
        return NULL;
    }
    memcpy(inst->wasmCopy, wasmBytes, wasmLength);

    inst->env = m3_NewEnvironment();
    if (!inst->env) {
        free(inst->wasmCopy);
        free(inst);
        if (outError) *outError = "failed to create wasm3 environment";
        return NULL;
    }
    inst->runtime = m3_NewRuntime(inst->env, stackSize, inst);
    if (!inst->runtime) {
        m3_FreeEnvironment(inst->env);
        free(inst->wasmCopy);
        free(inst);
        if (outError) *outError = "failed to create wasm3 runtime";
        return NULL;
    }

    // Set a generous memory limit (256 MB) for Go WASM
    m3_SetResourceLimit(inst->runtime, c_m3Limit_MemoryBytes, 256 * 1024 * 1024);

    M3Result result = m3_ParseModule(inst->env, &inst->module, inst->wasmCopy, wasmLength);
    if (result) {
        if (outError) *outError = result;
        m3_FreeRuntime(inst->runtime);
        m3_FreeEnvironment(inst->env);
        free(inst->wasmCopy);
        free(inst);
        return NULL;
    }
    result = m3_LoadModule(inst->runtime, inst->module);
    if (result) {
        if (outError) *outError = result;
        m3_FreeRuntime(inst->runtime);
        m3_FreeEnvironment(inst->env);
        free(inst->wasmCopy);
        free(inst);
        return NULL;
    }
    if (outError) *outError = NULL;
    return inst;
}

// --- Import linking ---

const char* AVWasm3LinkImportTrampoline(AVWasm3InstanceRef inst,
                                        const char* moduleName,
                                        const char* funcName,
                                        int32_t importID) {
    if (!inst || !inst->module) return "invalid instance";
    return m3_LinkRawFunctionEx(inst->module, moduleName, funcName,
                                NULL,
                                (M3RawCall)avGenericTrampoline,
                                (void*)(intptr_t)importID);
}


// --- Compilation and start ---

const char* AVWasm3Compile(AVWasm3InstanceRef inst) {
    if (!inst || !inst->module) return "invalid instance";
    return m3_CompileModule(inst->module);
}

const char* AVWasm3RunStart(AVWasm3InstanceRef inst) {
    if (!inst || !inst->module) return "invalid instance";
    return m3_RunStart(inst->module);
}

// --- Exports ---

AVWasm3FuncRef AVWasm3FindFunction(AVWasm3InstanceRef inst, const char* name) {
    if (!inst || !inst->runtime) return NULL;
    IM3Function func = NULL;
    M3Result result = m3_FindFunctionIn(&func, inst->module, name);
    if (result || !func) return NULL;
    return (AVWasm3FuncRef)func;
}

uint32_t AVWasm3FuncArgCount(AVWasm3FuncRef func) {
    return func ? m3_GetArgCount((IM3Function)func) : 0;
}

uint32_t AVWasm3FuncRetCount(AVWasm3FuncRef func) {
    return func ? m3_GetRetCount((IM3Function)func) : 0;
}

const char* AVWasm3CallFunc(AVWasm3FuncRef func,
                             uint32_t argc, const int64_t* argv,
                             uint32_t retc, int64_t* retv) {
    if (!func) return "null function";
    // Build argument pointer array for m3_Call
    const void** argptrs = NULL;
    if (argc > 0) {
        argptrs = (const void**)alloca(argc * sizeof(void*));
        for (uint32_t i = 0; i < argc; i++) {
            argptrs[i] = &argv[i];
        }
    }
    M3Result result = m3_Call((IM3Function)func, argc, argptrs);
    if (result) return result;

    if (retc > 0 && retv) {
        const void** retptrs = (const void**)alloca(retc * sizeof(void*));
        for (uint32_t i = 0; i < retc; i++) {
            retv[i] = 0;
            retptrs[i] = &retv[i];
        }
        result = m3_GetResults((IM3Function)func, retc, retptrs);
        if (result) return result;
    }
    return NULL;
}

int32_t AVWasm3ArgType(AVWasm3FuncRef func, uint32_t index) {
    return m3_GetArgType(func, index);
}

int32_t AVWasm3RetType(AVWasm3FuncRef func) {
    return m3_GetRetCount(func) ? m3_GetRetType(func, 0) : c_m3Type_none;
}

uint32_t AVWasm3ExportCount(AVWasm3InstanceRef instance) {
    return instance->module->numExports;
}

const char* AVWasm3ExportName(AVWasm3InstanceRef instance, uint32_t index) {
    return instance->module->exports[index].name;
}

uint8_t AVWasm3ExportKind(AVWasm3InstanceRef instance, uint32_t index) {
    return instance->module->exports[index].kind;
}

AVWasm3FuncRef AVWasm3TableFunction(AVWasm3InstanceRef instance, uint32_t index) {
    IM3Function function = NULL;
    return m3_GetTableFunction(&function, instance->module, index) ? NULL : function;
}

// --- Memory ---

uint8_t* AVWasm3GetMemory(AVWasm3InstanceRef inst, size_t* outSize) {
    if (!inst || !inst->module) return NULL;
    return m3_GetMemory(inst->module, outSize, 0);
}

// --- Cleanup ---

void AVWasm3Destroy(AVWasm3InstanceRef inst) {
    if (!inst) return;
    if (inst->runtime) m3_FreeRuntime(inst->runtime);
    if (inst->env) m3_FreeEnvironment(inst->env);
    free(inst->wasmCopy);
    free(inst);
}
