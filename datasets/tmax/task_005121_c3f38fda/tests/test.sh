#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

MATH_DIR = "/home/user/math_lib"
CI_DIR = "/home/user/ci"

ORIGINAL_VECTORS = [
    {"id": "test_1", "size": 3, "matrix": [1, 2, 3, 4, 5, 6, 7, 8, 9]},
    {"id": "test_2", "size": 2, "matrix": [10, -5, 3, 20]},
    {"id": "test_3", "size": 4, "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]},
]
ORIGINAL_RESULTS = [
    {"id": "test_1", "trace": 15},
    {"id": "test_2", "trace": 30},
    {"id": "test_3", "trace": 4},
]


def trace_for(case):
    n = case["size"]
    return sum(case["matrix"][i * n + i] for i in range(n))


def program_input(n, values):
    rows = [str(n)]
    for i in range(n):
        rows.append(" ".join(str(x) for x in values[i * n:(i + 1) * n]))
    return "\n".join(rows) + "\n"


def assert_trace_program(binary, n, values, use_valgrind=False):
    command = [binary]
    if use_valgrind:
        command = [
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all", "--error-exitcode=1", binary,
        ]
    result = subprocess.run(
        command,
        input=program_input(n, values),
        capture_output=True,
        text=True,
        timeout=15,
    )
    expected = sum(values[i * n + i] for i in range(n))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(expected), (
        f"Incorrect trace for {n}x{n} matrix: expected {expected}, "
        f"got {result.stdout!r}; stderr={result.stderr!r}"
    )


def test_phase1_patch_exists_and_recreates_submission():
    patch_file = f"{MATH_DIR}/fix.patch"
    assert os.path.isfile(patch_file), f"Patch file {patch_file} is missing"

    orig_file = f"{MATH_DIR}/matrix_trace.c.orig"
    c_file = f"{MATH_DIR}/matrix_trace.c"
    assert os.path.isfile(orig_file), "Original C file is missing"
    assert os.path.isfile(c_file), "Modified C file is missing"

    # Preserve the original clean-application assertion.
    result = subprocess.run(
        ["patch", "--dry-run", orig_file, "-i", patch_file],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Patch does not apply cleanly:\n{result.stderr}\n{result.stdout}"

    # Applying the patch must actually produce the submitted source file.
    with tempfile.TemporaryDirectory() as td:
        patched = os.path.join(td, "matrix_trace.c.orig")
        shutil.copyfile(orig_file, patched)
        applied = subprocess.run(
            ["patch", "--batch", patched, "-i", patch_file],
            capture_output=True,
            text=True,
        )
        assert applied.returncode == 0, f"Patch failed when applied:\n{applied.stderr}\n{applied.stdout}"
        with open(patched, "rb") as f:
            patched_bytes = f.read()
        with open(c_file, "rb") as f:
            submitted_bytes = f.read()
        assert patched_bytes == submitted_bytes, "fix.patch does not produce the submitted matrix_trace.c"


def test_phase1_c_code_fixed():
    c_file = f"{MATH_DIR}/matrix_trace.c"
    assert os.path.isfile(c_file), "Modified C file is missing"

    binary = f"{MATH_DIR}/matrix_trace_test"
    compile_result = subprocess.run(
        ["gcc", c_file, "-o", binary],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"C code fails to compile:\n{compile_result.stderr}"

    cases = [
        (1, [-17]),
        (2, [1, 2, 3, 4]),
        (3, [8, -4, 12, 7, 19, 2, -6, 5, -11]),
        (5, [((i * 17 + 9) % 41) - 20 for i in range(25)]),
    ]
    for n, values in cases:
        assert_trace_program(binary, n, values, use_valgrind=True)

    required_binary = f"{MATH_DIR}/matrix_trace"
    assert os.path.isfile(required_binary), "Compiled matrix_trace binary is missing"
    assert os.access(required_binary, os.X_OK), "Compiled matrix_trace binary is not executable"
    with open(required_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "matrix_trace is not a compiled executable"
    for n, values in cases:
        assert_trace_program(required_binary, n, values)


def run_ci_script(script_file):
    result = subprocess.run(
        [script_file],
        cwd=CI_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"run_tests.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"


def load_results():
    results_file = f"{CI_DIR}/results.json"
    assert os.path.isfile(results_file), f"Results file {results_file} is missing"
    try:
        with open(results_file, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {results_file} is not valid JSON: {exc}")


def test_phase2_script_execution_and_results():
    script_file = f"{CI_DIR}/run_tests.sh"
    vectors_file = f"{CI_DIR}/test_vectors.json"
    results_file = f"{CI_DIR}/results.json"
    assert os.path.isfile(script_file), f"Script {script_file} is missing"
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable"
    with open(script_file, "r") as f:
        script_content = f.read()
    assert "jq" in script_content, "run_tests.sh must use jq to parse the test vectors"

    with open(vectors_file, "r") as f:
        assert json.load(f) == ORIGINAL_VECTORS, "The supplied test_vectors.json was modified"

    dynamic_vectors = [
        {"id": "generated_alpha", "size": 1, "matrix": [73]},
        {"id": "generated_negative", "size": 3, "matrix": [-9, 4, 8, 11, -17, 2, 6, 5, 31]},
        {"id": "generated_large", "size": 5,
         "matrix": [((i * 29 + 7) % 101) - 50 for i in range(25)]},
        {"id": "generated_mixed", "size": 2, "matrix": [1234, -88, 45, -987]},
    ]
    dynamic_expected = [
        {"id": case["id"], "trace": trace_for(case)} for case in dynamic_vectors
    ]

    try:
        if os.path.exists(results_file):
            os.remove(results_file)
        run_ci_script(script_file)
        results = load_results()
        assert results == ORIGINAL_RESULTS, f"Results JSON does not match expected output. Got: {results}"

        with open(vectors_file, "w") as f:
            json.dump(dynamic_vectors, f)
        if os.path.exists(results_file):
            os.remove(results_file)
        run_ci_script(script_file)
        results = load_results()
        assert results == dynamic_expected, (
            f"run_tests.sh did not calculate results from the supplied vectors. Got: {results}"
        )
    finally:
        with open(vectors_file, "w") as f:
            json.dump(ORIGINAL_VECTORS, f, indent=2)
        rerun = subprocess.run([script_file], cwd=CI_DIR, capture_output=True, text=True, timeout=20)
        assert rerun.returncode == 0, f"run_tests.sh failed while restoring results: {rerun.stderr}"


class BackendHandler(BaseHTTPRequestHandler):
    token = ""

    def do_GET(self):
        body = (self.token + "|" + self.path).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def test_phase3_nginx_config():
    conf_file = f"{CI_DIR}/proxy.conf"
    assert os.path.isfile(conf_file), f"Nginx config {conf_file} is missing"

    result = subprocess.run(
        ["nginx", "-t", "-c", conf_file],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Nginx config syntax test failed:\n{result.stderr}"

    with open(conf_file, "r") as f:
        content = f.read()

    assert "pid /home/user/ci/nginx.pid;" in content or "pid\t/home/user/ci/nginx.pid;" in content or "pid  /home/user/ci/nginx.pid;" in content, "Config missing required pid directive"
    assert "/home/user/ci/error.log" in content, "Config missing required error_log directive"
    assert "/home/user/ci/access.log" in content, "Config missing required access_log directive"
    assert "127.0.0.1:8080" in content, "Config not listening on 127.0.0.1:8080"
    assert "proxy_pass http://127.0.0.1:9090" in content or "proxy_pass http://127.0.0.1:9090/" in content, "Config missing proxy_pass to 127.0.0.1:9090"
    assert "user " not in content, "Config must not contain 'user' directive (unprivileged)"

    BackendHandler.token = "proxy-verification-token-8f29"
    backend = ThreadingHTTPServer(("127.0.0.1", 9090), BackendHandler)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()

    account = pwd.getpwnam("user")
    def drop_privileges():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    nginx = None
    try:
        nginx = subprocess.Popen(
            ["nginx", "-c", conf_file, "-g", "daemon off;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=drop_privileges,
        )
        response = None
        last_error = None
        for _ in range(30):
            if nginx.poll() is not None:
                out, err = nginx.communicate()
                pytest.fail(f"Nginx failed to start unprivileged:\n{out}\n{err}")
            try:
                with urllib.request.urlopen(
                    "http://127.0.0.1:8080/report?case=runtime", timeout=1
                ) as r:
                    response = r.read().decode()
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert response == BackendHandler.token + "|/report?case=runtime", (
            f"/report was not proxied to the backend: {last_error or response!r}"
        )
    finally:
        if nginx is not None and nginx.poll() is None:
            nginx.terminate()
            try:
                nginx.wait(timeout=5)
            except subprocess.TimeoutExpired:
                nginx.kill()
                nginx.wait(timeout=5)
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
