#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import signal
import socket
import subprocess
import time
import urllib.request

WORKSPACE = "/home/user/workspace"
API = f"{WORKSPACE}/api"
LIBDIR = f"{WORKSPACE}/c_math/build"
LIB = f"{LIBDIR}/libcmath.so"


def merged_env(libdir=LIBDIR):
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = libdir + ((":" + old) if old else "")
    return env


def port_open():
    try:
        with socket.create_connection(("127.0.0.1", 3000), timeout=0.25):
            return True
    except OSError:
        return False


def stop_leftover_server():
    subprocess.run(
        ["pkill", "-f", "/home/user/workspace/api/target/debug/api"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    deadline = time.time() + 5
    while port_open() and time.time() < deadline:
        time.sleep(0.1)


def start_server(libdir):
    proc = subprocess.Popen(
        [f"{API}/target/debug/api"],
        cwd=WORKSPACE,
        env=merged_env(libdir),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise AssertionError(f"API server exited during startup. stdout={out!r}, stderr={err!r}")
        if port_open():
            return proc
        time.sleep(0.1)
    os.killpg(proc.pid, signal.SIGTERM)
    raise AssertionError("API server did not listen on 127.0.0.1:3000")


def stop_server(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)


def post(path, a, b):
    request = urllib.request.Request(
        f"http://127.0.0.1:3000/{path}",
        data=json.dumps({"a": a, "b": b}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        assert response.status == 200
        body = json.loads(response.read().decode())
    assert isinstance(body.get("result"), int), body
    return body["result"]


def test_shared_library_built():
    assert os.path.isfile(LIB), f"Shared library not found at {LIB}. Did you compile the CMake project?"
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libcmath.so is not an ELF shared library"

    symbols = subprocess.run(["nm", "-D", LIB], capture_output=True, text=True, check=True).stdout
    assert re.search(r"\badd$", symbols, re.MULTILINE), "libcmath.so does not export add"
    assert re.search(r"\bsub$", symbols, re.MULTILINE), "libcmath.so does not export sub"

    library = ctypes.CDLL(LIB)
    library.add.argtypes = [ctypes.c_int, ctypes.c_int]
    library.add.restype = ctypes.c_int
    library.sub.argtypes = [ctypes.c_int, ctypes.c_int]
    library.sub.restype = ctypes.c_int
    rng = random.Random(0xC0A7)
    for _ in range(25):
        a = rng.randrange(-1000, 1000)
        b = rng.randrange(-1000, 1000)
        assert library.add(a, b) == a + b
        assert library.sub(a, b) == a - b


def test_build_rs_exists_and_correct():
    build_rs_path = f"{API}/build.rs"
    assert os.path.isfile(build_rs_path), f"build.rs not found at {build_rs_path}."
    with open(build_rs_path, "r") as f:
        content = f.read()
    assert "cargo:rustc-link-search" in content, "build.rs is missing cargo:rustc-link-search instruction."
    assert "cargo:rustc-link-lib" in content, "build.rs is missing cargo:rustc-link-lib instruction."


def test_e2e_test_exists_and_correct():
    test_path = f"{API}/tests/e2e_test.rs"
    assert os.path.isfile(test_path), f"e2e_test.rs not found at {test_path}."
    with open(test_path, "r") as f:
        content = f.read()
    assert "proptest" in content, "e2e_test.rs does not seem to use proptest."
    assert "reqwest" in content, "e2e_test.rs does not seem to use reqwest."
    assert "test_add_sub_inverse" in content, "e2e_test.rs is missing the test_add_sub_inverse test."

    compact = re.sub(r"\s+", "", content)
    assert re.search(r"proptest!", compact), "The test must be defined using proptest."
    assert re.search(r"-1000(?:i32)?\.\.1000", compact), "The generated values must use the -1000..1000 range."
    assert "reqwest::blocking::Client" in content or "blocking::Client" in content
    assert "127.0.0.1:3000/add" in content
    assert "127.0.0.1:3000/sub" in content


def test_run_all_script():
    script_path = f"{WORKSPACE}/run_all.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        script = f.read()
    assert "LD_LIBRARY_PATH" in script
    assert "cargo run" in script and "api/Cargo.toml" in script
    assert re.search(r"\bsleep\s+2(?:\.0*)?\b", script)
    assert "cargo test" in script and "--test e2e_test" in script
    assert re.search(r"\bkill\b", script)
    assert "SUCCESS" in script and "FAILED" in script

    status_path = f"{WORKSPACE}/status.txt"
    if os.path.exists(status_path):
        os.unlink(status_path)
    stop_leftover_server()

    result = subprocess.run(
        [script_path], capture_output=True, text=True, cwd=WORKSPACE, timeout=600
    )
    assert result.returncode == 0, f"run_all.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(status_path), f"status.txt not found at {status_path}."
    with open(status_path, "r") as f:
        status_content = f.read()
    assert status_content == "SUCCESS\n" or status_content == "SUCCESS", f"Expected status.txt to contain 'SUCCESS', but got {status_content!r}."

    still_running = port_open()
    if still_running:
        stop_leftover_server()
    assert not still_running, "run_all.sh did not terminate the background API server"


def test_project_really_builds_and_api_is_correct():
    build = subprocess.run(
        ["cargo", "build", "--manifest-path", "api/Cargo.toml"],
        cwd=WORKSPACE,
        env=merged_env(),
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert build.returncode == 0, f"Cargo build failed. stdout={build.stdout}\nstderr={build.stderr}"
    assert os.path.isfile(f"{API}/target/debug/api")

    stop_leftover_server()
    proc = start_server(LIBDIR)
    try:
        rng = random.Random(0xADD5AB)
        for _ in range(30):
            a = rng.randrange(-1000, 1000)
            b = rng.randrange(-1000, 1000)
            total = post("add", a, b)
            assert total == a + b
            assert post("sub", total, b) == a
    finally:
        stop_server(proc)


def test_property_test_passes_real_server_and_detects_broken_inverse():
    faulty_dir = "/tmp/faulty_cmath"
    os.makedirs(faulty_dir, exist_ok=True)
    faulty_c = f"{faulty_dir}/cmath.c"
    with open(faulty_c, "w") as f:
        f.write("int add(int a,int b){return a+b+1;} int sub(int a,int b){return a-b;}\n")
    compile_result = subprocess.run(
        ["cc", "-shared", "-fPIC", faulty_c, "-o", f"{faulty_dir}/libcmath.so"],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    test_cmd = ["cargo", "test", "--manifest-path", "api/Cargo.toml", "--test", "e2e_test"]

    stop_leftover_server()
    broken_server = start_server(faulty_dir)
    try:
        assert post("add", 17, 4) == 22, "The deliberately faulty library was not loaded"
        broken = subprocess.run(
            test_cmd,
            cwd=WORKSPACE,
            env=merged_env(),
            capture_output=True,
            text=True,
            timeout=300,
        )
        assert broken.returncode != 0, "The submitted E2E property test passed against a deliberately incorrect add implementation"
    finally:
        stop_server(broken_server)

    real_server = start_server(LIBDIR)
    try:
        good = subprocess.run(
            test_cmd,
            cwd=WORKSPACE,
            env=merged_env(),
            capture_output=True,
            text=True,
            timeout=300,
        )
        assert good.returncode == 0, f"E2E property test failed against the real API. stdout={good.stdout}\nstderr={good.stderr}"
        combined = good.stdout + good.stderr
        assert "test_add_sub_inverse" in combined
    finally:
        stop_server(real_server)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
