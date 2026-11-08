#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/sanitizer.c"
EXECUTABLE = "/home/user/sanitizer"


def test_compile_sanitizer():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} not found. The student must create the sanitizer source code."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} must be a regular file."

    compile_cmd = ["gcc", "-O2", SOURCE, "-o", EXECUTABLE]
    result = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)

    assert result.returncode == 0, f"Compilation failed. Standard error output:\n{result.stderr}"
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} not found after compilation."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} must be a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."


def test_adversarial_corpus():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(EXECUTABLE), f"Sanitizer executable {EXECUTABLE} not found. Ensure compilation succeeds."
    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} not found."
    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} not found."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        result = subprocess.run([EXECUTABLE, file_path], capture_output=True, text=True, timeout=3)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(f)

    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        result = subprocess.run([EXECUTABLE, file_path], capture_output=True, text=True, timeout=3)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)


def vulnerability_oracle(request):
    header_block = request.split(b"\r\n\r\n", 1)[0]
    lines = header_block.split(b"\r\n")[1:]
    for line in lines:
        if b":" not in line:
            continue
        name, value = line.split(b":", 1)
        if name.strip().lower() != b"cookie":
            continue
        start = value.find(b"session_id=")
        if start < 0:
            continue
        session = value[start + len(b"session_id="):]
        length = 0
        for byte in session:
            if byte in (ord(';'), ord('\r'), ord('\n')):
                break
            length += 1
        # buffer[64] is already out of bounds, including when it receives
        # the terminating NUL after exactly 64 data bytes.
        if length >= 64:
            return True
    return False


def make_request(headers, body=b""):
    return b"GET / HTTP/1.1\r\nHost: example.test\r\n" + b"".join(
        name + b": " + value + b"\r\n" for name, value in headers
    ) + b"\r\n" + body


def test_generated_requests_exercise_sanitizer():
    token = secrets.token_hex(24).encode("ascii")
    long_value = (token * 4)[:96]
    exact_value = (token * 3)[:64]
    short_value = (token * 2)[:63]

    requests = [
        make_request([(b"Cookie", b"session_id=" + exact_value)]),
        make_request([(b"Cookie", b"theme=dark; session_id=" + long_value + b"; mode=1")]),
        make_request([(b"Cookie", b"session_id=" + long_value)]),
        make_request([(b"Cookie", b"session_id=" + short_value)]),
        make_request([(b"Cookie", b"session_id=" + short_value + b"; other=" + long_value)]),
        make_request([(b"Cookie", b"unrelated=" + long_value)]),
        make_request([(b"X-Debug", b"session_id=" + long_value)]),
        make_request([(b"Content-Length", str(len(long_value) + 11).encode("ascii"))], b"session_id=" + long_value),
        make_request([(b"Cookie", b"session_id=")]),
    ]

    expected = [vulnerability_oracle(request) for request in requests]
    assert any(expected), "Generated suite must contain malicious requests."
    assert not all(expected), "Generated suite must contain benign requests."

    failures = []
    with tempfile.TemporaryDirectory(prefix="sanitizer-tests-") as directory:
        order = list(range(len(requests)))
        secrets.SystemRandom().shuffle(order)
        for index in order:
            path = os.path.join(directory, secrets.token_hex(12))
            with open(path, "wb") as request_file:
                request_file.write(requests[index])

            result = subprocess.run(
                [EXECUTABLE, path], capture_output=True, text=True, timeout=3
            )
            want_evil = expected[index]
            wanted_status = 1 if want_evil else 0
            wanted_output = "EVIL" if want_evil else "CLEAN"
            if result.returncode != wanted_status or result.stdout.strip() != wanted_output:
                failures.append(
                    f"case {index}: expected {wanted_output}/status {wanted_status}, "
                    f"got {result.stdout.strip()!r}/status {result.returncode}"
                )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
