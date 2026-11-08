#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

PROJECT_DIR = "/home/user/project"
PATCH_FILE = os.path.join(PROJECT_DIR, "parser_fix.patch")
PARSER_C = os.path.join(PROJECT_DIR, "c_ext", "parser.c")
RUST_BINARY = os.path.join(PROJECT_DIR, "target", "debug", "rust_processor")
GATEWAY_PY = os.path.join(PROJECT_DIR, "gateway.py")


def random_ascii(length):
    alphabet = string.ascii_letters + string.digits + "_-"
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(length))


def test_patch_file_exists_and_is_applicable():
    assert os.path.isfile(PATCH_FILE), f"Patch file {PATCH_FILE} is missing."
    patch_text = open(PATCH_FILE, "r", encoding="utf-8").read()
    assert patch_text.strip(), "parser_fix.patch is empty."
    assert "--- " in patch_text and "+++ " in patch_text, "Patch is not a unified diff."
    assert "parser.c" in patch_text, "Patch does not modify c_ext/parser.c."
    assert "-    strcpy(output, input);" in patch_text, "Patch does not remove the original unsafe strcpy."

    applicable = False
    errors = []
    for strip_level in (0, 1):
        result = subprocess.run(
            ["patch", "--batch", "--dry-run", "-R", f"-p{strip_level}"],
            cwd=PROJECT_DIR,
            input=patch_text,
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            applicable = True
            break
        errors.append(result.stdout + result.stderr)
    assert applicable, "parser_fix.patch cannot be reverse-applied to the submitted tree:\n" + "\n".join(errors)


def test_c_parser_safely_truncates_and_preserves_canary():
    with tempfile.TemporaryDirectory() as td:
        library = os.path.join(td, "libparser.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-Wall", "-Wextra", "-o", library, PARSER_C],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"c_ext/parser.c did not compile:\n{result.stderr}"

        parser = ctypes.CDLL(library)
        parser.process_string.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
        parser.process_string.restype = None

        samples = [b"", b"x", b"A" * 14, b"B" * 15, b"C" * 16, b"D" * 80]
        samples.extend(random_ascii(random.randint(17, 120)).encode("ascii") for _ in range(8))
        for value in samples:
            storage = (ctypes.c_ubyte * 32)(*([0x5A] * 32))
            parser.process_string(value, ctypes.cast(storage, ctypes.c_void_p))
            raw = bytes(storage)
            expected = value[:15]
            assert raw[:len(expected)] == expected, "C parser did not preserve the expected prefix."
            assert raw[len(expected)] == 0, "C parser did not null-terminate within the 16-byte buffer."
            assert raw[16:] == b"Z" * 16, "C parser wrote beyond the 16-byte output buffer."


def test_cargo_build_succeeds():
    clean = subprocess.run(["cargo", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stderr}"
    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stderr}"
    assert os.path.isfile(RUST_BINARY), f"Rust binary {RUST_BINARY} was not created."
    assert os.access(RUST_BINARY, os.X_OK), f"Rust binary {RUST_BINARY} is not executable."


def test_rust_binary_truncates_without_segfault():
    inputs = ["A" * 30, random_ascii(15), random_ascii(16)]
    inputs.extend(random_ascii(random.randint(20, 100)) for _ in range(8))
    for value in inputs:
        result = subprocess.run([RUST_BINARY, value], capture_output=True, text=True)
        assert result.returncode == 0, f"Rust binary crashed for input length {len(value)}."
        assert result.stdout == value[:15] + "\n", (
            f"Expected exact 15-character truncation {value[:15]!r}, got {result.stdout!r}."
        )


def test_python_gateway_validation_rate_limiting_and_binary_invocation():
    invocation_log = os.path.join(PROJECT_DIR, ".verifier_binary_calls")
    backup_binary = RUST_BINARY + ".verifier_backup"
    if os.path.exists(invocation_log):
        os.unlink(invocation_log)
    shutil.copy2(RUST_BINARY, backup_binary)
    wrapper = f'''#!/usr/bin/python3
import json
import sys
with open({invocation_log!r}, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
print(sys.argv[1][:15])
'''
    with open(RUST_BINARY, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(RUST_BINARY, 0o755)

    server_process = subprocess.Popen(
        ["python3", GATEWAY_PY],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(1)

    try:
        assert server_process.poll() is None, "Python gateway failed to start or crashed immediately."
        url = "http://127.0.0.1:8080"

        def send_raw(body):
            req = urllib.request.Request(
                url,
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=3) as response:
                    return response.status, response.read().decode("utf-8")
            except urllib.error.HTTPError as exc:
                return exc.code, exc.read().decode("utf-8", errors="replace")

        def send_json(payload):
            return send_raw(json.dumps(payload).encode("utf-8"))

        status, _ = send_raw(b"not json")
        assert status == 400, f"Expected 400 for malformed JSON, got {status}"

        status, _ = send_json({"data": "test"})
        assert status == 400, f"Expected 400 for missing user_id, got {status}"
        status, _ = send_json({"user_id": "user1"})
        assert status == 400, f"Expected 400 for missing data, got {status}"

        invalid_payloads = [
            [],
            "string instead of object",
            {"data": 123, "user_id": "u-" + uuid.uuid4().hex},
            {"data": None, "user_id": "u-" + uuid.uuid4().hex},
            {"data": ["x"], "user_id": "u-" + uuid.uuid4().hex},
            {"data": random_ascii(25), "user_id": 123},
            {"data": random_ascii(25), "user_id": None},
            {"data": random_ascii(25), "user_id": ["u"]},
        ]
        for payload in invalid_payloads:
            status, _ = send_json(payload)
            assert status == 400, f"Expected 400 for invalid payload {payload!r}, got {status}"

        user_id = "rate-" + uuid.uuid4().hex
        data = random_ascii(random.randint(25, 70))
        accepted_inputs = []
        for request_number in range(1, 4):
            status, body = send_json({"user_id": user_id, "data": data})
            assert status == 200, f"Expected 200 for request {request_number}, got {status}"
            assert body == data[:15] + "\n", f"Gateway returned incorrect processor stdout: {body!r}"
            accepted_inputs.append(data)

        status, _ = send_json({"user_id": user_id, "data": random_ascii(40)})
        assert status == 429, f"Expected 429 for request 4, got {status}"

        other_user = "other-" + uuid.uuid4().hex
        other_data = random_ascii(random.randint(25, 70))
        status, body = send_json({"user_id": other_user, "data": other_data})
        assert status == 200, f"Expected 200 for a different user, got {status}"
        assert body == other_data[:15] + "\n", f"Gateway returned incorrect stdout for another user: {body!r}"
        accepted_inputs.append(other_data)

        assert os.path.isfile(invocation_log), "Gateway did not execute ./target/debug/rust_processor."
        with open(invocation_log, "r", encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls == [[value] for value in accepted_inputs], (
            "Gateway must invoke the Rust processor exactly once for each accepted request, "
            "with the submitted data argument, and not invoke it for rejected requests."
        )
    finally:
        server_process.terminate()
        try:
            server_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            server_process.kill()
            server_process.wait(timeout=2)
        shutil.move(backup_binary, RUST_BINARY)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
