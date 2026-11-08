#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_encoder_executable_exists():
    encoder_path = "/home/user/ci-tools/c-encoder/encoder"
    assert os.path.exists(encoder_path), f"File {encoder_path} does not exist. Did you fix the Makefile and run make?"
    assert os.access(encoder_path, os.X_OK), f"File {encoder_path} is not executable."

def test_test_results_log():
    log_path = "/home/user/ci-tools/test_results.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist. Did you run the Go tests and save the output?"
    with open(log_path, "r") as f:
        content = f.read()
    assert "PASS" in content, f"Expected 'PASS' in {log_path}, but it was not found. The tests might have failed."

def test_go_verifier_implementation():
    test_path = "/home/user/ci-tools/go-verifier/verifier_test.go"
    assert os.path.exists(test_path), f"File {test_path} is missing."
    with open(test_path, "r") as f:
        content = f.read()
    assert "encoding/hex" in content, "The Go test does not import 'encoding/hex'. You must decode the hex output."
    assert "chan " in content or "chan\t" in content or "make(chan" in content, "The Go test does not seem to use channels ('chan')."
    assert "go func" in content or "go " in content, "The Go test does not seem to spawn goroutines ('go func')."
TEST_EOF

cat << 'VERIFY_EOF' > /tmp/verify_behavior.py
import os
import shutil
import stat
import subprocess
import sys
import time

C_DIR = "/home/user/ci-tools/c-encoder"
GO_DIR = "/home/user/ci-tools/go-verifier"
ENCODER = os.path.join(C_DIR, "encoder")
BACKUP = "/tmp/encoder.verifier-backup"
CALL_LOG = "/tmp/encoder_calls.log"


def run(cmd, cwd=None, timeout=60):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=timeout)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write_executable(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                   stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)


# Prove that the repaired Makefile itself can produce the executable.
if os.path.exists(ENCODER):
    os.remove(ENCODER)
build = run(["make"], cwd=C_DIR)
require(build.returncode == 0, "make failed:\n" + build.stdout.decode(errors="replace"))
require(os.path.isfile(ENCODER) and os.access(ENCODER, os.X_OK),
        "make did not produce an executable encoder")

# Exercise the built C utility and independently derive each expected encoding.
for value in ["", "abc", "build-token-42", "colon:value", "MixedCASE012345"]:
    result = run([ENCODER, value], timeout=10)
    expected_serialized = str(len(value.encode("utf-8"))).encode() + b":" + value.encode("utf-8")
    expected_output = expected_serialized.hex().encode() + b"\n"
    require(result.returncode == 0, f"encoder failed for {value!r}")
    require(result.stdout == expected_output,
            f"encoder returned {result.stdout!r}, expected {expected_output!r}")
    decoded = bytes.fromhex(result.stdout.strip().decode("ascii"))
    require(decoded == expected_serialized, "encoder output did not decode to the serialization")

# Execute the submitted Go test against the real compiled encoder.
real_test = run(["go", "test", "-count=1", "-run", "^TestEncoderProperty$"], cwd=GO_DIR, timeout=60)
require(real_test.returncode == 0,
        "submitted Go property test failed:\n" + real_test.stdout.decode(errors="replace"))

shutil.copy2(ENCODER, BACKUP)
try:
    # Replace the encoder temporarily with an instrumented, behaviorally correct
    # implementation. Its delay makes actual overlap observable.
    if os.path.exists(CALL_LOG):
        os.remove(CALL_LOG)
    good_wrapper = '''#!/usr/bin/python3
import os, sys, time
log = "/tmp/encoder_calls.log"
def event(kind):
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (f"{kind} {os.getpid()} {time.time_ns()}\\n").encode())
    finally:
        os.close(fd)
event("S")
time.sleep(0.15)
s = sys.argv[1]
payload = str(len(s.encode("utf-8"))).encode() + b":" + s.encode("utf-8")
sys.stdout.write(payload.hex() + "\\n")
sys.stdout.flush()
event("E")
'''
    write_executable(ENCODER, good_wrapper)
    concurrent_test = run(["go", "test", "-count=1", "-run", "^TestEncoderProperty$"], cwd=GO_DIR, timeout=60)
    require(concurrent_test.returncode == 0,
            "Go test failed against correct encoded output:\n" + concurrent_test.stdout.decode(errors="replace"))
    require(os.path.exists(CALL_LOG), "Go test did not invoke the encoder")

    events = []
    with open(CALL_LOG, encoding="utf-8") as f:
        for line in f:
            kind, pid, timestamp = line.split()
            events.append((int(timestamp), kind, int(pid)))
    starts = [e for e in events if e[1] == "S"]
    ends = [e for e in events if e[1] == "E"]
    require(len(starts) == 50 and len(ends) == 50,
            f"expected exactly 50 completed encoder invocations, saw {len(starts)} starts and {len(ends)} completions")
    active = 0
    maximum = 0
    for _, kind, _ in sorted(events):
        if kind == "S":
            active += 1
            maximum = max(maximum, active)
        else:
            active -= 1
    require(maximum >= 2, "the 50 encoder invocations were not concurrent")

    # A syntactically valid hex response with the wrong decoded serialization
    # must make the property test fail, proving it validates decoded content.
    bad_wrapper = '''#!/usr/bin/python3
print(b"999:not-the-input".hex())
'''
    write_executable(ENCODER, bad_wrapper)
    bad_test = run(["go", "test", "-count=1", "-run", "^TestEncoderProperty$"], cwd=GO_DIR, timeout=60)
    require(bad_test.returncode != 0,
            "Go property test passed incorrect decoded serialization")
finally:
    if os.path.exists(BACKUP):
        shutil.copy2(BACKUP, ENCODER)
        os.remove(BACKUP)
VERIFY_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/verify_behavior.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
