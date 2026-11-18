// AVWasm3Bridge.c - wasm3 interpreter bridge for JSC WebAssembly polyfill
// MIT License (wasm3), project license (bridge code)
#include "AVWasm3Bridge.h"
#include "wasm3.h"
#include <string.h>
#include <stdlib.h>

struct AVWasm3Instance {
    IM3Environment env;
    IM3Runtime     runtime;
    IM3Module      module;
    uint8_t*       wasmCopy; // persistent copy of WASM bytes
};

// --- Global import trampoline ---

static AVWasm3ImportCallback g_importCallback = NULL;

void AVWasm3SetImportCallback(AVWasm3ImportCallback callback) {
    g_importCallback = callback;
}

// Generic trampoline called by wasm3 for all linked imports.
// The importID is stored in _ctx->userdata.
// Stack layout: [ret0..retN-1] [arg0..argM-1]
// For void(i32) (Go WASM style): [arg0]
// For i32(i32,i32): [ret0] [arg0] [arg1]
static const void* avGenericTrampoline(IM3Runtime runtime,
                                       IM3ImportContext _ctx,
                                       uint64_t* _sp,
                                       void* _mem) {
    if (!g_importCallback) return "no import callback set";

    int32_t importID = (int32_t)(intptr_t)_ctx->userdata;
    uint32_t retc = m3_GetRetCount(_ctx->function);
    uint32_t argc = m3_GetArgCount(_ctx->function);

    // Arguments start after return slots on the value stack
    uint64_t* args = _sp + retc;
    uint64_t retval = 0;

    g_importCallback(importID, argc, args, &retval);

    // Store return value if the function returns something
    if (retc > 0) {
        _sp[0] = retval;
    }

    return NULL; // m3Err_none = success
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
    inst->runtime = m3_NewRuntime(inst->env, stackSize, NULL);
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
                                        const char* signature,
                                        int32_t importID) {
    if (!inst || !inst->module) return "invalid instance";
    return m3_LinkRawFunctionEx(inst->module, moduleName, funcName,
                                signature,
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
    M3Result result = m3_FindFunction(&func, inst->runtime, name);
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

// --- Memory ---

uint8_t* AVWasm3GetMemory(AVWasm3InstanceRef inst, uint32_t* outSize) {
    if (!inst || !inst->module) return NULL;
    return m3_GetMemory(inst->module, outSize, 0);
}

uint32_t AVWasm3GrowMemory(AVWasm3InstanceRef inst, uint32_t deltaPages) {
    // wasm3 handles memory.grow internally via the WASM instruction.
    // For external grow requests, we can try ResizeMemory if available.
    // Go WASM only grows memory from WASM instructions, so this is
    // primarily for the JS Memory.grow() API (rarely used directly).
    (void)inst; (void)deltaPages;
    return (uint32_t)-1;
}

uint32_t AVWasm3MemoryPages(AVWasm3InstanceRef inst) {
    if (!inst || !inst->module) return 0;
    uint32_t size = 0;
    m3_GetMemory(inst->module, &size, 0);
    return size / 65536;
}

// --- Cleanup ---

void AVWasm3Destroy(AVWasm3InstanceRef inst) {
    if (!inst) return;
    if (inst->runtime) m3_FreeRuntime(inst->runtime);
    if (inst->env) m3_FreeEnvironment(inst->env);
    free(inst->wasmCopy);
    free(inst);
}
