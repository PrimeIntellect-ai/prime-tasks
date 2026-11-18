#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import http.client
import os
import random
import re
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HEADER = "/app/vendored/cpp-httplib/httplib.h"
BINARY = "/app/server/waf_server"
TESTER = "/app/tester/tester.go"
PORT = 8080


def listener_pids(port=PORT):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    if not inodes:
        return result
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def kill_listeners():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(), "Could not free port 8080"


def wait_for_listener(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"waf_server exited early with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError("waf_server did not listen on 127.0.0.1:8080")


def start_waf():
    kill_listeners()
    proc = subprocess.Popen(
        [BINARY], cwd="/app/server", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_for_listener(proc)
    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", BINARY)
        for pid in pids
    ), "The listener on port 8080 is not /app/server/waf_server"
    return proc


def stop_proc(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)


def custom_decode(value):
    for old, new in (
        ("%2f", "/"), ("%2e", "."), ("%2F", "/"), ("%2E", "."),
        ("%c0%af", "/"), ("%c0%ae", "."),
        ("%C0%AF", "/"), ("%C0%AE", "."), ("%25", "%")
    ):
        value = value.replace(old, new)
    return value


def oracle(uri):
    decoded = uri
    for _ in range(3):
        decoded = custom_decode(decoded)
    return "../" in decoded


def request(path):
    conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)
    try:
        conn.request("GET", path)
        response = conn.getresponse()
        return response.status, response.read().decode("utf-8").strip()
    finally:
        conn.close()


def wrap_percent(token, layers):
    for _ in range(layers):
        token = token.replace("%", "%25")
    return token


def generated_cases():
    nonce = os.urandom(8).hex()
    cases = [
        ("/hello", 200, "OK"),
        ("/..%2f", 403, "Blocked"),
        ("/%252e%252e%2f", 403, "Blocked"),
        ("/%c0%ae%c0%ae%c0%af", 403, "Blocked"),
    ]

    dots = ["%2e", "%2E", "%c0%ae", "%C0%AE"]
    slashes = ["%2f", "%2F", "%c0%af", "%C0%AF"]
    rng = random.SystemRandom()

    # Randomized malicious paths spanning all three decoding passes.
    for i in range(60):
        d1 = wrap_percent(rng.choice(dots), rng.randrange(3))
        d2 = wrap_percent(rng.choice(dots), rng.randrange(3))
        slash = wrap_percent(rng.choice(slashes), rng.randrange(3))
        path = f"/{nonce}/{i:x}/{d1}{d2}{slash}tail"
        assert oracle(path)
        cases.append((path, 403, "Blocked"))

    # Additional randomized URI fragments, including mixed-case and encodings
    # which need more than three rounds. Expected results are derived here.
    atoms = [
        "safe", "abc", "-", "_", ".", "%2e", "%2E", "%2f", "%2F",
        "%c0%ae", "%c0%af", "%C0%AE", "%C0%AF", "%C0%af", "%c0%AF",
        "%252e", "%252f", "%25252e", "%25252f", "%2525252e",
        "%2525252f", "x%25y"
    ]
    for i in range(100):
        fragment = "".join(rng.choice(atoms) for _ in range(rng.randrange(2, 8)))
        path = f"/{nonce}/r{i:x}/{fragment}"
        blocked = oracle(path)
        cases.append((path, 403 if blocked else 200, "Blocked" if blocked else "OK"))
    return cases


class CountingHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    count = 0
    active = 0
    max_active = 0
    paths = []
    lock = threading.Lock()

    def do_GET(self):
        with type(self).lock:
            type(self).count += 1
            type(self).active += 1
            type(self).max_active = max(type(self).max_active, type(self).active)
            type(self).paths.append(self.path)
        try:
            time.sleep(0.12)
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"OK")
        finally:
            with type(self).lock:
                type(self).active -= 1

    def log_message(self, fmt, *args):
        pass


waf = None
counter = None
counter_thread = None
success = False
try:
    # Preserve the original file and textual repair assertions.
    assert os.path.isfile(HEADER), f"Expected vendored httplib header to exist at {HEADER}"
    with open(HEADER, "r", encoding="utf-8", errors="ignore") as f:
        header_content = f.read()
    assert "class BrokenServerXYZ" not in header_content, "The httplib.h file still contains the broken class name 'BrokenServerXYZ'"
    assert "class Server {" in header_content or "class Server" in header_content, "The httplib.h file does not contain the fixed 'class Server'"

    # Ensure the repaired header actually compiles and exposes httplib::Server.
    with open("/tmp/header_probe.cpp", "w") as f:
        f.write('#include "/app/vendored/cpp-httplib/httplib.h"\nint main(){ httplib::Server server; return 0; }\n')
    probe = subprocess.run(
        ["g++", "-std=c++11", "-pthread", "/tmp/header_probe.cpp", "-o", "/tmp/header_probe"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert probe.returncode == 0, "Repaired httplib.h does not compile:\n" + probe.stdout

    assert os.path.isfile(BINARY), f"Expected C++ server binary to exist at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Expected {BINARY} to be executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "waf_server is not an ELF executable"

    assert os.path.isfile(TESTER), f"Expected Go tester file to exist at {TESTER}"

    # Parse the Go source as Go syntax, rather than accepting keywords in comments.
    analyzer_source = r'''package main
import ("go/ast"; "go/parser"; "go/token"; "os")
func main() {
 p := os.Args[len(os.Args)-1]
 f, err := parser.ParseFile(token.NewFileSet(), p, nil, 0); if err != nil { panic(err) }
 hasGo, hasChan, hasSend, hasReceive, has100 := false, false, false, false, false
 ast.Inspect(f, func(n ast.Node) bool {
  switch x := n.(type) {
  case *ast.GoStmt: hasGo = true
  case *ast.ChanType: hasChan = true
  case *ast.SendStmt: hasSend = true
  case *ast.UnaryExpr: if x.Op == token.ARROW { hasReceive = true }
  case *ast.RangeStmt: hasReceive = true
  case *ast.BasicLit: if x.Kind == token.INT && x.Value == "100" { has100 = true }
  }
  return true
 })
 if !(hasGo && hasChan && hasSend && hasReceive && has100) { os.Exit(1) }
}
'''
    with open("/tmp/analyze_tester.go", "w") as f:
        f.write(analyzer_source)
    analysis = subprocess.run(
        ["go", "run", "/tmp/analyze_tester.go", "--", TESTER],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert analysis.returncode == 0, "tester.go must use goroutines, a used channel, and a 100-request count"

    # Start the submitted binary ourselves and test many randomized URIs against
    # an independently evaluated translation of the supplied Go algorithm.
    waf = start_waf()
    for path, expected_status, expected_body in generated_cases():
        status, body = request(path)
        assert status == expected_status, f"Expected status {expected_status} for path {path}, got {status}"
        assert body == expected_body, f"Expected body '{expected_body}' for path {path}, got '{body}'"

    # Execute tester.go against an instrumented server. This proves it really
    # sends exactly 100 concurrent requests to the required path.
    stop_proc(waf)
    waf = None
    kill_listeners()
    CountingHandler.count = CountingHandler.active = CountingHandler.max_active = 0
    CountingHandler.paths = []
    counter = ThreadingHTTPServer(("127.0.0.1", PORT), CountingHandler)
    counter_thread = threading.Thread(target=counter.serve_forever, daemon=True)
    counter_thread.start()

    tester_run = subprocess.run(
        ["go", "run", TESTER], cwd="/app/tester",
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert tester_run.returncode == 0, "tester.go failed:\n" + tester_run.stdout
    assert "Success" in tester_run.stdout, "tester.go did not print Success"
    assert CountingHandler.count == 100, f"tester.go sent {CountingHandler.count} requests instead of 100"
    assert CountingHandler.paths == ["/valid_path"] * 100, "tester.go requested a path other than /valid_path"
    assert CountingHandler.max_active >= 2, "tester.go requests were not concurrent"
    success = True
finally:
    if counter is not None:
        counter.shutdown()
        counter.server_close()
    if counter_thread is not None:
        counter_thread.join(timeout=2)
    stop_proc(waf)
    # Restore the required final state: the submitted server is left running.
    try:
        if os.path.isfile(BINARY) and os.access(BINARY, os.X_OK):
            final_waf = start_waf()
            if success:
                time.sleep(0.1)
    except Exception:
        if success:
            raise
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
