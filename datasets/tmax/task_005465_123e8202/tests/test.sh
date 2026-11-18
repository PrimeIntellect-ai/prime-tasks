#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/usr/local/go/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import gzip
import http.server
import json
import os
import signal
import socket
import subprocess
import threading
import time
import urllib.request


def kill_listener(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    if inodes:
        time.sleep(0.5)


def get_url(url, timeout=5):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read(), response.headers


def validate_go_profile(path):
    assert os.path.getsize(path) > 100, f"Profile {path} is implausibly small"
    with gzip.open(path, "rb") as f:
        decoded = f.read()
    assert len(decoded) > 0, f"Profile {path} has no gzip payload"
    result = subprocess.run(
        ["go", "tool", "pprof", "-top", path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"go tool pprof rejected {path}:\n{result.stderr}"


def test_main_go_fixed():
    path = "/home/user/app/main.go"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "net/http/pprof" in content, "net/http/pprof is not imported in main.go"
    assert "<-jobChan" in content.replace(" ", ""), "Background worker reading from jobChan is missing in main.go"


def test_load_test_exists_and_sends_required_load():
    path = "/home/user/scripts/load_test.py"
    assert os.path.isfile(path), f"Python load test script {path} does not exist."

    kill_listener(8080)
    stats = {"total": 0, "valid": 0, "active": 0, "max_active": 0}
    lock = threading.Lock()

    class CaptureServer(http.server.ThreadingHTTPServer):
        allow_reuse_address = True
        daemon_threads = True

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                valid = self.path == "/process" and json.loads(body.decode("utf-8")) == {"data": "ci_test"}
            except Exception:
                valid = False

            with lock:
                stats["total"] += 1
                stats["valid"] += int(valid)
                stats["active"] += 1
                stats["max_active"] = max(stats["max_active"], stats["active"])
            time.sleep(0.03)
            payload = b'{"status":"processing"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            try:
                self.wfile.write(payload)
            finally:
                with lock:
                    stats["active"] -= 1

        def log_message(self, *args):
            pass

    server = CaptureServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(
            ["python3", path],
            cwd=os.path.dirname(path),
            capture_output=True,
            text=True,
            timeout=120,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.returncode == 0, f"Load test failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert stats["total"] == 500, f"Load test sent {stats['total']} requests instead of exactly 500"
    assert stats["valid"] == 500, "Every request must be POST /process with JSON payload {\"data\": \"ci_test\"}"
    assert stats["max_active"] > 1, "Requests were sent serially rather than concurrently"


def test_heap_profile_exists():
    path = "/home/user/output_heap.pb.gz"
    assert os.path.isfile(path), f"Heap profile {path} does not exist."
    with open(path, "rb") as f:
        magic_number = f.read(2)
    assert magic_number == b'\x1f\x8b', f"File {path} is not a valid gzip file."
    validate_go_profile(path)


def test_go_compiles():
    path = "/home/user/app/main.go"
    assert os.path.isfile(path), f"File {path} does not exist."
    result = subprocess.run(
        ["go", "build", "-o", "/dev/null", "main.go"],
        cwd="/home/user/app",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Go code failed to compile:\n{result.stderr}"


def test_running_service_has_pprof_and_consumes_jobs(tmp_path):
    binary = str(tmp_path / "app_server")
    build = subprocess.run(
        ["go", "build", "-o", binary, "main.go"],
        cwd="/home/user/app",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Go code failed to compile:\n{build.stderr}"

    kill_listener(8080)
    proc = subprocess.Popen(
        [binary],
        cwd="/home/user/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 15
        while True:
            if proc.poll() is not None:
                raise AssertionError("Go server exited before accepting connections")
            try:
                status, index, _ = get_url("http://127.0.0.1:8080/debug/pprof/", 1)
                if status == 200:
                    break
            except Exception:
                pass
            assert time.time() < deadline, "Go server did not expose /debug/pprof/ on port 8080"
            time.sleep(0.1)

        assert b"heap" in index and b"goroutine" in index, "Standard pprof index is not registered"

        _, baseline_text, _ = get_url("http://127.0.0.1:8080/debug/pprof/goroutine?debug=1")
        first = baseline_text.decode("utf-8", "replace").splitlines()[0]
        baseline = int(first.rsplit(" ", 1)[1])

        body = json.dumps({"data": "ci_test"}).encode()
        def send_one(_):
            request = urllib.request.Request(
                "http://127.0.0.1:8080/process",
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status

        with concurrent.futures.ThreadPoolExecutor(max_workers=80) as pool:
            statuses = list(pool.map(send_one, range(500)))
        assert statuses == [200] * 500, "The running /process endpoint did not accept all 500 jobs"

        deadline = time.time() + 10
        current = None
        while time.time() < deadline:
            _, goroutines, _ = get_url("http://127.0.0.1:8080/debug/pprof/goroutine?debug=1")
            current = int(goroutines.decode("utf-8", "replace").splitlines()[0].rsplit(" ", 1)[1])
            if current <= baseline + 20:
                break
            time.sleep(0.2)
        assert current <= baseline + 20, f"Goroutines remained blocked after jobs were submitted: baseline={baseline}, current={current}"

        _, stacks, _ = get_url("http://127.0.0.1:8080/debug/pprof/goroutine?debug=2")
        blocks = stacks.decode("utf-8", "replace").split("\n\n")
        app_channel_workers = [
            block for block in blocks
            if "main.go:" in block and ("[chan receive]" in block or "[select]" in block)
        ]
        assert len(app_channel_workers) == 1, "Expected one started background worker waiting continuously for jobs"

        status, heap_data, _ = get_url("http://127.0.0.1:8080/debug/pprof/heap", 15)
        assert status == 200 and heap_data.startswith(b"\x1f\x8b"), "Live pprof heap endpoint did not return a gzip profile"
        live_profile = str(tmp_path / "live_heap.pb.gz")
        with open(live_profile, "wb") as f:
            f.write(heap_data)
        validate_go_profile(live_profile)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
