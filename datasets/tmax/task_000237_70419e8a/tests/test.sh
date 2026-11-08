#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import secrets
import shutil
import signal
import socket
import string
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import pytest

APP_DIR = "/app"
LIBRARY_DIR = os.path.join(APP_DIR, "fast-url-parser-1.2.0")
SO_FILE = os.path.join(LIBRARY_DIR, "libfastparser.so")
SERVER_FILE = os.path.join(APP_DIR, "server.py")
BENCH_FILE = os.path.join(APP_DIR, "bench.py")
BENCH_RESULTS = os.path.join(APP_DIR, "bench_results.txt")
BASE_URL = "http://127.0.0.1:8888/api/v1/normalize"
AUTH = "Bearer dev-sec-token"
HEADERS = {"Authorization": AUTH}


def request(params=None, headers=None, url=BASE_URL):
    if params is not None:
        url += "?" + urlencode(params)
    req = Request(url, headers=headers or {}, method="GET")
    try:
        with urlopen(req, timeout=4) as response:
            return response.status, response.read().decode("utf-8")
    except HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")
    except OSError as exc:
        pytest.fail(f"Could not connect to the server at 127.0.0.1:8888: {exc}")


def expected_clean(value):
    raw = value.encode("utf-8")
    out = bytearray()
    i = 0
    while i < len(raw) and len(out) < 255:
        if i + 2 < len(raw) and raw[i:i+3] == b"../":
            i += 3
        else:
            out.append(raw[i])
            i += 1
    return out.decode("utf-8")


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1].upper() == "22B8":
                        inodes.add(fields[9])
        except OSError:
            pass
    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(name))
        except OSError:
            pass
    return result


def stop_listener():
    for _ in range(3):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.5)
    for pid in listener_pids():
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.3)
    assert not listener_pids(), "Could not stop the process listening on port 8888"


def start_agent_server():
    proc = subprocess.Popen(
        [sys.executable, SERVER_FILE], cwd=APP_DIR,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 6
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"server.py exited during startup with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8888), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.1)
    proc.terminate()
    pytest.fail("server.py did not listen on 127.0.0.1:8888")


def assert_success(params, expected):
    status, body = request(params, HEADERS)
    assert status == 200, f"Expected 200 for valid request, got {status}: {body}"
    try:
        data = json.loads(body)
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {body}")
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("cleaned_path") == expected, \
        f"Expected cleaned_path {expected!r}, got {data.get('cleaned_path')!r}"


def test_shared_object_compiled_and_callable():
    assert os.path.isfile(SO_FILE), f"Shared object not found: {SO_FILE}. The Makefile might not be fixed or 'make' was not run."
    build = subprocess.run(["make", "-C", LIBRARY_DIR], text=True, capture_output=True)
    assert build.returncode == 0, f"The repaired Makefile cannot build the library:\n{build.stdout}\n{build.stderr}"
    try:
        library = ctypes.CDLL(SO_FILE)
        clean_path = library.clean_path
    except (OSError, AttributeError) as exc:
        pytest.fail(f"libfastparser.so is not a loadable library exporting clean_path: {exc}")
    clean_path.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    clean_path.restype = None
    for value in (b"../../../etc/passwd", b"/a/../b/../../c", b"plain/path"):
        output = ctypes.create_string_buffer(256)
        clean_path(value, output)
        assert output.value.decode() == expected_clean(value.decode())


def test_server_no_auth():
    status, _ = request({"path": "/test", "min_version": "1.0.0", "client_version": "1.0.0"})
    assert status == 401, f"Expected 401 for missing auth, got {status}"


def test_server_invalid_auth():
    status, _ = request(
        {"path": "/test", "min_version": "1.0.0", "client_version": "1.0.0"},
        {"Authorization": "Bearer wrong-token"},
    )
    assert status == 401, f"Expected 401 for invalid auth, got {status}"


def test_server_version_check_lower():
    status, _ = request({"path": "/test", "min_version": "2.0.0", "client_version": "1.0.0"}, HEADERS)
    assert status == 403, f"Expected 403 for client_version < min_version, got {status}"


def test_server_version_check_malformed():
    status, _ = request({"path": "/test", "min_version": "1.0.0", "client_version": "1.0a"}, HEADERS)
    assert status == 403, f"Expected 403 for malformed version, got {status}"


def test_randomized_semantic_versions():
    rng = random.SystemRandom()
    for _ in range(18):
        minimum = tuple(rng.randrange(0, 1000) for _ in range(3))
        client = tuple(rng.randrange(0, 1000) for _ in range(3))
        min_text = ".".join(map(str, minimum))
        client_text = ".".join(map(str, client))
        params = {"path": "/version/test", "min_version": min_text, "client_version": client_text}
        status, body = request(params, HEADERS)
        expected = 200 if client >= minimum else 403
        assert status == expected, f"For client={client_text}, minimum={min_text}, expected {expected}, got {status}: {body}"

    malformed = [
        "", "1", "1.2", "1.2.3.4", "v1.2.3", "1.2.x", "1.-2.3",
        "01.2.3", "1.02.3", "1.2.03", " 1.2.3", "1.2.3 ", "1..3",
        f"{rng.randrange(2, 99)}.{rng.randrange(2, 99)}.x{rng.randrange(10, 99)}",
    ]
    for bad in malformed:
        for field in ("min_version", "client_version"):
            params = {"path": "/bad/version", "min_version": "1.2.3", "client_version": "4.5.6"}
            params[field] = bad
            status, _ = request(params, HEADERS)
            assert status == 403, f"Malformed {field}={bad!r} should return 403, got {status}"


def test_server_success_normalization_and_random_paths():
    assert_success(
        {"path": "../../../etc/passwd", "min_version": "1.0.0", "client_version": "1.2.0"},
        "etc/passwd",
    )
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    for _ in range(16):
        pieces = []
        for _ in range(rng.randrange(3, 12)):
            if rng.randrange(3) == 0:
                pieces.append("../")
            else:
                pieces.append("".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 9))) + "/")
        value = ("/" if rng.randrange(2) else "") + "".join(pieces) + "end" + secrets.token_hex(3)
        major = rng.randrange(1, 500)
        assert_success(
            {"path": value, "min_version": f"{major}.0.0", "client_version": f"{major}.{rng.randrange(0, 500)}.{rng.randrange(0, 500)}"},
            expected_clean(value),
        )


def test_bench_results_exist_and_valid():
    assert os.path.isfile(BENCH_RESULTS), f"Benchmark results file missing: {BENCH_RESULTS}"
    with open(BENCH_RESULTS) as f:
        content = f.read().strip()
    try:
        time_taken = float(content)
    except ValueError:
        pytest.fail(f"Benchmark results file does not contain a valid float: {content!r}")
    assert time_taken > 0, "Benchmark time should be greater than 0."


def test_server_really_calls_submitted_shared_library():
    assert os.path.isfile(SERVER_FILE), "Missing /app/server.py"
    stop_listener()
    backup = SO_FILE + ".verifier-backup"
    shutil.copy2(SO_FILE, backup)
    token = "probe_" + secrets.token_hex(16)
    proc = None
    try:
        with tempfile.TemporaryDirectory() as temp:
            source = os.path.join(temp, "probe.c")
            probe = os.path.join(temp, "libfastparser.so")
            with open(source, "w") as f:
                f.write('#include <string.h>\nvoid clean_path(const char *in, char *out) { strcpy(out, "' + token + '"); }\n')
            result = subprocess.run(["gcc", "-shared", "-fPIC", source, "-o", probe], text=True, capture_output=True)
            assert result.returncode == 0, result.stderr
            shutil.copy2(probe, SO_FILE)
        proc = start_agent_server()
        value = "/dynamic/../../" + secrets.token_hex(8)
        assert_success({"path": value, "min_version": "7.8.9", "client_version": "7.8.9"}, token)
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_listener()
        if os.path.exists(backup):
            os.replace(backup, SO_FILE)
        start_agent_server()


def test_benchmark_script_makes_exactly_500_successful_requests():
    assert os.path.isfile(BENCH_FILE), "Benchmark script missing: /app/bench.py"
    stop_listener()
    state = {"total": 0, "valid": 0}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state["total"] += 1
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query, keep_blank_values=True)
            valid = (
                parsed.path == "/api/v1/normalize"
                and query == {
                    "path": ["/var/../etc/passwd"],
                    "min_version": ["1.0.0"],
                    "client_version": ["1.2.0"],
                }
                and self.headers.get("Authorization") == AUTH
            )
            if valid:
                state["valid"] += 1
                body = b'{"status": "success", "cleaned_path": "/var/etc/passwd"}'
                self.send_response(200)
            else:
                body = b'{"error": "invalid benchmark request"}'
                self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 8888), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run([sys.executable, BENCH_FILE], cwd=APP_DIR, text=True, capture_output=True, timeout=30)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        start_agent_server()

    assert result.returncode == 0, f"bench.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert state["total"] == 500, f"bench.py made {state['total']} requests instead of exactly 500"
    assert state["valid"] == 500, f"Only {state['valid']} of the 500 benchmark requests used the required valid URL and authorization"
    assert os.path.isfile(BENCH_RESULTS), "bench.py did not write /app/bench_results.txt"
    content = open(BENCH_RESULTS).read().strip()
    try:
        elapsed = float(content)
    except ValueError:
        pytest.fail(f"bench.py did not write a simple float: {content!r}")
    assert elapsed > 0, "Benchmark time should be greater than 0"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
