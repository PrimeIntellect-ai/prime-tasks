#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import signal
import string
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

PROJECT = "/home/user/waf_project"
PYTHON = "/home/user/venv/bin/python"
API_URL = "http://127.0.0.1:8000/analyze"


def post_json(url, payload, timeout=5):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def kill_port(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local = fields[1]
                        if int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    if inodes:
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
                        victims.add(int(name))
            except (FileNotFoundError, PermissionError):
                continue
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.5)


def start_api(port=8000):
    proc = subprocess.Popen(
        [PYTHON, "-m", "uvicorn", "api:app", "--host", "127.0.0.1", "--port", str(port)],
        cwd=PROJECT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    url = f"http://127.0.0.1:{port}/analyze"
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"FastAPI process exited early with code {proc.returncode}")
        try:
            post_json(url, {"data": "startup probe"}, timeout=0.5)
            return proc
        except Exception:
            time.sleep(0.15)
    proc.kill()
    pytest.fail("FastAPI service did not become reachable")


def stop_process(proc):
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    time.sleep(0.3)


def expected_waf(payload):
    state = 0
    for ch in payload:
        if state == 0 and ch == "S":
            state = 1
        elif state == 1 and ch == "E":
            state = 2
        elif state == 2 and ch == "L":
            state = 3
        elif state == 3 and ch == "E":
            state = 4
        elif state == 4 and ch == "C":
            state = 5
        elif state == 5 and ch == "T":
            return 1
        else:
            state = 0
    return 0


def test_complete_waf_project():
    build_path = os.path.join(PROJECT, "build.sh")
    lib_path = os.path.join(PROJECT, "libwaf.so")
    assert os.path.isfile(build_path), f"The file {build_path} does not exist."
    with open(build_path) as f:
        build_content = f.read()
    assert "-shared" in build_content, "The build.sh script is missing the '-shared' flag."
    assert "-fPIC" in build_content, "The build.sh script is missing the '-fPIC' flag."

    if os.path.lexists(lib_path):
        os.unlink(lib_path)
    subprocess.run(["bash", "./build.sh"], cwd=PROJECT, check=True, timeout=30)
    assert os.path.isfile(lib_path), "build.sh did not create libwaf.so"
    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libwaf.so is not an ELF file"
    elf = subprocess.run(
        ["readelf", "-h", lib_path], capture_output=True, text=True, check=True
    ).stdout
    assert "DYN (Shared object file)" in elf, "libwaf.so is not an ELF shared object"

    lib = ctypes.CDLL(lib_path)
    analyze = lib.analyze_payload
    analyze.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
    analyze.restype = ctypes.c_int
    rng = random.SystemRandom()
    samples = ["Hello World", "SELECT * FROM users"]
    alphabet = string.ascii_letters + string.digits + " /;_*"
    for _ in range(24):
        value = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 70)))
        if rng.randrange(2):
            at = rng.randrange(len(value) + 1)
            value = value[:at] + "SELECT" + value[at:]
        samples.append(value)
    for value in samples:
        raw = value.encode("ascii")
        assert analyze(raw, len(raw) * 42) == expected_waf(value)
        assert analyze(raw, len(raw) * 42 + 1) == -1

    signature_check = r'''
import ctypes
import api
found = False
for value in vars(api).values():
    if isinstance(value, ctypes.CDLL):
        try:
            fn = value.analyze_payload
        except Exception:
            continue
        if fn.argtypes == [ctypes.c_char_p, ctypes.c_uint32] and fn.restype is ctypes.c_int:
            found = True
assert found, "api.py did not expose a CDLL analyze_payload with the required ctypes signature"
print("SIGNATURE_OK")
'''
    checked = subprocess.run(
        [PYTHON, "-c", signature_check], cwd=PROJECT,
        capture_output=True, text=True, timeout=15
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr
    assert "SIGNATURE_OK" in checked.stdout

    test_script = "/home/user/test_waf.py"
    assert os.path.isfile(test_script), f"The file {test_script} does not exist."
    kill_port(8000)
    nonce = "verify-" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(24))
    expected_body = "GET / HTTP/1.1\nHost: example.com\nSELECT * FROM users;"
    observed = {}

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            observed["path"] = self.path
            observed["body"] = json.loads(self.rfile.read(length).decode("utf-8"))
            response = {"status": "malicious", "nonce": nonce}
            body = json.dumps(response, separators=(",", ":")).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    mock = ReusableHTTPServer(("127.0.0.1", 8000), Handler)
    thread = threading.Thread(target=mock.handle_request, daemon=True)
    thread.start()
    run_test = subprocess.run([PYTHON, test_script], cwd="/home/user", capture_output=True, text=True, timeout=15)
    thread.join(timeout=3)
    mock.server_close()
    assert run_test.returncode == 0, run_test.stdout + run_test.stderr
    assert observed.get("path") == "/analyze"
    assert observed.get("body") == {"data": expected_body}
    with open("/home/user/result.json") as f:
        captured_result = json.load(f)
    assert captured_result == {"status": "malicious", "nonce": nonce}, \
        "test_waf.py did not save the API's actual JSON response"

    actual_proc = start_api(8000)
    try:
        cases = ["Hello World", "SELECT * FROM users"]
        for _ in range(18):
            value = "".join(rng.choice(alphabet) for _ in range(rng.randint(4, 80)))
            if rng.randrange(2):
                at = rng.randrange(len(value) + 1)
                value = value[:at] + "SELECT" + value[at:]
            cases.append(value)
        for value in cases:
            response = post_json(API_URL, {"data": value})
            expected = "malicious" if expected_waf(value) else "safe"
            assert response == {"status": expected}, f"Wrong response for payload {value!r}: {response!r}"
    finally:
        stop_process(actual_proc)
        kill_port(8000)

    backup_path = lib_path + ".verifier-real"
    probe_path = os.path.join(PROJECT, ".verifier_probe.c")
    marker = "probe" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(28))
    if os.path.exists(backup_path):
        os.unlink(backup_path)
    os.replace(lib_path, backup_path)
    probe_proc = None
    try:
        with open(probe_path, "w") as f:
            f.write(
                '#include <stdint.h>\n#include <string.h>\n'
                'int analyze_payload(const char *p, uint32_t c) {\n'
                f'  if (strcmp(p, "{marker}") != 0) return -1;\n'
                '  return c == (uint32_t)(strlen(p) * 42) ? 1 : -1;\n}\n'
            )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", lib_path, probe_path],
            check=True, cwd=PROJECT, timeout=30
        )
        probe_proc = start_api(18000)
        probe_url = "http://127.0.0.1:18000/analyze"
        assert post_json(probe_url, {"data": marker}) == {"status": "malicious"}, \
            "api.py did not pass the payload and length*42 checksum to libwaf.so"
        other = "ordinary-" + "".join(rng.choice(string.ascii_lowercase) for _ in range(16))
        assert post_json(probe_url, {"data": other}) == {"status": "checksum_error"}, \
            "api.py did not call the C function or map its -1 result"
    finally:
        stop_process(probe_proc)
        if os.path.exists(lib_path):
            os.unlink(lib_path)
        if os.path.exists(backup_path):
            os.replace(backup_path, lib_path)
        if os.path.exists(probe_path):
            os.unlink(probe_path)

    final_proc = start_api(8000)
    final_run = subprocess.run([PYTHON, test_script], cwd="/home/user", capture_output=True, text=True, timeout=15)
    assert final_run.returncode == 0, final_run.stdout + final_run.stderr
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"The file {result_path} does not exist."
    try:
        with open(result_path) as f:
            final_result = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {result_path} does not contain valid JSON.")
    assert "status" in final_result, f"The JSON in {result_path} does not contain the 'status' key."
    assert final_result["status"] == "malicious", \
        f"Expected status 'malicious', but got '{final_result['status']}'."
    assert final_result == {"status": "malicious"}
    assert post_json(API_URL, {"data": "Hello World"}) == {"status": "safe"}
    assert post_json(API_URL, {"data": "SELECT * FROM users"}) == {"status": "malicious"}
    # Leave final_proc running, as required by the task.
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
