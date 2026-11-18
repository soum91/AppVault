"""Run the production Swift signer with native WebAssembly disabled.

This fixture serves the pinned runtime locally and permits no Apple requests.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading

worker = Path(sys.argv[1]).resolve()
assets = Path(sys.argv[2]).resolve()
served = set()


class Resources(BaseHTTPRequestHandler):
    def do_GET(self):
        allowed = {
            "/runtime/sap.wasm",
            "/runtime/libCoreADI.so",
            "/runtime/libstoreservicescore.so",
        }
        if self.path not in allowed:
            self.send_error(404)
            return
        data = (assets / Path(self.path).name).read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        served.add(self.path)

    def log_message(self, *_):
        pass


with ThreadingHTTPServer(("127.0.0.1", 0), Resources) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}/"
        # Keep stdin open until the helper returns its asynchronous result.
        with subprocess.Popen(
            [worker, base, assets],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        ) as process:
            killer = threading.Timer(180, process.kill)
            killer.start()
            try:
                for line in process.stdout:
                    message = json.loads(line)
                    assert message["type"] != "fatal", message
                    if message["type"] == "ready":
                        script = """
                        if (globalThis.sapWasmJit !== false) throw Error("Interpreter not installed");
                        await loadSapSigner({proxyURL: proxy});
                        const proof = JSON.parse(await sapStoreProofHeaders(state, {proxyURL: proxy}));
                        if (typeof sapWasmPrepareSetup !== "function") throw Error("Go signer did not initialize");
                        return JSON.stringify({provisioned: proof.provisioned, signerReady: true});
                        """
                        request = {
                            "id": 1, "script": script,
                            "arguments": {
                                "state": json.dumps({"identifier": "0123456789abcdef", "files": {}}),
                                "proxy": base + "proxy",
                            },
                        }
                        process.stdin.write(json.dumps(request) + "\n")
                        process.stdin.flush()
                    elif message["type"] == "result":
                        assert message["ok"], message
                        assert json.loads(message["value"]) == {"provisioned": False, "signerReady": True}
                        assert served == {"/runtime/sap.wasm", "/runtime/libCoreADI.so", "/runtime/libstoreservicescore.so"}
                        print("PASS: both pinned WASM modules and local Store state initialized under the Swift interpreter bridge")
                        break
                else:
                    raise RuntimeError("Signer exited before producing its result")
            finally:
                killer.cancel()
                if process.poll() is None:
                    process.terminate()
    finally:
        server.shutdown()
