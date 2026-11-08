#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import subprocess
import pytest
import hashlib
import secrets


def test_investigation_report_exists_and_correct():
    report_path = "/home/user/investigation_report.json"
    assert os.path.isfile(report_path), f"Missing investigation report at {report_path}"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Investigation report is not valid JSON")

    expected_password = "OmegaUpload7391"
    expected_endpoint = "/api/v2/internal/sys_upload_traversal_unsafe"
    expected_cn = "EvilCorp Intermediate CA G2"

    assert report.get("cracked_password") == expected_password, f"Incorrect cracked_password. Expected {expected_password}, got {report.get('cracked_password')}"
    assert report.get("vulnerable_endpoint") == expected_endpoint, f"Incorrect vulnerable_endpoint. Expected {expected_endpoint}, got {report.get('vulnerable_endpoint')}"
    assert report.get("invalid_cert_cn") == expected_cn, f"Incorrect invalid_cert_cn. Expected '{expected_cn}', got '{report.get('invalid_cert_cn')}'"


def test_fast_cracker_performance_and_accuracy():
    fast_cracker_path = "/home/user/fast_cracker"
    slow_cracker_path = "/app/slow_cracker.py"
    hash_file_path = "/app/target_hash.txt"

    assert os.path.isfile(fast_cracker_path), f"Missing fast_cracker at {fast_cracker_path}"
    assert os.access(fast_cracker_path, os.X_OK), f"fast_cracker at {fast_cracker_path} is not executable"

    with open(fast_cracker_path, "rb") as f:
        fast_bytes = f.read()
    with open(slow_cracker_path, "rb") as f:
        slow_bytes = f.read()
    assert fast_bytes != slow_bytes, "fast_cracker must not be a byte-identical copy of slow_cracker.py"

    if os.path.isfile(hash_file_path):
        with open(hash_file_path, "r") as f:
            target_hash = f.read().strip()
    else:
        target_hash = hashlib.sha256(b"OmegaUpload7391").hexdigest()

    # Preserve the benchmark against the intercepted target.
    start_slow = time.time()
    subprocess.run(["python3", slow_cracker_path, target_hash], capture_output=True)
    slow_time = time.time() - start_slow

    start_fast = time.time()
    fast_res = subprocess.run([fast_cracker_path, target_hash], capture_output=True, text=True)
    fast_time = time.time() - start_fast

    speedup = slow_time / fast_time if fast_time > 0 else float("inf")

    assert "OmegaUpload7391" in fast_res.stdout, f"Fast cracker did not output the correct password. Output: {fast_res.stdout}"
    assert speedup >= 25.0, f"Speedup {speedup:.2f}x is below the 25.0x threshold (Slow: {slow_time:.4f}s, Fast: {fast_time:.4f}s)"

    # Enforce the specified output and exit behavior for the intercepted target.
    assert fast_res.returncode == 0, f"Fast cracker exited with status {fast_res.returncode}"
    assert fast_res.stdout == "OmegaUpload7391\n", f"Fast cracker must print only the cracked password. Output: {fast_res.stdout!r}"


def test_fast_cracker_on_randomized_hashes():
    fast_cracker_path = "/home/user/fast_cracker"
    slow_cracker_path = "/app/slow_cracker.py"

    # Generate challenges only after the agent has finished. High suffixes provide
    # a stable amount of work for the reference implementation while remaining
    # valid members of the voicemail-described search space.
    candidates = [i for i in range(5500, 10000) if i != 7391]
    suffixes = secrets.SystemRandom().sample(candidates, 4)

    total_slow = 0.0
    total_fast = 0.0
    for suffix in suffixes:
        expected = f"OmegaUpload{suffix:04d}"
        challenge_hash = hashlib.sha256(expected.encode()).hexdigest()

        start_slow = time.perf_counter()
        slow_res = subprocess.run(
            ["python3", slow_cracker_path, challenge_hash],
            capture_output=True,
            text=True,
            timeout=30,
        )
        total_slow += time.perf_counter() - start_slow
        assert slow_res.returncode == 0
        assert slow_res.stdout == expected + "\n"

        start_fast = time.perf_counter()
        fast_res = subprocess.run(
            [fast_cracker_path, challenge_hash],
            capture_output=True,
            text=True,
            timeout=10,
        )
        total_fast += time.perf_counter() - start_fast

        assert fast_res.returncode == 0, f"Fast cracker exited with status {fast_res.returncode} for hash {challenge_hash}"
        assert fast_res.stderr == "", f"Fast cracker wrote unexpected stderr: {fast_res.stderr!r}"
        assert fast_res.stdout == expected + "\n", f"Fast cracker returned {fast_res.stdout!r}; expected only {expected!r}"

    randomized_speedup = total_slow / total_fast if total_fast > 0 else float("inf")
    assert randomized_speedup >= 25.0, (
        f"Randomized speedup {randomized_speedup:.2f}x is below the 25.0x threshold "
        f"(Slow: {total_slow:.4f}s, Fast: {total_fast:.4f}s)"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
