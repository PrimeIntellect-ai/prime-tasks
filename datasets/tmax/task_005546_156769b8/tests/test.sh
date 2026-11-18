#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ctypes
import glob
import http.server
import json
import os
import random
import re
import shutil
import signal
import socketserver
import string
import subprocess
import threading
import time
import urllib.request

WORKSPACE = "/home/user/workspace"
LEGACY = os.path.join(WORKSPACE, "legacy_crypto")
RUST = os.path.join(WORKSPACE, "rust_api")
SO = os.path.join(LEGACY, "libcrypto_mask.so")
BENCH = os.path.join(WORKSPACE, "bench.go")
REPORT = os.path.join(WORKSPACE, "bench_report.txt")
CARGO = shutil.which("cargo") or "/home/user/.cargo/bin/cargo"
SERVER_LOG = "/tmp/verifier_rust_server.log"


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(proc.rsplit("/", 1)[1])
            if pid == os.getpid():
                continue
            for fd in glob.glob(proc + "/fd/*"):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    victims.add(pid)
                    break
        except (OSError, ValueError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=0.15):
                pass
        except Exception:
            time.sleep(0.1)
            return
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def post_token(token, timeout=2):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/secure-token",
        data=json.dumps({"token": token}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        body = response.read().decode("utf-8")
        data = json.loads(body)
        assert "masked" in data, "Response JSON does not contain 'masked' field."
        return data["masked"]


def start_rust_server(expected):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LEGACY + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    log = open(SERVER_LOG, "ab", buffering=0)
    proc = subprocess.Popen(
        [CARGO, "run", "--quiet"],
        cwd=RUST,
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    deadline = time.time() + 60
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            if post_token(expected[0]) == expected[1]:
                return proc
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    try:
        with open(SERVER_LOG, "r", errors="replace") as f:
            output = f.read()[-8000:]
    except OSError:
        output = ""
    raise AssertionError(f"Rust server did not start with expected behavior: {last_error}\n{output}")


# Phase 1: the repaired Makefile must actually rebuild the library.
assert os.path.isdir(LEGACY), f"Legacy directory {LEGACY} is missing."
for artifact in (SO, os.path.join(LEGACY, "crypto.o")):
    try:
        os.remove(artifact)
    except FileNotFoundError:
        pass
make = subprocess.run(["make"], cwd=LEGACY, capture_output=True, text=True)
assert make.returncode == 0, f"make failed:\n{make.stdout}\n{make.stderr}"
assert os.path.isfile(SO), f"Shared library {SO} was not built."
file_result = subprocess.run(["file", SO], capture_output=True, text=True)
assert "shared object" in file_result.stdout, f"{SO} is not a valid shared object: {file_result.stdout}"

# Exercise the rebuilt C artifact on verifier-generated inputs.
lib = ctypes.CDLL(SO)
lib.apply_mask.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.apply_mask.restype = None
alphabet = string.ascii_letters + string.digits + "_-"
for _ in range(8):
    raw = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(5, 40))).encode()
    out = ctypes.create_string_buffer(len(raw) + 1)
    lib.apply_mask(raw, out)
    assert out.raw[:len(raw)] == bytes(b ^ 0x2A for b in raw), "Rebuilt apply_mask has incorrect behavior."
    assert out.raw[len(raw)] == 0, "apply_mask did not NUL-terminate its output."

assert os.path.isdir(RUST), f"Rust API directory {RUST} is missing."
rs_sources = []
for path in glob.glob(os.path.join(RUST, "**", "*.rs"), recursive=True):
    if os.sep + "target" + os.sep not in path:
        with open(path, errors="replace") as f:
            rs_sources.append(f.read())
assert any(re.search(r"#\s*\[\s*test\s*\][\s\S]{0,3000}\bapply_mask\s*\(", src) for src in rs_sources), \
    "No standard #[test] directly exercising apply_mask was found."

# Instrument apply_mask while running cargo test, proving an executed Rust test reaches the C FFI.
original_so = "/tmp/original_libcrypto_mask.so"
shutil.copy2(SO, original_so)
marker = "/tmp/verifier_ffi_called"
try:
    os.remove(marker)
except FileNotFoundError:
    pass
instrumented_c = "/tmp/verifier_instrumented_crypto.c"
with open(instrumented_c, "w") as f:
    f.write(r'''#include <string.h>
#include <fcntl.h>
#include <unistd.h>
void apply_mask(const char *input, char *output) {
    int fd = open("/tmp/verifier_ffi_called", O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd >= 0) { write(fd, "1", 1); close(fd); }
    size_t n = strlen(input);
    for (size_t i = 0; i < n; i++) output[i] = input[i] ^ 0x2A;
    output[n] = '\0';
}
''')
subprocess.run(["gcc", "-shared", "-fPIC", "-o", SO, instrumented_c], check=True)
env = os.environ.copy()
env["LD_LIBRARY_PATH"] = LEGACY + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
cargo_test = subprocess.run([CARGO, "test"], cwd=RUST, env=env, capture_output=True, text=True, timeout=180)
assert cargo_test.returncode == 0, f"Rust unit tests failed:\n{cargo_test.stdout}\n{cargo_test.stderr}"
assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "cargo test did not execute apply_mask through FFI."

# Replace the library behavior with a runtime-only test implementation. The endpoint
# must follow it, which rejects hardcoded XOR endpoints and proves dynamic C FFI use.
kill_port_8080()
reverse_c = "/tmp/verifier_reverse_crypto.c"
with open(reverse_c, "w") as f:
    f.write(r'''#include <string.h>
void apply_mask(const char *input, char *output) {
    size_t n = strlen(input);
    for (size_t i = 0; i < n; i++) output[i] = input[n - i - 1];
    output[n] = '\0';
}
''')
subprocess.run(["gcc", "-shared", "-fPIC", "-o", SO, reverse_c], check=True)
probe = "ffi_" + "".join(random.SystemRandom().choice(alphabet) for _ in range(20))
start_rust_server((probe, probe[::-1]))
for _ in range(4):
    token = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(6, 35)))
    assert post_token(token) == token[::-1], "Endpoint did not return the result produced by the C library."
kill_port_8080()
shutil.copy2(original_so, SO)

# Phase 3: execute bench.go against an instrumented HTTP server and count its traffic.
assert os.path.isfile(BENCH), f"Go benchmark script {BENCH} is missing."
try:
    os.remove(REPORT)
except FileNotFoundError:
    pass

class State:
    lock = threading.Lock()
    total = 0
    valid = 0
    active = 0
    max_active = 0

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        valid = False
        try:
            valid = self.path == "/secure-token" and json.loads(raw) == {"token": "bench_test"}
        except Exception:
            pass
        with State.lock:
            State.total += 1
            State.valid += int(valid)
            State.active += 1
            State.max_active = max(State.max_active, State.active)
        try:
            time.sleep(0.02)
            body = json.dumps({"masked": "HODIRu^OY^"}).encode()
            self.send_response(200 if valid else 400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        finally:
            with State.lock:
                State.active -= 1
    def log_message(self, *args):
        pass

class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

mock = ThreadedServer(("127.0.0.1", 8080), Handler)
thread = threading.Thread(target=mock.serve_forever, daemon=True)
thread.start()
try:
    bench_run = subprocess.run(["go", "run", BENCH], cwd=WORKSPACE, capture_output=True, text=True, timeout=180)
finally:
    mock.shutdown()
    mock.server_close()
    thread.join(timeout=5)
assert bench_run.returncode == 0, f"bench.go failed:\n{bench_run.stdout}\n{bench_run.stderr}"
assert State.total == 500, f"bench.go sent {State.total} requests instead of exactly 500."
assert State.valid == 500, f"Only {State.valid} requests used POST /secure-token with the required payload."
assert State.max_active > 1, "Requests were not concurrent."
assert os.path.isfile(REPORT), f"Benchmark report {REPORT} is missing."
with open(REPORT) as f:
    report_content = f.read().strip()
assert "Success: 500" in report_content, f"Expected 'Success: 500' in {REPORT}, found: {report_content!r}"
assert report_content == "Success: 500", f"Report must have exact format 'Success: 500', found: {report_content!r}"

# Restore the required final state and retain the original fixed-token assertion too.
final_probe = "final_" + "".join(random.SystemRandom().choice(alphabet) for _ in range(16))
start_rust_server((final_probe, "".join(chr(ord(c) ^ 0x2A) for c in final_probe)))
assert post_token("test") == "^OY^", "Expected masked value '^OY^' for token 'test'."
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
