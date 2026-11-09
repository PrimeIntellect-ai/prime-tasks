#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import secrets
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

APP_DIR = "/home/user/app"
SO_FILE = os.path.join(APP_DIR, "libmathcore.so")
SERVER_FILE = os.path.join(APP_DIR, "server.py")
LOG_FILE = os.path.join(APP_DIR, "release_test.log")


def expected_value(x, y):
    return (x * x * x) + (y * y) - (x * y)


def fetch(path, timeout=5):
    with urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8").strip()


def test_shared_library_exists():
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} does not exist."

    # Preserve the original ELF assertion.
    with open(SO_FILE, "rb") as f:
        magic = f.read(4)
    assert magic == b'\x7fELF', f"File {SO_FILE} is not a valid ELF shared object."

    # It must actually be a loadable shared library exporting the required function.
    lib = ctypes.CDLL(SO_FILE)
    evaluate = lib.evaluate
    evaluate.argtypes = [ctypes.c_double, ctypes.c_double]
    evaluate.restype = ctypes.c_double
    for x, y in [(1.25, -2.5), (-3.5, 0.75), (6.0, 4.25)]:
        assert evaluate(x, y) == expected_value(x, y)


def test_server_declares_double_ffi_signature():
    assert os.path.isfile(SERVER_FILE), f"Server source {SERVER_FILE} does not exist."
    with open(SERVER_FILE, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SERVER_FILE)

    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {"CDLL", "PyDLL"}
        for node in ast.walk(tree)
    ), "server.py does not load the shared library with ctypes."

    assigned_attrs = {
        target.attr
        for node in ast.walk(tree)
        if isinstance(node, (ast.Assign, ast.AnnAssign))
        for target in ((node.targets if isinstance(node, ast.Assign) else [node.target]))
        if isinstance(target, ast.Attribute)
    }
    assert "argtypes" in assigned_attrs, "The evaluate function's argtypes are not set."
    assert "restype" in assigned_attrs, "The evaluate function's restype is not set."


def test_release_test_log():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original assertion, then ensure this is the raw expected body.
    expected_result = "Result: 61.0"
    assert expected_result in content, (
        f"Log file {LOG_FILE} does not contain the expected string "
        f"'{expected_result}'. Found: {content}"
    )
    assert content == expected_result, f"Expected raw curl output '{expected_result}', got '{content}'"


def test_server_eval_endpoint():
    # Preserve the original fixed endpoint assertion.
    url = "http://127.0.0.1:8080/eval?x=2.0&y=5.0"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode("utf-8").strip()
            expected_body = "Result: 23.0"
            assert expected_body in body, f"Expected response to contain '{expected_body}', got '{body}'"
            assert body == expected_body
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the server or fetch the URL: {e}")

    # Exercise values selected only after the agent has finished.
    rng = secrets.SystemRandom()
    cases = set()
    while len(cases) < 8:
        cases.add((rng.randint(-80, 80) / 4.0, rng.randint(-80, 80) / 4.0))
    for x, y in cases:
        status, body = fetch(f"/eval?x={x}&y={y}")
        expected_body = f"Result: {expected_value(x, y)}"
        assert status == 200
        assert body == expected_body, f"For x={x}, y={y}, expected '{expected_body}', got '{body}'"


def test_other_path_is_not_eval():
    with pytest.raises(urllib.error.HTTPError) as exc:
        urllib.request.urlopen("http://127.0.0.1:8080/not-eval?x=2&y=5", timeout=5)
    assert exc.value.code == 404


def test_handler_really_uses_c_evaluate(tmp_path):
    # Build an unpredictable replacement backend and import the submitted handler
    # in a separate process. Its response must change with the C implementation.
    nonce = secrets.randbelow(1_000_000) + 100_000
    probe_c = tmp_path / "probe.c"
    probe_so = tmp_path / "probe.so"
    probe_c.write_text(
        "double evaluate(double x, double y) { "
        f"return (x*x*x) + (y*y) - (x*y) + {nonce}.0; }}\n",
        encoding="utf-8",
    )
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(probe_so), str(probe_c)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Derive answers by executing the probe rather than trusting fixed constants.
    probe = ctypes.CDLL(str(probe_so))
    probe.evaluate.argtypes = [ctypes.c_double, ctypes.c_double]
    probe.evaluate.restype = ctypes.c_double

    runner = tmp_path / "runner.py"
    runner.write_text(
        "import importlib.util, socketserver, sys\n"
        "spec = importlib.util.spec_from_file_location('submitted_server', '/home/user/app/server.py')\n"
        "mod = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(mod)\n"
        "with socketserver.TCPServer(('127.0.0.1', int(sys.argv[1])), mod.MathHandler) as srv:\n"
        "    srv.serve_forever()\n",
        encoding="utf-8",
    )

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    backup = tmp_path / "original_libmathcore.so"
    shutil.copy2(SO_FILE, backup)
    proc = None
    try:
        os.replace(probe_so, SO_FILE)
        proc = subprocess.Popen(
            ["python3", str(runner), str(port)],
            cwd=APP_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        deadline = time.time() + 6
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"Submitted server could not start with the probe backend: {out}{err}")
            try:
                x, y = 1.25, -2.5
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/eval?x={x}&y={y}", timeout=0.5
                ) as response:
                    body = response.read().decode("utf-8").strip()
                    assert response.status == 200
                    assert body == f"Result: {probe.evaluate(x, y)}"
                    break
            except urllib.error.URLError as e:
                last_error = e
                time.sleep(0.1)
        else:
            pytest.fail(f"Probe server did not become ready: {last_error}")

        for x, y in [(-3.75, 2.25), (7.5, -1.5)]:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/eval?x={x}&y={y}", timeout=2
            ) as response:
                body = response.read().decode("utf-8").strip()
                assert response.status == 200
                assert body == f"Result: {probe.evaluate(x, y)}"
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        os.replace(backup, SO_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
