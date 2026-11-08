#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import secrets
import shutil
import string
import subprocess

PROJECT_DIR = "/home/user/project"
REVERSER = os.path.join(PROJECT_DIR, "reverser")
REAL_REVERSER = "/tmp/verifier_reverser_real"
TRACE_DIR = "/tmp/reverser_trace"
WRAPPER_HASH = None


def test_makefile_compiles():
    if os.path.exists(REVERSER):
        os.remove(REVERSER)

    result = subprocess.run(["make"], cwd=PROJECT_DIR, capture_output=True)
    assert result.returncode == 0, f"Make failed with error: {result.stderr.decode()}"
    assert os.path.isfile(REVERSER), "Makefile did not produce an executable named 'reverser'"
    assert os.access(REVERSER, os.X_OK), "'reverser' binary is not executable"
    with open(REVERSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile did not produce a compiled executable"


def test_reverser_logic():
    assert os.path.isfile(REVERSER), "reverser binary is missing, cannot test logic"

    result = subprocess.run([REVERSER], input=b"hello", capture_output=True)
    assert result.stdout == b"olleh", f"Expected 'olleh', got {result.stdout!r}"

    alphabet = (string.ascii_letters + string.digits + string.punctuation + " ").encode()
    for _ in range(25):
        length = secrets.randbelow(4096) + 1
        value = bytes(alphabet[secrets.randbelow(len(alphabet))] for _ in range(length))
        result = subprocess.run([REVERSER], input=value, capture_output=True)
        assert result.returncode == 0, "reverser failed on a generated input"
        assert result.stdout == value[::-1], "reverser produced an incorrect result for a generated input"


def install_tracing_wrapper():
    global WRAPPER_HASH
    shutil.copy2(REVERSER, REAL_REVERSER)
    wrapper = r'''#!/usr/bin/python3
import fcntl
import os

trace_dir = "/tmp/reverser_trace"
os.makedirs(trace_dir, exist_ok=True)
data = b""
while True:
    chunk = os.read(0, 65536)
    if not chunk:
        break
    data += chunk
counter_path = os.path.join(trace_dir, "counter")
with open(counter_path, "a+") as counter:
    fcntl.flock(counter.fileno(), fcntl.LOCK_EX)
    counter.seek(0)
    text = counter.read().strip()
    number = int(text) if text else 0
    counter.seek(0)
    counter.truncate()
    counter.write(str(number + 1))
    counter.flush()
    with open(os.path.join(trace_dir, f"{number:04d}.bin"), "wb") as record:
        record.write(data)
    fcntl.flock(counter.fileno(), fcntl.LOCK_UN)
read_fd, write_fd = os.pipe()
os.write(write_fd, data)
os.close(write_fd)
os.dup2(read_fd, 0)
os.close(read_fd)
os.execv("/tmp/verifier_reverser_real", ["reverser"] + os.sys.argv[1:])
'''
    with open(REVERSER, "w") as f:
        f.write(wrapper)
    os.chmod(REVERSER, 0o755)
    WRAPPER_HASH = hashlib.sha256(wrapper.encode()).hexdigest()


def reset_trace():
    shutil.rmtree(TRACE_DIR, ignore_errors=True)
    os.makedirs(TRACE_DIR)


def read_trace():
    records = []
    for path in sorted(glob.glob(os.path.join(TRACE_DIR, "*.bin"))):
        with open(path, "rb") as f:
            records.append(f.read())
    return records


def assert_wrapper_unchanged():
    with open(REVERSER, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    assert digest == WRAPPER_HASH, "script replaced the reverser instead of exercising it"


def strip_input_newline(value):
    return value[:-1] if value.endswith(b"\n") else value


def run_property_script(script_path, log_path):
    reset_trace()
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run([script_path], cwd=PROJECT_DIR, capture_output=True)
    assert result.returncode == 0, f"prop_test.sh failed to execute: {result.stderr.decode()}"
    assert_wrapper_unchanged()

    assert os.path.isfile(log_path), "test_results.log was not created by prop_test.sh"
    with open(log_path, "r") as f:
        content = f.read()
    assert "PROPERTY TEST PASSED" in content, "test_results.log does not contain 'PROPERTY TEST PASSED'"

    records = read_trace()
    assert len(records) == 100, f"prop_test.sh invoked reverser {len(records)} times, expected 100"
    originals = []
    for index in range(0, 100, 2):
        original = strip_input_newline(records[index])
        second_input = strip_input_newline(records[index + 1])
        assert 10 <= len(original) <= 50, "generated property-test string has an invalid length"
        assert all(chr(c) in string.ascii_letters + string.digits for c in original), \
            "generated property-test string is not alphanumeric"
        assert second_input == original[::-1], \
            "prop_test.sh did not feed the first reversal back into reverser"
        originals.append(original)
    assert len(set(originals)) >= 45, "prop_test.sh did not generate sufficiently varied random strings"
    return originals


def test_prop_test_script():
    script_path = os.path.join(PROJECT_DIR, "prop_test.sh")
    log_path = os.path.join(PROJECT_DIR, "test_results.log")

    assert os.path.isfile(script_path), "prop_test.sh script is missing"
    assert os.access(script_path, os.X_OK), "prop_test.sh is not executable"

    install_tracing_wrapper()
    first_run = run_property_script(script_path, log_path)
    second_run = run_property_script(script_path, log_path)
    assert first_run != second_run, "prop_test.sh reused a fixed set of test strings"


def test_benchmark_script():
    script_path = os.path.join(PROJECT_DIR, "benchmark.sh")
    log_path = os.path.join(PROJECT_DIR, "benchmark.log")
    payload_path = os.path.join(PROJECT_DIR, "payload.txt")

    assert os.path.isfile(script_path), "benchmark.sh script is missing"
    assert os.access(script_path, os.X_OK), "benchmark.sh is not executable"

    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(payload_path):
        os.remove(payload_path)
    reset_trace()

    result = subprocess.run([script_path], cwd=PROJECT_DIR, capture_output=True)
    assert result.returncode == 0, f"benchmark.sh failed to execute: {result.stderr.decode()}"
    assert_wrapper_unchanged()

    assert os.path.isfile(log_path), "benchmark.log was not created by benchmark.sh"
    with open(log_path, "r") as f:
        content = f.read()
    assert "BENCHMARK COMPLETED" in content, "benchmark.log does not contain 'BENCHMARK COMPLETED'"

    assert os.path.isfile(payload_path), "payload.txt was not created by benchmark.sh"
    payload_size = os.path.getsize(payload_path)
    assert payload_size == 50000, f"payload.txt size is {payload_size}, expected exactly 50000"

    with open(payload_path, "r") as f:
        payload_content = f.read()
    assert payload_content == "A" * 50000, "payload.txt does not contain exactly 50,000 'A' characters"

    records = read_trace()
    assert len(records) == 100, f"benchmark.sh invoked reverser {len(records)} times, expected 100"
    expected = b"A" * 50000
    assert all(record == expected for record in records), \
        "benchmark.sh did not pass the 50,000-byte payload to every reverser invocation"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
