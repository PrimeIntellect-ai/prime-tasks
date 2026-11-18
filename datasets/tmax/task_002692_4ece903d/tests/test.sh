#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier controls the API server instance used by the integration run.
pkill -f 'python3.*api_server.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import socket
import subprocess
import sys
import time

WORKSPACE_DIR = "/home/user/workspace"


def test_libdecoder_compiled():
    lib_path = os.path.join(WORKSPACE_DIR, "libdecoder.so")
    assert os.path.exists(lib_path), f"Shared library {lib_path} was not compiled."
    assert os.path.isfile(lib_path), f"{lib_path} is not a file."


def test_sorter_compiled():
    sorter_path = os.path.join(WORKSPACE_DIR, "sorter")
    assert os.path.exists(sorter_path), f"Executable {sorter_path} was not compiled."
    assert os.path.isfile(sorter_path), f"{sorter_path} is not a file."
    assert os.access(sorter_path, os.X_OK), f"{sorter_path} is not executable."


def test_integration_test_script_exists():
    script_path = os.path.join(WORKSPACE_DIR, "integration_test.py")
    assert os.path.exists(script_path), f"Python script {script_path} was not created."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_result_log_exists_and_content():
    log_path = os.path.join(WORKSPACE_DIR, "test_result.log")
    assert os.path.exists(log_path), f"Result log {log_path} was not created."
    assert os.path.isfile(log_path), f"{log_path} is not a file."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"{log_path} is empty."


def reference_decode(value):
    temp = list(value)
    found = False
    for i in range(4):
        if found:
            break
        original = temp[i]
        for digit in "0123456789":
            temp[i] = digit
            checksum = sum((j + 1) * int(temp[j]) for j in range(4)) % 10
            if checksum == int(temp[4]):
                found = True
                break
        if not found:
            temp[i] = original
    return "".join(temp[:4])


def test_decoder_is_loadable_and_decodes_payloads():
    lib_path = os.path.join(WORKSPACE_DIR, "libdecoder.so")
    try:
        library = ctypes.CDLL(lib_path)
        decode = library.decode_payload
    except Exception as exc:
        raise AssertionError(f"Could not load decoder shared library: {exc}")

    decode.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    decode.restype = None
    rng = random.SystemRandom()
    samples = ["19340", "56780", "99996", "00000"]
    samples.extend("".join(str(rng.randrange(10)) for _ in range(5)) for _ in range(30))

    for sample in samples:
        output = ctypes.create_string_buffer(5)
        decode(sample.encode("ascii"), output)
        actual = output.value.decode("ascii")
        assert actual == reference_decode(sample), (
            f"decode_payload({sample!r}) returned {actual!r}, "
            f"expected {reference_decode(sample)!r}"
        )


def test_sorter_executes_and_sorts_descending():
    sorter_path = os.path.join(WORKSPACE_DIR, "sorter")
    rng = random.SystemRandom()
    values = [rng.randrange(10000) for _ in range(35)] + [0, 7, 9999, 7]
    input_text = "".join(f"{value:04d}\n" for value in values)
    result = subprocess.run(
        [sorter_path],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"sorter failed: {result.stderr}"
    expected = "".join(f"{value:04d}\n" for value in sorted(values, reverse=True))
    assert result.stdout == expected, (
        f"sorter output was incorrect. Expected {expected!r}, got {result.stdout!r}"
    )


def wait_for_server(process):
    deadline = time.time() + 10
    while time.time() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read()
            raise AssertionError(f"api_server.py exited before serving requests: {stderr}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("api_server.py did not bind to 127.0.0.1:8080")


def test_integration_script_runs_api_pipeline_and_writes_valid_diff():
    expected_path = os.path.join(WORKSPACE_DIR, "expected_output.txt")
    with open(expected_path, "r") as f:
        assert f.read() == "9999\n5678\n1234\n0000\n", "expected_output.txt was modified"

    server = subprocess.Popen(
        [sys.executable, os.path.join(WORKSPACE_DIR, "api_server.py")],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_server(server)
        run = subprocess.run(
            [sys.executable, os.path.join(WORKSPACE_DIR, "integration_test.py")],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run.returncode == 0, (
            f"integration_test.py failed with exit code {run.returncode}: {run.stderr}"
        )
    finally:
        server.terminate()
        try:
            _, server_stderr = server.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            _, server_stderr = server.communicate(timeout=5)

    assert 'GET /data' in server_stderr and ' 200 ' in server_stderr, (
        "integration_test.py did not successfully request /data from the API server"
    )

    log_path = os.path.join(WORKSPACE_DIR, "test_result.log")
    assert os.path.isfile(log_path), f"Result log {log_path} was not created."
    with open(log_path, "r") as f:
        content = f.read().strip()

    # The supplied decoder produces 7934, 5678, 5999, and 0000 for the API
    # payloads, so the sorted result differs from the canonical file. A valid
    # normal, context, unified, or equivalent textual diff must expose both
    # actual-only and expected-only records rather than claiming PASS.
    assert content and content != "PASS", "The differing outputs must produce a diff, not PASS."
    for value in ("7934", "5999", "9999", "1234"):
        assert value in content, f"Diff output is missing differing value {value}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
