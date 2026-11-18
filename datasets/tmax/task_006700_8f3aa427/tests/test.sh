#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import signal
import socket
import string
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

WORKSPACE_DIR = "/home/user/workspace"
PID_FILE = os.path.join(WORKSPACE_DIR, "server.pid")
SERVER_EXEC = os.path.join(WORKSPACE_DIR, "server")
LIBRARY = os.path.join(WORKSPACE_DIR, "libsolver.so")
MAKEFILE = os.path.join(WORKSPACE_DIR, "Makefile")
SERVER_SOURCE = os.path.join(WORKSPACE_DIR, "server.cpp")
SERVER_URL = "http://localhost:8123/verify"
PORT = 8123


def read_pid():
    assert os.path.exists(PID_FILE), f"PID file {PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID (found: {pid_str})."
    return int(pid_str)


def listening_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def process_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def assert_pid_is_server(pid):
    os.kill(pid, 0)
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert exe == os.path.realpath(SERVER_EXEC), f"PID {pid} runs {exe}, not {SERVER_EXEC}."
    assert listening_socket_inodes(PORT) & process_socket_inodes(pid), f"PID {pid} does not own the listening socket on port {PORT}."
    with open(f"/proc/{pid}/maps") as f:
        maps = f.read()
    assert os.path.realpath(LIBRARY) in maps, f"PID {pid} has not loaded {LIBRARY}."


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.1)


def start_server(extra_env=None, write_pid=True):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = WORKSPACE_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    if extra_env:
        env.update(extra_env)
    proc = subprocess.Popen(
        [SERVER_EXEC], cwd=WORKSPACE_DIR, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Server exited during startup with status {proc.returncode}.")
        if listening_socket_inodes(PORT) & process_socket_inodes(proc.pid):
            if write_pid:
                with open(PID_FILE, "w") as f:
                    f.write(str(proc.pid))
            return proc
        time.sleep(0.05)
    stop_pid(proc.pid)
    pytest.fail("Server did not listen on port 8123 within five seconds.")


def request(body, path="/verify", method="POST"):
    req = urllib.request.Request("http://localhost:8123" + path, data=body.encode(), method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")


def assert_response(body, expected_pass):
    status, response_body = request(body)
    expected_status = 200 if expected_pass else 400
    expected_body = '{"status": "pass"}' if expected_pass else '{"status": "fail"}'
    assert status == expected_status, f"For {body!r}, expected HTTP {expected_status}, got {status}: {response_body}"
    assert expected_body in response_body, f"Expected body to contain {expected_body!r}, got: {response_body}"
    assert response_body.strip() == expected_body, f"Expected exact response body {expected_body!r}, got: {response_body!r}"


def expected_solver(expr, manifest):
    values = {}
    for item in manifest.split(","):
        if ":" in item:
            key, value = item.split(":", 1)
            values[key] = int(value)
    for item in expr.split(","):
        if ">=" in item:
            key, value = item.split(">=", 1)
            if key not in values or values[key] < int(value):
                return False
        elif "==" in item:
            key, value = item.split("==", 1)
            if key not in values or values[key] != int(value):
                return False
    return True


def test_server_pid_running():
    """Verify that server.pid identifies the actual server process and listener."""
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {PID_FILE}) is not running.")
    assert_pid_is_server(pid)


def test_dynamic_linking():
    """Verify that the server executable dynamically links against libsolver.so."""
    assert os.path.exists(SERVER_EXEC), f"Server executable {SERVER_EXEC} does not exist."
    try:
        output = subprocess.check_output(["ldd", SERVER_EXEC], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running ldd on {SERVER_EXEC} failed: {e.output}")
    assert "libsolver.so" in output, "The server executable is not dynamically linked against libsolver.so."


def test_makefile_rebuilds_required_artifacts():
    assert os.path.isfile(MAKEFILE), "Makefile is missing."
    assert os.path.isfile(SERVER_SOURCE), "server.cpp is missing."
    with open(SERVER_SOURCE) as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]http_stub\.h[>\"]', source), "server.cpp does not use the provided http_stub.h."

    for target in ("all", "libsolver.so", "server"):
        result = subprocess.run(["make", "-n", "-B", target], cwd=WORKSPACE_DIR, text=True, capture_output=True)
        assert result.returncode == 0, f"Make target {target!r} is missing or invalid:\n{result.stdout}\n{result.stderr}"

    lib_plan = subprocess.check_output(["make", "-n", "-B", "libsolver.so"], cwd=WORKSPACE_DIR, text=True, stderr=subprocess.STDOUT)
    assert "-fPIC" in lib_plan, "The libsolver.so build does not compile with -fPIC."
    assert "-shared" in lib_plan, "The libsolver.so build does not create a shared library."
    server_plan = subprocess.check_output(["make", "-n", "-B", "server"], cwd=WORKSPACE_DIR, text=True, stderr=subprocess.STDOUT)
    assert "solver" in server_plan.lower(), "The server target does not link against libsolver.so."

    old_pid = read_pid()
    stop_pid(old_pid)
    for artifact in (SERVER_EXEC, LIBRARY):
        if os.path.lexists(artifact):
            os.unlink(artifact)
    build = subprocess.run(["make", "-B", "all"], cwd=WORKSPACE_DIR, text=True, capture_output=True, timeout=30)
    assert build.returncode == 0, f"make -B all failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(SERVER_EXEC) and os.access(SERVER_EXEC, os.X_OK), "Makefile did not build an executable server."
    assert os.path.isfile(LIBRARY), "Makefile did not build libsolver.so."

    server_elf = subprocess.check_output(["readelf", "-h", SERVER_EXEC], text=True)
    library_elf = subprocess.check_output(["readelf", "-h", LIBRARY], text=True)
    assert "ELF" in server_elf, "server is not an ELF executable."
    assert re.search(r"Type:\s+DYN", library_elf), "libsolver.so is not an ELF shared object."

    lib_symbols = subprocess.check_output(["nm", "-D", LIBRARY], text=True)
    server_symbols = subprocess.check_output(["nm", "-D", SERVER_EXEC], text=True)
    assert re.search(r"\b[TW]\s+evaluate_constraints$", lib_symbols, re.MULTILINE), "libsolver.so does not export evaluate_constraints."
    assert re.search(r"\bU\s+evaluate_constraints(?:@.*)?$", server_symbols, re.MULTILINE), "server does not dynamically import evaluate_constraints."
    start_server()


def test_library_implementation_on_generated_inputs():
    lib = ctypes.CDLL(LIBRARY)
    evaluate = lib.evaluate_constraints
    evaluate.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    evaluate.restype = ctypes.c_bool
    rng = random.SystemRandom()
    prefix = "direct_" + uuid.uuid4().hex[:10]
    for case in range(20):
        keys = [f"{prefix}_{case}_{i}" for i in range(4)]
        manifest_values = {key: rng.randrange(0, 50) for key in keys}
        manifest = ",".join(f"{key}:{value}" for key, value in manifest_values.items())
        constraints = []
        for key in keys:
            op = rng.choice([">=", "=="])
            constraints.append(f"{key}{op}{rng.randrange(0, 50)}")
        expr = ",".join(constraints)
        actual = bool(evaluate(expr.encode(), manifest.encode()))
        assert actual == expected_solver(expr, manifest), f"libsolver.so returned the wrong result for {expr!r}, {manifest!r}."


def test_server_really_calls_evaluate_constraints_with_parsed_fields():
    current_pid = read_pid()
    stop_pid(current_pid)
    token = uuid.uuid4().hex
    key = "probe_" + token
    wanted_expr = key + "==777"
    wanted_manifest = key + ":1"
    probe_cpp = "/tmp/solver_probe.cpp"
    probe_so = "/tmp/solver_probe.so"
    with open(probe_cpp, "w") as f:
        f.write('#include <cstring>\nextern "C" bool evaluate_constraints(const char* e, const char* m) { return std::strcmp(e, "' + wanted_expr + '") == 0 && std::strcmp(m, "' + wanted_manifest + '") == 0; }\n')
    subprocess.check_call(["g++", "-shared", "-fPIC", probe_cpp, "-o", probe_so])
    probe_proc = None
    try:
        probe_proc = start_server({"LD_PRELOAD": probe_so}, write_pid=False)
        # The real solver would fail this request, while the injected function passes it.
        assert_response(f"EXPR: {wanted_expr}\nMANIFEST: {wanted_manifest}", True)
        # The real solver would pass this request, while the injected function fails it.
        assert_response(f"EXPR: {wanted_expr}\nMANIFEST: {key}:777", False)
    finally:
        if probe_proc is not None:
            stop_pid(probe_proc.pid)
        start_server()


def test_http_pass_case():
    """Verify the original satisfied-constraints case."""
    data = b"EXPR: libA>=2\nMANIFEST: libA:3"
    req = urllib.request.Request(SERVER_URL, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        pytest.fail(f"Expected HTTP 200 but got {e.code}. Response body: {e.read().decode('utf-8')}")
    except Exception as e:
        pytest.fail(f"HTTP request failed: {e}")
    assert status == 200, f"Expected HTTP status 200, got {status}."
    assert '{"status": "pass"}' in body, f"Expected pass body, got: {body}"


def test_http_fail_case():
    """Verify the original unsatisfied-constraints case."""
    data = b"EXPR: libA>=2,libB==2\nMANIFEST: libA:3,libB:1"
    req = urllib.request.Request(SERVER_URL, data=data, method="POST")
    status = None
    body = ""
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        status = e.code
        body = e.read().decode("utf-8")
    except Exception as e:
        pytest.fail(f"HTTP request failed: {e}")
    assert status == 400, f"Expected HTTP status 400, got {status}."
    assert '{"status": "fail"}' in body, f"Expected fail body, got: {body}"


def test_generated_post_verify_cases():
    rng = random.SystemRandom()
    prefix = "http_" + uuid.uuid4().hex[:12]
    saw_pass = False
    saw_fail = False
    for case in range(30):
        keys = [f"{prefix}_{case}_{i}" for i in range(5)]
        manifest_values = {key: rng.randrange(0, 100) for key in keys}
        # Sometimes omit a constrained key to exercise missing dependencies.
        manifest_keys = keys[:-1] if case % 4 == 0 else keys
        manifest = ",".join(f"{key}:{manifest_values[key]}" for key in manifest_keys)
        constraints = []
        for i, key in enumerate(keys):
            op = ">=" if (case + i) % 2 == 0 else "=="
            if case % 3 == 0 and key in manifest_values:
                threshold = manifest_values[key] if op == "==" else max(0, manifest_values[key] - 1)
            else:
                threshold = rng.randrange(0, 100)
            constraints.append(f"{key}{op}{threshold}")
        expr = ",".join(constraints)
        expected = expected_solver(expr, manifest)
        saw_pass |= expected
        saw_fail |= not expected
        assert_response(f"EXPR: {expr}\nMANIFEST: {manifest}", expected)

    # Explicit generated cases ensure both result branches regardless of random values.
    pass_key = prefix + "_guaranteed_pass"
    fail_key = prefix + "_guaranteed_fail"
    assert_response(f"EXPR: {pass_key}>=17\nMANIFEST: {pass_key}:18", True)
    assert_response(f"EXPR: {fail_key}==31\nMANIFEST: {fail_key}:30", False)
    assert_pid_is_server(read_pid())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
