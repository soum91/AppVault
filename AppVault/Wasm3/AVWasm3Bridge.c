// AVWasm3Bridge.c - wasm3 interpreter bridge for JSC WebAssembly polyfill
// MIT License (wasm3), project license (bridge code)
#include "AVWasm3Bridge.h"
#include "m3_env.h"

#include <string.h>
#include <stdlib.h>

typedef struct AVWasm3Wrapper {
    struct AVWasm3Wrapper* next;
    uint8_t bytes[];
} AVWasm3Wrapper;

struct AVWasm3Instance {
    IM3Environment env;
    IM3Runtime     runtime;
    IM3Module      module;
    AVWasm3ImportCallback callback;
    void* userdata;
    AVWasm3Wrapper* wrappers;
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

static IM3Table firstTable(AVWasm3InstanceRef instance) {
    return instance->module->numTables ? instance->module->tables[0] : NULL;
}

int32_t AVWasm3TableLength(AVWasm3InstanceRef instance) {
    IM3Table table = firstTable(instance);
    return table ? (int32_t)table->size : -1;
}

int AVWasm3TableHasFunction(AVWasm3InstanceRef instance, uint32_t index) {
    IM3Table table = firstTable(instance);
    return table && index < table->size && table->elements[index] != NULL;
}

int32_t AVWasm3TableGrow(AVWasm3InstanceRef instance, uint32_t delta) {
    IM3Table table = firstTable(instance);
    if (!table) return -1;
    uint32_t old = table->size;
    uint32_t max = table->maxSize ? table->maxSize : 65536;
    if (old > max || delta > max - old) return -1;
    if (!delta) return (int32_t)old;
    void** elements = m3_ReallocArray(void*, table->elements, old + delta, old);
    if (!elements) return -1;
    memset(elements + old, 0, delta * sizeof(*elements));
    table->elements = elements;
    table->size = old + delta;
    instance->runtime->tableElementsUsed += delta;
    return (int32_t)old;
}

const char* AVWasm3TableSet(AVWasm3InstanceRef instance, uint32_t index,
                           const uint8_t* wrapper, uint32_t length, int32_t callbackID) {
    IM3Table table = firstTable(instance);
    if (!table || index >= table->size) return "WASM table index out of range";
    if (!wrapper) {
        table->elements[index] = NULL;
        return NULL;
    }
    // Emscripten wraps a JS callback as a tiny WASM module that re-exports e.f.
    // Load it into the caller's runtime so call_indirect can use its own stack.
    if (!length || length > 4096) return "invalid WASM callback wrapper";
    AVWasm3Wrapper* storage = malloc(sizeof(*storage) + length);
    if (!storage) return "cannot allocate WASM callback wrapper";
    memcpy(storage->bytes, wrapper, length);
    IM3Module module = NULL;
    M3Result error = m3_ParseModule(instance->env, &module, storage->bytes, length);
    if (error) {
        free(storage);
        return error;
    }
    storage->next = instance->wrappers;
    instance->wrappers = storage;
    error = m3_LoadModule(instance->runtime, module);
    if (error) return error;
    error = m3_LinkRawFunctionEx(module, "e", "f", NULL, avGenericTrampoline, (void*)(intptr_t)callbackID);
    if (error) return error;
    IM3Function function = NULL;
    error = m3_FindFunctionIn(&function, module, "f");
    if (error) return error;
    table->elements[index] = function;
    return NULL;
}

// --- Memory ---

uint8_t* AVWasm3GetMemory(AVWasm3InstanceRef inst, size_t* outSize) {
    if (!inst || !inst->module) return NULL;
    return m3_GetMemory(inst->module, outSize, 0);
}

int32_t AVWasm3GrowMemory(AVWasm3InstanceRef inst, uint32_t delta) {
    IM3Memory memory = inst->module->memory0;
    if (!memory || memory->numPages > UINT32_MAX - delta) return -1;
    uint32_t old = (uint32_t)memory->numPages;
    return ResizeMemory(inst->runtime, memory, (uint64_t)old + delta) ? -1 : (int32_t)old;
}

// --- Cleanup ---

void AVWasm3Destroy(AVWasm3InstanceRef inst) {
    if (!inst) return;
    if (inst->runtime) m3_FreeRuntime(inst->runtime);
    if (inst->env) m3_FreeEnvironment(inst->env);
    free(inst->wasmCopy);
    while (inst->wrappers) {
        AVWasm3Wrapper* wrapper = inst->wrappers;
        inst->wrappers = wrapper->next;
        free(wrapper);
    }
    free(inst);
}
