#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

WORKSPACE_DIR = "/home/user/workspace"
CI_RUN_SCRIPT = os.path.join(WORKSPACE_DIR, "ci_run.sh")
CI_REPORT = os.path.join(WORKSPACE_DIR, "ci_report.txt")
LIB_DIR = os.path.join(WORKSPACE_DIR, "lib")
LIB_SO = os.path.join(LIB_DIR, "libverify.so")
VERIFY_C = os.path.join(LIB_DIR, "verify.c")
CLIENT_DIR = os.path.join(WORKSPACE_DIR, "expr_client")
CARGO_TOML = os.path.join(CLIENT_DIR, "Cargo.toml")
MOCK_API = os.path.join(WORKSPACE_DIR, "mock_api.py")


def test_files_exist():
    """Check that the required files were created."""
    assert os.path.exists(CI_RUN_SCRIPT), f"{CI_RUN_SCRIPT} does not exist."
    assert os.access(CI_RUN_SCRIPT, os.X_OK), f"{CI_RUN_SCRIPT} is not executable."
    assert os.path.exists(LIB_SO), f"{LIB_SO} does not exist."
    assert os.path.exists(CARGO_TOML), f"{CARGO_TOML} does not exist."
    assert os.path.exists(MOCK_API), f"{MOCK_API} does not exist."
    assert os.path.exists(VERIFY_C), f"{VERIFY_C} does not exist."


def test_ci_run_execution():
    """Run ci_run.sh and verify its output."""
    if os.path.exists(CI_REPORT):
        os.remove(CI_REPORT)

    try:
        result = subprocess.run(
            [CI_RUN_SCRIPT],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {CI_RUN_SCRIPT} timed out.")

    assert result.returncode == 0, (
        f"{CI_RUN_SCRIPT} failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.exists(CI_REPORT), f"{CI_REPORT} was not created by {CI_RUN_SCRIPT}."

    with open(CI_REPORT, "r") as f:
        content = f.read().strip()

    expected_content = "SUCCESS: id=42, valid=true"
    assert content == expected_content, (
        f"Expected '{expected_content}' in {CI_REPORT}, but got '{content}'"
    )


def test_c_artifacts_are_real_and_export_checksum():
    elf = subprocess.run(
        ["readelf", "-h", LIB_SO], capture_output=True, text=True
    )
    assert elf.returncode == 0, f"libverify.so is not an ELF shared library:\n{elf.stderr}"
    assert "DYN (Shared object file)" in elf.stdout, "libverify.so is not a shared object"

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", LIB_SO], capture_output=True, text=True
    )
    assert symbols.returncode == 0, symbols.stderr
    assert any(line.split()[-1] == "calculate_checksum" for line in symbols.stdout.splitlines()), (
        "libverify.so does not export calculate_checksum"
    )

    # Load and invoke the submitted library in a child process so a defective
    # binary cannot crash the verifier itself.
    probe = subprocess.run(
        [
            "python3",
            "-c",
            "import ctypes,sys; "
            "x=ctypes.CDLL(sys.argv[1]).calculate_checksum; "
            "x.argtypes=[ctypes.c_char_p]; x.restype=ctypes.c_uint32; "
            "print(x(b'verifier-probe'))",
            LIB_SO,
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert probe.returncode == 0, f"calculate_checksum could not be invoked:\n{probe.stderr}"
    int(probe.stdout.strip())

    # The requested C source must itself compile into a library with the symbol.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "libverify.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", VERIFY_C, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"verify.c does not compile:\n{result.stderr}"
        symbols = subprocess.run(
            ["nm", "-D", "--defined-only", rebuilt], capture_output=True, text=True
        )
        assert symbols.returncode == 0
        assert any(line.split()[-1] == "calculate_checksum" for line in symbols.stdout.splitlines())


def test_mock_api_serves_required_task():
    proc = subprocess.Popen(
        ["python3", MOCK_API],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    expected = '{"id": 42, "expression": "15 * 3 + 2", "checksum": 3283}'
    try:
        body = None
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"mock_api.py exited early.\nSTDOUT:\n{out}\nSTDERR:\n{err}")
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080/task", timeout=1) as response:
                    assert response.status == 200
                    body = response.read().decode("utf-8")
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert body is not None, f"mock API did not become reachable: {last_error}"
        assert body == expected, f"Unexpected /task response: {body!r}"
        assert json.loads(body) == {
            "id": 42,
            "expression": "15 * 3 + 2",
            "checksum": 3283,
        }
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def _build_client():
    env = os.environ.copy()
    env["LIBRARY_PATH"] = LIB_DIR + os.pathsep + env.get("LIBRARY_PATH", "")
    result = subprocess.run(
        ["cargo", "build", "--manifest-path", CARGO_TOML, "--message-format=json"],
        cwd=CLIENT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust client did not compile.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact":
            target = message.get("target", {})
            if "bin" in target.get("kind", []) and message.get("executable"):
                executables.append(message["executable"])
    assert executables, "cargo did not produce a Rust binary target"
    return executables[-1]


class _TaskHandler(BaseHTTPRequestHandler):
    payload = b""
    seen_paths = []

    def do_GET(self):
        type(self).seen_paths.append(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(type(self).payload)))
        self.end_headers()
        self.wfile.write(type(self).payload)

    def log_message(self, fmt, *args):
        pass


def _run_client_case(executable, task, expected_report, env):
    _TaskHandler.payload = json.dumps(task, separators=(",", ":")).encode("utf-8")
    _TaskHandler.seen_paths = []
    server = ThreadingHTTPServer(("127.0.0.1", 8080), _TaskHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.exists(CI_REPORT):
            os.remove(CI_REPORT)
        result = subprocess.run(
            [executable],
            cwd=WORKSPACE_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Rust client failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert "/task" in _TaskHandler.seen_paths, "Rust client did not request GET /task"
        assert os.path.exists(CI_REPORT), "Rust client did not create ci_report.txt"
        with open(CI_REPORT, "r") as f:
            assert f.read().strip() == expected_report
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_rust_client_evaluates_input_and_calls_c_ffi():
    executable = _build_client()
    rng = random.SystemRandom()
    a, b, c, d = [rng.randrange(2, 25) for _ in range(4)]
    expression = f"{a} + {b} * {c} + {d}"
    result_value = a + b * c + d
    verification = f"id:42,result:{result_value}"
    mask = rng.randrange(10000, 2**31)
    checksum = (sum(verification.encode("ascii")) ^ mask) & 0xFFFFFFFF

    with tempfile.TemporaryDirectory() as td:
        spy_c = os.path.join(td, "spy.c")
        spy_so = os.path.join(td, "libverify.so")
        log_path = os.path.join(td, "ffi.log")
        with open(spy_c, "w") as f:
            f.write(f'''#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\nuint32_t calculate_checksum(const char *input) {{\n    uint32_t sum = 0;\n    const unsigned char *p = (const unsigned char *)input;\n    while (*p) sum += *p++;\n    const char *path = getenv("VERIFY_LOG");\n    if (path) {{ FILE *fp = fopen(path, "a"); if (fp) {{ fprintf(fp, "%s\\n", input); fclose(fp); }} }}\n    return sum ^ {mask}u;\n}}\n''')
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", spy_c, "-o", spy_so],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert built.returncode == 0, built.stderr

        backup = os.path.join(td, "submitted-libverify.so")
        shutil.copy2(LIB_SO, backup)
        try:
            shutil.copy2(spy_so, LIB_SO)
            env = os.environ.copy()
            env["LD_LIBRARY_PATH"] = LIB_DIR + os.pathsep + env.get("LD_LIBRARY_PATH", "")
            env["VERIFY_LOG"] = log_path

            task = {"id": 42, "expression": expression, "checksum": checksum}
            _run_client_case(executable, task, "SUCCESS: id=42, valid=true", env)
            with open(log_path, "r") as f:
                assert f.read().splitlines() == [verification], (
                    "Client did not pass the evaluated id/result string to calculate_checksum"
                )

            os.remove(log_path)
            task["checksum"] = (checksum + 1) & 0xFFFFFFFF
            _run_client_case(executable, task, "FAILURE", env)
            with open(log_path, "r") as f:
                assert f.read().splitlines() == [verification], (
                    "Client did not invoke calculate_checksum for a mismatching checksum"
                )
        finally:
            shutil.copy2(backup, LIB_SO)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
