#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import pytest

HOME = "/home/user"
SO_PATH = os.path.join(HOME, "libvm.so")
API_PATH = os.path.join(HOME, "api.py")


def expected_value(code):
    total = 0
    for i in range(0, len(code), 2):
        value = int(code[i + 1])
        total += value if code[i] == "P" else -value
    return total


def random_code():
    count = 3 + secrets.randbelow(8)
    return "".join(("P" if secrets.randbelow(2) else "M") + str(secrets.randbelow(10)) for _ in range(count))


def request(code, timeout=2):
    query = urllib.parse.urlencode({"code": code})
    url = "http://127.0.0.1:8080/eval?" + query
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8").strip()


def listening_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[1].upper() == wanted and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def wait_for_server(proc, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"api.py exited early with status {proc.returncode}")
        try:
            request("P1", timeout=0.3)
            return
        except Exception:
            time.sleep(0.1)
    pytest.fail("api.py did not start listening on port 8080")


def test_libvm_so_exists():
    """Test that the shared library was built."""
    assert os.path.isfile(SO_PATH), f"Shared library missing: {SO_PATH}. Did you run make?"


def test_libvm_is_loadable_and_evaluates_dynamic_inputs():
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libvm.so is not an ELF shared library"

    lib = ctypes.CDLL(SO_PATH)
    evaluate = lib.evaluate
    evaluate.argtypes = [ctypes.c_char_p]
    evaluate.restype = ctypes.c_int

    for _ in range(12):
        code = random_code()
        assert evaluate(code.encode("utf-8")) == expected_value(code)


def test_result_log_content():
    """Test that result.log contains the raw successful API response."""
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}. Did you make the curl request and save the output?"

    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "9", f"Expected result.log to contain '9', but found '{content}'"

    with open(log_path, "rb") as f:
        assert f.read() == b"9", "result.log must contain strictly the raw response text '9'"


def test_api_server_running_and_fixed():
    """Keep the original live API assertion and verify api.py owns the listener."""
    pids = listening_pids()
    assert pids, "No process is listening on port 8080"
    assert any(
        "api.py" in open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
        for pid in pids
    ), "The process listening on port 8080 was not started from api.py"

    url = "http://127.0.0.1:8080/eval?code=P5M2P1"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            body = response.read().decode("utf-8").strip()
    except Exception as e:
        pytest.fail(f"Failed to reach API server at {url} or server crashed: {e}")

    assert status == 200, f"Expected HTTP 200 OK, got {status}"
    assert body == "4", f"Expected API to return '4' for P5M2P1, got '{body}'"

    for _ in range(12):
        code = random_code()
        status, body = request(code)
        assert status == 200
        assert body == str(expected_value(code)), f"Wrong API result for dynamically generated code {code}"


def test_api_artifact_has_ffi_bindings_and_runs_itself():
    check = r'''import ctypes, importlib.util, os
os.chdir("/home/user")
spec = importlib.util.spec_from_file_location("submitted_api", "/home/user/api.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.lib.evaluate.argtypes == [ctypes.c_char_p]
assert mod.lib.evaluate.restype is ctypes.c_int
assert os.path.realpath(mod.lib._name) == "/home/user/libvm.so"
'''
    completed = subprocess.run([sys.executable, "-c", check], capture_output=True, text=True, timeout=5)
    assert completed.returncode == 0, "api.py does not configure the required ctypes bindings: " + completed.stderr

    # Stop the already-validated submitted server, then execute api.py directly so
    # the dynamic checks cannot be satisfied by an unrelated replacement daemon.
    old_pids = listening_pids()
    assert old_pids
    for pid in old_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while listening_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listening_pids():
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while listening_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_pids(), "Could not stop the old API listener"

    out = open("/tmp/submitted_api.out", "ab")
    proc = subprocess.Popen(
        [sys.executable, API_PATH],
        cwd=HOME,
        stdout=out,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_server(proc)

    for _ in range(16):
        code = random_code()
        status, body = request(code)
        assert status == 200
        assert body == str(expected_value(code)), f"api.py returned the wrong result for {code}"
    assert proc.poll() is None, "api.py did not remain running in the background"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
