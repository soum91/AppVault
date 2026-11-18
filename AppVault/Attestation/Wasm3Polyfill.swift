import Foundation
import JavaScriptCore

/// JavaScript surface used by the two pinned signer modules when native
/// WebAssembly is unavailable. One bridge belongs to one runtime thread.
final class Wasm3Polyfill {
    private final class Instance {
        let handle: AVWasm3InstanceRef
        init(_ handle: AVWasm3InstanceRef) { self.handle = handle }
        deinit { AVWasm3Destroy(handle) }
    }

    private weak var context: JSContext?
    private var instances: [Int: Instance] = [:]
    private var imports: [Int32: JSValue] = [:]
    private var functions: [Int: [String: AVWasm3FuncRef]] = [:]
    private var buffers: [Int: (size: Int, value: JSValue)] = [:]
    private var nextInstance = 1
    private var nextImport: Int32 = 1

    init(context: JSContext) { self.context = context }

    func close() {
        imports.removeAll()
        functions.removeAll()
        buffers.removeAll()
        instances.removeAll()
    }

    private static func encoded(_ value: JSValue?, as type: Int32) -> UInt64 {
        switch type {
        case 1: return UInt64(UInt32(bitPattern: value?.toInt32() ?? 0))
        case 2: return UInt64(bitPattern: Int64(value?.toString() ?? "") ?? 0)
        case 3: return UInt64(Float(value?.toDouble() ?? .nan).bitPattern)
        case 4: return (value?.toDouble() ?? .nan).bitPattern
        default: return 0
        }
    }

    private static func decoded(_ bits: UInt64, as type: Int32) -> Any {
        switch type {
        case 1: return Int32(truncatingIfNeeded: bits)
        case 2: return String(Int64(bitPattern: bits))
        case 3: return Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
        case 4: return Double(bitPattern: bits)
        default: return NSNull()
        }
    }

    private static let invokeImport: AVWasm3ImportCallback = { userdata, id, function, args, result in
        guard let userdata, let function else { return 0 }
        let bridge = Unmanaged<Wasm3Polyfill>.fromOpaque(userdata).takeUnretainedValue()
        guard let callback = bridge.imports[id], let context = bridge.context else { return 0 }
        var values: [Any] = []
        var types: [Int32] = []
        for index in 0..<AVWasm3FuncArgCount(function) {
            let type = AVWasm3ArgType(function, index)
            types.append(type)
            values.append(decoded(args?[Int(index)] ?? 0, as: type))
        }
        let returnType = AVWasm3RetType(function)
        let value = callback.call(withArguments: [types, values, returnType])
        guard context.exception == nil else { return 0 }
        result?.pointee = encoded(value, as: returnType)
        return 1
    }

    private static let releaseBuffer: JSTypedArrayBytesDeallocator = { _, opaque in
        if let opaque { Unmanaged<Instance>.fromOpaque(opaque).release() }
    }

    func install(in context: JSContext) {
        let create: @convention(block) (JSValue, JSValue) -> Int = { [weak self] bytes, modules in
            guard let self, let context = self.context else { return -1 }
            func fail(_ message: String) -> Int {
                context.exception = JSValue(newErrorFromMessage: message, in: context)
                return -1
            }
            let global = context.jsGlobalContextRef!
            guard let raw = bytes.jsValueRef, let buffer = JSValueToObject(global, raw, nil) else { return fail("Invalid WASM buffer") }
            let size = JSObjectGetArrayBufferByteLength(global, buffer, nil)
            guard size > 0, size <= 64 * 1024 * 1024,
                  let base = JSObjectGetArrayBufferBytesPtr(global, buffer, nil) else { return fail("Invalid WASM buffer length") }
            var error: UnsafePointer<CChar>?
            guard let handle = AVWasm3Create(base.assumingMemoryBound(to: UInt8.self), UInt32(size), 4 << 20, &error) else {
                return fail(error.map { String(cString: $0) } ?? "Cannot load WASM")
            }
            let instance = Instance(handle)
            AVWasm3SetImportCallback(handle, Self.invokeImport, Unmanaged.passUnretained(self).toOpaque())
            var linked: [Int32] = []
            var committed = false
            defer { if !committed { linked.forEach { self.imports.removeValue(forKey: $0) } } }
            // JavaScript supplies names only. Preserve callable values as JSValue.
            let names = modules.forProperty("names")?.toArray() as? [[String]] ?? []
            let wrapped = modules.forProperty("wrapped")
            for (index, pair) in names.enumerated() where pair.count == 2 {
                let id = self.nextImport
                if let error = AVWasm3LinkImportTrampoline(handle, pair[0], pair[1], id) {
                    let message = String(cString: error)
                    if message == "function lookup failed" { continue }
                    return fail(message)
                }
                guard let callable = wrapped?.atIndex(index) else { return fail("Missing WASM import callback") }
                self.imports[id] = callable
                linked.append(id)
                self.nextImport += 1
            }
            if let error = AVWasm3Compile(handle) { return fail(String(cString: error)) }
            if let error = AVWasm3RunStart(handle) { return fail(String(cString: error)) }
            let id = self.nextInstance
            self.nextInstance += 1
            self.instances[id] = instance
            committed = true
            return id
        }
        context.setObject(create, forKeyedSubscript: "__avW3Create" as NSString)

        let exports: @convention(block) (Int) -> [[String: Any]] = { [weak self] id in
            guard let handle = self?.instances[id]?.handle else { return [] }
            return (0..<AVWasm3ExportCount(handle)).compactMap { index in
                guard let name = AVWasm3ExportName(handle, index) else { return nil }
                return ["name": String(cString: name), "kind": Int(AVWasm3ExportKind(handle, index))]
            }
        }
        context.setObject(exports, forKeyedSubscript: "__avW3Exports" as NSString)

        let call: @convention(block) (Int, String, Int32, JSValue) -> JSValue = { [weak self] id, name, slot, args in
            guard let self, let context = self.context else { return JSValue(undefinedIn: JSContext.current()) }
            func fail(_ message: String) -> JSValue {
                context.exception = JSValue(newErrorFromMessage: message, in: context)
                return JSValue(undefinedIn: context)
            }
            guard let handle = self.instances[id]?.handle else { return fail("WASM instance has closed") }
            let key = slot < 0 ? name : "#\(slot)"
            guard let function = self.functions[id]?[key] ?? (slot < 0 ? AVWasm3FindFunction(handle, name) : AVWasm3TableFunction(handle, UInt32(slot))) else {
                return fail("WASM callable not found: \(key)")
            }
            self.functions[id, default: [:]][key] = function
            let count = AVWasm3FuncArgCount(function)
            let returns = AVWasm3FuncRetCount(function)
            guard returns <= 1 else { return fail("Multiple WASM results are unsupported") }
            var values = (0..<count).map { index in
                Int64(bitPattern: Self.encoded(args.atIndex(Int(index)), as: AVWasm3ArgType(function, index)))
            }
            var result: Int64 = 0
            if let error = AVWasm3CallFunc(function, count, &values, returns, &result) {
                return fail(String(cString: error))
            }
            if returns == 0 { return JSValue(undefinedIn: context) }
            let type = AVWasm3RetType(function)
            return JSValue(object: [Self.decoded(UInt64(bitPattern: result), as: type), type], in: context)
        }
        context.setObject(call, forKeyedSubscript: "__avW3Call" as NSString)

        let memory: @convention(block) (Int) -> JSValue = { [weak self] id in
            guard let self, let context = self.context else { return JSValue(nullIn: JSContext.current()) }
            guard let instance = self.instances[id] else { return JSValue(nullIn: context) }
            var size = 0
            guard let bytes = AVWasm3GetMemory(instance.handle, &size), size > 0 else { return JSValue(nullIn: context) }
            if let cached = self.buffers[id], cached.size == size { return cached.value }
            // The interpreter reserves linear memory at one address. Keep its
            // owner alive until the last JavaScript view releases the buffer.
            let retained = Unmanaged.passRetained(instance).toOpaque()
            var exception: JSValueRef?
            guard let buffer = JSObjectMakeArrayBufferWithBytesNoCopy(context.jsGlobalContextRef, bytes, size, Self.releaseBuffer, retained, &exception) else {
                // JSC calls the supplied deallocator on construction failure.
                return JSValue(nullIn: context)
            }
            let value = JSValue(jsValueRef: buffer, in: context)!
            self.buffers[id] = (size, value)
            return value
        }
        context.setObject(memory, forKeyedSubscript: "__avW3Memory" as NSString)
        context.evaluateScript(Self.script, withSourceURL: URL(string: "appvault://wasm3-polyfill.js"))
    }

    static let script = #"""
(function (root) {
  "use strict";
  const importList = modules => {
    const names = [], wrapped = [];
    for (const [module, values] of Object.entries(modules || {})) {
      for (const [name, func] of Object.entries(values)) {
        if (typeof func !== "function") continue;
        names.push([module, name]);
        wrapped.push((types, args, result) => {
          const value = func(...args.map((arg, i) => types[i] === 2 ? BigInt(arg) : arg));
          return result === 2 ? String(value) : value;
        });
      }
    }
    return {names, wrapped};
  };
  function Module(bytes) {
    this.bytes = ArrayBuffer.isView(bytes)
      ? bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
      : bytes;
  }
  function Instance(module, imports) {
    const id = root.__avW3Create(module.bytes, importList(imports));
    if (id < 1) throw new Error("WebAssembly interpreter could not instantiate module");
    const callable = (name, index = -1) => (...args) => {
      const result = root.__avW3Call(id, name, index, args.map(arg => typeof arg === "bigint" ? String(arg) : arg));
      return !result ? undefined : result[1] === 2 ? BigInt(result[0]) : result[0];
    };
    this.exports = {};
    for (const {name, kind} of root.__avW3Exports(id)) {
      if (kind === 0) this.exports[name] = callable(name);
      else if (kind === 1) this.exports[name] = {get: slot => callable("", slot)};
      else if (kind === 2) this.exports[name] = {get buffer() {return root.__avW3Memory(id);}};
      else throw new Error("Unsupported WebAssembly export kind: " + kind);
    }
  }
  root.WebAssembly = {
    Module, Instance, RuntimeError: Error,
    instantiate: async (bytes, imports) => {
      if (bytes instanceof Module) return new Instance(bytes, imports);
      const module = new Module(bytes);
      return {module, instance: new Instance(module, imports)};
    }
  };
  // Unicorn has a built-in interpreted path for guest execution.
  root.sapWasmJit = false;
})(globalThis);
"""#
}
