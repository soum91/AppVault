// AVWasm3Bridge.h - wasm3 interpreter bridge for JSC WebAssembly polyfill
// MIT License (wasm3), project license (bridge code)
#ifndef AVWasm3Bridge_h
#define AVWasm3Bridge_h

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a wasm3 instance (environment + runtime + module).
typedef struct AVWasm3Instance* AVWasm3InstanceRef;

/// Create a new wasm3 instance from raw WASM bytes. The bytes are copied.
/// stackSize is the interpreter stack size in bytes (e.g. 4 << 20 for 4 MB).
/// Returns NULL on failure, with *outError pointing to a static error string.
AVWasm3InstanceRef AVWasm3Create(const uint8_t* wasmBytes, uint32_t wasmLength,
                                 uint32_t stackSize, const char** outError);

// --- Import linking (trampoline) ---

typedef struct M3Function* AVWasm3FuncRef;
typedef int (*AVWasm3ImportCallback)(void* userdata, int32_t importID,
                                    AVWasm3FuncRef function, const uint64_t* args,
                                    uint64_t* result);
void AVWasm3SetImportCallback(AVWasm3InstanceRef instance,
                              AVWasm3ImportCallback callback, void* userdata);
const char* AVWasm3LinkImportTrampoline(AVWasm3InstanceRef instance,
                                       const char* module, const char* name,
                                       int32_t importID);

/// Compile all functions after imports are linked.
const char* AVWasm3Compile(AVWasm3InstanceRef inst);

/// Run the _start or _initialize function if present.
const char* AVWasm3RunStart(AVWasm3InstanceRef inst);

// --- Exports ---

/// Find an exported function by name. Returns NULL if not found.
/// The returned pointer is valid for the lifetime of the instance.
AVWasm3FuncRef AVWasm3FindFunction(AVWasm3InstanceRef inst, const char* name);

/// Get argument and return counts for a function.
uint32_t AVWasm3FuncArgCount(AVWasm3FuncRef func);
uint32_t AVWasm3FuncRetCount(AVWasm3FuncRef func);
int32_t AVWasm3ArgType(AVWasm3FuncRef func, uint32_t index);
int32_t AVWasm3RetType(AVWasm3FuncRef func);
uint32_t AVWasm3ExportCount(AVWasm3InstanceRef instance);
const char* AVWasm3ExportName(AVWasm3InstanceRef instance, uint32_t index);
uint8_t AVWasm3ExportKind(AVWasm3InstanceRef instance, uint32_t index);
AVWasm3FuncRef AVWasm3TableFunction(AVWasm3InstanceRef instance, uint32_t index);

/// Call a function with i64 arguments and get i64 results.
/// All WASM numeric types fit in i64. Floats are bit-cast.
const char* AVWasm3CallFunc(AVWasm3FuncRef func,
                             uint32_t argc, const int64_t* argv,
                             uint32_t retc, int64_t* retv);

// --- Memory ---

/// Get the linear memory base pointer and current size in bytes.
/// Returns NULL if the module has no memory.
uint8_t* AVWasm3GetMemory(AVWasm3InstanceRef inst, size_t* outSize);

// --- Lifecycle ---

/// Destroy the instance and free all resources.
void AVWasm3Destroy(AVWasm3InstanceRef inst);


#ifdef __cplusplus
}
#endif

#endif /* AVWasm3Bridge_h */
