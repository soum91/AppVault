import Foundation
import JavaScriptCore

/// Provides a `WebAssembly` polyfill in a JSContext using wasm3 as the
/// interpreter backend. Used when JavaScriptCore's native WebAssembly is
/// unavailable (no JIT due to MAP_JIT being claimed by forkfix.dylib on
/// Dopamine jailbreaks).
///
/// The polyfill implements the subset of the WebAssembly JS API that the
/// Go WASM runtime (wasm_exec.js) and sap-signer.js use:
///   - WebAssembly.instantiate(bufferSource, importObject) -> Promise
///   - Instance with callable exports and memory access
///   - Memory grow
enum Wasm3Polyfill {

    // MARK: - Import trampoline state

    // Mapping of importID -> JSValue (the JS import function).
    // Accessed only from the RuntimeThread, so no locking needed.
    private static var importFunctions: [Int32: JSValue] = [:]
    private static weak var activeContext: JSContext?

    // MARK: - C trampoline callback

    /// Called by wasm3 (via AVWasm3Bridge) when a trampolined import fires.
    /// This is a @convention(c) function so it can serve as a C function pointer.
    private static let trampolineCallback: AVWasm3ImportCallback = {
        (importID: Int32, argc: UInt32, argv: UnsafePointer<UInt64>?, retval: UnsafeMutablePointer<UInt64>?) in

        guard let jsFunc = Wasm3Polyfill.importFunctions[importID],
              let context = Wasm3Polyfill.activeContext else {
            return
        }

        // Build JS argument array from the wasm3 stack values.
        // For Go WASM, all imports are void(i32) - one i32 argument (the SP).
        var jsArgs: [Any] = []
        if let argv {
            for i in 0..<Int(argc) {
                // Arguments are i64-widened; for i32 imports, truncate to 32 bits.
                // Go WASM uses i32 for the SP argument.
                jsArgs.append(Int32(truncatingIfNeeded: argv[i]))
            }
        }

        // Call the JS function. For Go WASM imports, these return void.
        let result = jsFunc.call(withArguments: jsArgs)

        // If the function returned a value and the WASM function expects one,
        // store it in retval.
        if let retval, let result, !result.isUndefined && !result.isNull {
            retval.pointee = UInt64(bitPattern: result.toInt64())
        }
    }

    // MARK: - Install

    /// Install the WebAssembly polyfill into the given context.
    /// Must be called on the RuntimeThread. The context must already have
    /// Promise support (from the InProcessSAPRuntime prelude).
    static func install(in context: JSContext) {
        // Set up the global import callback (only done once; subsequent calls
        // just update activeContext).
        AVWasm3SetImportCallback(trampolineCallback)
        activeContext = context
        importFunctions.removeAll()

        // Store instance references to prevent premature deallocation.
        var instances: [Int: AVWasm3InstanceRef] = [:]
        var nextInstanceID = 1
        var nextImportID: Int32 = 1

        // --- Native hook: create a wasm3 instance ---
        let create: @convention(block) (JSValue) -> JSValue = { [weak context] wasmBuf in
            guard let context else { return JSValue(undefinedIn: JSContext.current()) }
            guard let wasmData = extractBytes(from: wasmBuf, context: context) else {
                context.exception = JSValue(newErrorFromMessage: "wasm3: invalid buffer", in: context)
                return JSValue(undefinedIn: context)
            }

            var errorStr: UnsafePointer<CChar>?
            let stackSize: UInt32 = 4 * 1024 * 1024 // 4 MB interpreter stack
            let inst: AVWasm3InstanceRef? = wasmData.withUnsafeBytes { raw in
                AVWasm3Create(
                    raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    UInt32(raw.count),
                    stackSize,
                    &errorStr
                )
            }
            guard let inst else {
                let msg = errorStr.map { String(cString: $0) } ?? "unknown error"
                context.exception = JSValue(newErrorFromMessage: "wasm3 create: \(msg)", in: context)
                return JSValue(undefinedIn: context)
            }

            let id = nextInstanceID
            nextInstanceID += 1
            instances[id] = inst

            return JSValue(int32: Int32(id), in: context)
        }
        context.setObject(create, forKeyedSubscript: "__avW3Create" as NSString)

        // --- Native hook: link an import to the trampoline ---
        let linkImport: @convention(block) (Int, String, String) -> Int32 = { instanceID, moduleName, funcName in
            guard let inst = instances[instanceID] else { return -1 }
            let importID = nextImportID
            nextImportID += 1

            // Link with NULL signature (wildcard) to match any import signature
            let result = AVWasm3LinkImportTrampoline(inst, moduleName, funcName, nil, importID)
            if let result {
                let msg = String(cString: result)
                // "function lookup failed" means the WASM module doesn't import this;
                // that's fine - the importObject may have extra entries.
                if msg == "function lookup failed" { return -1 }
            }
            return importID
        }
        context.setObject(linkImport, forKeyedSubscript: "__avW3Link" as NSString)

        // --- Native hook: register a JS function for an importID ---
        let registerFunc: @convention(block) (Int32, JSValue) -> Void = { importID, jsFunc in
            Wasm3Polyfill.importFunctions[importID] = jsFunc
        }
        context.setObject(registerFunc, forKeyedSubscript: "__avW3Register" as NSString)

        // --- Native hook: compile the module ---
        let compile: @convention(block) (Int) -> JSValue = { [weak context] instanceID in
            guard let context else { return JSValue(undefinedIn: JSContext.current()) }
            guard let inst = instances[instanceID] else {
                context.exception = JSValue(newErrorFromMessage: "wasm3: instance not found", in: context)
                return JSValue(undefinedIn: context)
            }
            if let err = AVWasm3Compile(inst) {
                let msg = String(cString: err)
                context.exception = JSValue(newErrorFromMessage: "wasm3 compile: \(msg)", in: context)
                return JSValue(bool: false, in: context)
            }
            return JSValue(bool: true, in: context)
        }
        context.setObject(compile, forKeyedSubscript: "__avW3Compile" as NSString)

        // --- Native hook: run start function ---
        let runStart: @convention(block) (Int) -> Void = { instanceID in
            guard let inst = instances[instanceID] else { return }
            let result = AVWasm3RunStart(inst)
            // Some modules have no start, that's OK
            _ = result
        }
        context.setObject(runStart, forKeyedSubscript: "__avW3Start" as NSString)

        // --- Native hook: call an exported function ---
        let callExport: @convention(block) (Int, String, JSValue) -> JSValue = { [weak context] instanceID, funcName, argsArray in
            guard let context else { return JSValue(undefinedIn: JSContext.current()) }
            guard let inst = instances[instanceID] else {
                context.exception = JSValue(newErrorFromMessage: "wasm3: instance not found", in: context)
                return JSValue(undefinedIn: context)
            }
            guard let fn = AVWasm3FindFunction(inst, funcName) else {
                context.exception = JSValue(newErrorFromMessage: "wasm3: '\(funcName)' not found", in: context)
                return JSValue(undefinedIn: context)
            }

            let argc = AVWasm3FuncArgCount(fn)
            var argv = [Int64](repeating: 0, count: max(1, Int(argc)))
            if !argsArray.isUndefined && !argsArray.isNull {
                let len = min(Int(argc), Int(argsArray.forProperty("length")?.toInt32() ?? 0))
                for i in 0..<len {
                    argv[i] = argsArray.atIndex(i)?.toInt64() ?? 0
                }
            }

            let retc = AVWasm3FuncRetCount(fn)
            var retv = [Int64](repeating: 0, count: max(1, Int(retc)))

            if let err = AVWasm3CallFunc(fn, argc, &argv, retc, &retv) {
                let msg = String(cString: err)
                context.exception = JSValue(newErrorFromMessage: "wasm3 call '\(funcName)': \(msg)", in: context)
                return JSValue(undefinedIn: context)
            }

            if retc == 0 { return JSValue(undefinedIn: context) }
            return JSValue(int64: retv[0], in: context)
        }
        context.setObject(callExport, forKeyedSubscript: "__avW3Call" as NSString)

        // --- Native hook: find exported function names ---
        let findExports: @convention(block) (Int) -> JSValue = { [weak context] instanceID in
            guard let context else { return JSValue(newArrayIn: JSContext.current()) }
            guard let inst = instances[instanceID] else {
                return JSValue(newArrayIn: context)!
            }
            let exports = JSValue(newArrayIn: context)!
            // Check common Go WASM and generic exports
            let names = ["run", "resume", "getsp", "mem", "_start",
                         "_initialize", "memory", "malloc", "free",
                         "main", "_main"]
            var idx = 0
            for name in names {
                if AVWasm3FindFunction(inst, name) != nil {
                    exports.setValue(name, at: idx)
                    idx += 1
                }
            }
            return exports
        }
        context.setObject(findExports, forKeyedSubscript: "__avW3Exports" as NSString)

        // --- Native hook: get memory as ArrayBuffer ---
        let getMemory: @convention(block) (Int) -> JSValue = { [weak context] instanceID in
            guard let context else { return JSValue(nullIn: JSContext.current()) }
            guard let inst = instances[instanceID] else {
                return JSValue(nullIn: context)
            }
            var size: UInt32 = 0
            guard let ptr = AVWasm3GetMemory(inst, &size), size > 0 else {
                return JSValue(nullIn: context)
            }
            // Create an ArrayBuffer backed by the wasm3 memory.
            // This is a live view; callers must not hold references past grow/destroy.
            var exception: JSValueRef?
            guard let ab = JSObjectMakeArrayBufferWithBytesNoCopy(
                context.jsGlobalContextRef, ptr, Int(size),
                nil, nil, &exception
            ) else {
                return JSValue(nullIn: context)
            }
            return JSValue(jsValueRef: ab, in: context)
        }
        context.setObject(getMemory, forKeyedSubscript: "__avW3Memory" as NSString)

        // --- Native hook: get memory size in bytes ---
        let memSize: @convention(block) (Int) -> Int = { instanceID in
            guard let inst = instances[instanceID] else { return 0 }
            var size: UInt32 = 0
            _ = AVWasm3GetMemory(inst, &size)
            return Int(size)
        }
        context.setObject(memSize, forKeyedSubscript: "__avW3MemSize" as NSString)

        // --- Native hook: destroy instance ---
        let destroy: @convention(block) (Int) -> Void = { instanceID in
            if let inst = instances.removeValue(forKey: instanceID) {
                AVWasm3Destroy(inst)
            }
        }
        context.setObject(destroy, forKeyedSubscript: "__avW3Destroy" as NSString)

        // --- Evaluate the JavaScript polyfill ---
        context.evaluateScript(polyfillScript, withSourceURL: URL(string: "appvault://wasm3-polyfill.js"))
        if let ex = context.exception {
            context.exception = nil
            _ = ex // The setUp caller checks for WebAssembly availability
        }
    }

    // MARK: - Helpers

    private static func extractBytes(from value: JSValue, context: JSContext) -> Data? {
        let ctxRef = context.jsGlobalContextRef!
        let valRef = value.jsValueRef!

        // Check for ArrayBuffer
        if let obj = JSValueToObject(ctxRef, valRef, nil) {
            let len = JSObjectGetArrayBufferByteLength(ctxRef, obj, nil)
            if len > 0, let ptr = JSObjectGetArrayBufferBytesPtr(ctxRef, obj, nil) {
                return Data(bytes: ptr, count: len)
            }
        }

        // Check for TypedArray (Uint8Array etc.)
        let typedType = JSValueGetTypedArrayType(ctxRef, valRef, nil)
        if typedType != kJSTypedArrayTypeNone && typedType != kJSTypedArrayTypeArrayBuffer {
            if let obj = JSValueToObject(ctxRef, valRef, nil) {
                let len = JSObjectGetTypedArrayByteLength(ctxRef, obj, nil)
                if len > 0, let ptr = JSObjectGetTypedArrayBytesPtr(ctxRef, obj, nil) {
                    let offset = JSObjectGetTypedArrayByteOffset(ctxRef, obj, nil)
                    return Data(bytes: ptr.advanced(by: offset), count: len)
                }
            }
        }
        return nil
    }

    // MARK: - JS polyfill

    static let polyfillScript = #"""
(function(G) {
  "use strict";
  // WebAssembly polyfill backed by wasm3 (pure interpreter, no JIT/MAP_JIT).
  // Native hooks: __avW3Create, __avW3Link, __avW3Register, __avW3Compile,
  //               __avW3Start, __avW3Call, __avW3Exports, __avW3Memory,
  //               __avW3MemSize, __avW3Destroy

  function WasmMemory(iid) {
    this._iid = iid;
    Object.defineProperty(this, 'buffer', {
      get: function() {
        return G.__avW3Memory(this._iid) || new ArrayBuffer(0);
      }
    });
  }
  WasmMemory.prototype.grow = function(delta) {
    // Memory growth happens inside wasm3 via the memory.grow instruction.
    // The JS side just re-reads the buffer property each time.
    return G.__avW3MemSize(this._iid) / 65536;
  };

  function WasmInstance(iid, exportNames) {
    var self = this;
    this._iid = iid;
    this.exports = {};

    // Set up exported functions as callable wrappers
    for (var i = 0; i < exportNames.length; i++) {
      (function(name) {
        self.exports[name] = function() {
          var args = [];
          for (var j = 0; j < arguments.length; j++) {
            var v = arguments[j];
            args.push(typeof v === 'number' ? v : Number(v) || 0);
          }
          return G.__avW3Call(iid, name, args);
        };
      })(exportNames[i]);
    }

    // Memory is always available as 'mem' and 'memory' for Go WASM
    var mem = new WasmMemory(iid);
    self.exports.mem = mem;
    self.exports.memory = mem;
  }

  function WasmModule() {}

  G.WebAssembly = {
    instantiate: function(bufferSource, importObject) {
      return new Promise(function(resolve, reject) {
        try {
          // Normalize input to ArrayBuffer
          var bytes = bufferSource;
          if (ArrayBuffer.isView(bufferSource)) {
            bytes = bufferSource.buffer.slice(
              bufferSource.byteOffset,
              bufferSource.byteOffset + bufferSource.byteLength
            );
          }

          // Create the wasm3 instance
          var iid = G.__avW3Create(bytes);
          if (iid <= 0) {
            reject(new Error("WebAssembly: failed to create instance"));
            return;
          }

          // Link imports from the importObject
          if (importObject) {
            var moduleNames = Object.keys(importObject);
            for (var m = 0; m < moduleNames.length; m++) {
              var modName = moduleNames[m];
              var mod = importObject[modName];
              if (!mod || typeof mod !== 'object') continue;
              var funcNames = Object.keys(mod);
              for (var f = 0; f < funcNames.length; f++) {
                var fName = funcNames[f];
                var fn = mod[fName];
                if (typeof fn !== 'function') continue;
                // Link this import and get an importID
                var importID = G.__avW3Link(iid, modName, fName);
                if (importID > 0) {
                  // Register the JS function for this importID
                  G.__avW3Register(importID, fn);
                }
              }
            }
          }

          // Compile
          if (!G.__avW3Compile(iid)) {
            G.__avW3Destroy(iid);
            reject(new Error("WebAssembly: compilation failed"));
            return;
          }

          // Run start function (if any)
          G.__avW3Start(iid);

          // Discover exports
          var exportNames = G.__avW3Exports(iid) || [];

          var instance = new WasmInstance(iid, exportNames);
          var module = new WasmModule();
          resolve({ module: module, instance: instance });
        } catch (e) {
          reject(e);
        }
      });
    },
    Memory: WasmMemory,
    Instance: WasmInstance,
    Module: WasmModule,
    validate: function() { return true; },
    compile: function(bytes) {
      return G.WebAssembly.instantiate(bytes, {}).then(function(r) { return r.module; });
    },
    instantiateStreaming: function(response, importObject) {
      return response.then(function(r) { return r.arrayBuffer(); })
        .then(function(bytes) { return G.WebAssembly.instantiate(bytes, importObject); });
    }
  };
})(globalThis);
"""#
}
