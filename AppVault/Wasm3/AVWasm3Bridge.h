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

/// Callback type for the global import trampoline.
/// Called synchronously during WASM execution when an imported function
/// is invoked. importID identifies which import was called.
/// argc/argv contain the i64-widened arguments.
/// Write a return value to retval[0] if the function has a return type.
typedef void (*AVWasm3ImportCallback)(int32_t importID,
                                      uint32_t argc, const uint64_t* argv,
                                      uint64_t* retval);

/// Set the global import trampoline callback. Must be called before
/// any WASM imports fire. Thread-safety: call from one thread only.
void AVWasm3SetImportCallback(AVWasm3ImportCallback callback);

/// Link a module import to the global trampoline with the given importID.
/// The importID will be passed to the callback when this import is called.
/// signature can be NULL for wildcard matching (matches any import).
/// Must be called before AVWasm3Compile.
const char* AVWasm3LinkImportTrampoline(AVWasm3InstanceRef inst,
                                        const char* moduleName,
                                        const char* funcName,
                                        const char* signature,
                                        int32_t importID);

/// Compile all functions after imports are linked.
const char* AVWasm3Compile(AVWasm3InstanceRef inst);

/// Run the _start or _initialize function if present.
const char* AVWasm3RunStart(AVWasm3InstanceRef inst);

// --- Exports ---

/// Find an exported function by name. Returns NULL if not found.
/// The returned pointer is valid for the lifetime of the instance.
typedef struct M3Function* AVWasm3FuncRef;
AVWasm3FuncRef AVWasm3FindFunction(AVWasm3InstanceRef inst, const char* name);

/// Get argument and return counts for a function.
uint32_t AVWasm3FuncArgCount(AVWasm3FuncRef func);
uint32_t AVWasm3FuncRetCount(AVWasm3FuncRef func);

/// Call a function with i64 arguments and get i64 results.
/// All WASM numeric types fit in i64. Floats are bit-cast.
const char* AVWasm3CallFunc(AVWasm3FuncRef func,
                             uint32_t argc, const int64_t* argv,
                             uint32_t retc, int64_t* retv);

// --- Memory ---

/// Get the linear memory base pointer and current size in bytes.
/// Returns NULL if the module has no memory.
uint8_t* AVWasm3GetMemory(AVWasm3InstanceRef inst, uint32_t* outSize);

/// Grow memory by delta pages (64KB each). Returns previous page count,
/// or (uint32_t)-1 on failure.
uint32_t AVWasm3GrowMemory(AVWasm3InstanceRef inst, uint32_t deltaPages);

/// Get the current memory size in pages.
uint32_t AVWasm3MemoryPages(AVWasm3InstanceRef inst);

// --- Lifecycle ---

/// Destroy the instance and free all resources.
void AVWasm3Destroy(AVWasm3InstanceRef inst);


#ifdef __cplusplus
}
#endif

#endif /* AVWasm3Bridge_h */
