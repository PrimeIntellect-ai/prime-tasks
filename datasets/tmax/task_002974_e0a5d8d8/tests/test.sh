#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import hashlib
import subprocess


def test_secure_audit_log_exists_and_permissions():
    log_file = "/home/user/secure_audit.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist."

    file_stat = os.stat(log_file)
    mode = stat.S_IMODE(file_stat.st_mode)
    assert mode == 0o400, f"Permissions of {log_file} are {oct(mode)}, expected 0o400."


def test_secure_audit_log_contents():
    raw_file = "/home/user/raw_audits.txt"
    log_file = "/home/user/secure_audit.log"

    assert os.path.isfile(raw_file), f"File {raw_file} is missing."
    assert os.path.isfile(log_file), f"File {log_file} is missing."

    with open(raw_file, "r") as f:
        raw_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = []
    for line in raw_lines:
        decoded_bytes = base64.b64decode(line)
        sha256_hex = hashlib.sha256(decoded_bytes).hexdigest()
        decoded_text = decoded_bytes.decode('utf-8', errors='replace')
        expected_lines.append(f"{sha256_hex}:{decoded_text}")

    with open(log_file, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_file}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {log_file} does not match expected output.\nExpected: {expected}\nActual: {actual}"


def test_c_program_compiles_and_generates_log_from_fresh_inputs():
    source = "/home/user/audit_processor.c"
    raw_file = "/home/user/raw_audits.txt"
    log_file = "/home/user/secure_audit.log"
    binary = "/tmp/audit_processor_verifier"

    assert os.path.isfile(source), f"C source file {source} does not exist."
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} must be a regular file."

    compile_result = subprocess.run(
        ["gcc", source, "-o", binary, "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "audit_processor.c failed to compile:\n" + compile_result.stderr
    )

    with open(raw_file, "rb") as f:
        original_raw = f.read()
    with open(log_file, "rb") as f:
        original_log = f.read()
    original_log_stat = os.stat(log_file)

    nonce = os.urandom(24).hex()
    payloads = [
        f"verification event {nonce}".encode("ascii"),
        f"user-{nonce[:17]} accessed /tmp/object-{nonce[17:]}".encode("ascii"),
        f"failed authentication token {nonce[::-1]}".encode("ascii"),
    ]
    encoded_input = b"\n".join(base64.b64encode(p) for p in payloads) + b"\n"
    expected_lines = [
        f"{hashlib.sha256(p).hexdigest()}:{p.decode('ascii')}" for p in payloads
    ]

    try:
        with open(raw_file, "wb") as f:
            f.write(encoded_input)
        os.chown(raw_file, 1000, 1000)
        os.chmod(raw_file, 0o666)

        os.unlink(log_file)
        run_result = subprocess.run(
            ["runuser", "-u", "user", "--", binary],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "Compiled audit processor exited unsuccessfully:\n" + run_result.stderr
        )
        assert os.path.isfile(log_file), "Compiled C program did not generate secure_audit.log."

        with open(log_file, "r") as f:
            actual_lines = [line.strip() for line in f.readlines() if line.strip()]

        assert len(actual_lines) == len(expected_lines), (
            f"Fresh execution produced {len(actual_lines)} lines; expected {len(expected_lines)}."
        )
        for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
            assert actual == expected, (
                f"Fresh execution output line {i+1} is incorrect.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
    finally:
        with open(raw_file, "wb") as f:
            f.write(original_raw)
        if os.path.lexists(log_file):
            os.unlink(log_file)
        with open(log_file, "wb") as f:
            f.write(original_log)
        os.chown(log_file, original_log_stat.st_uid, original_log_stat.st_gid)
        os.chmod(log_file, stat.S_IMODE(original_log_stat.st_mode))
        if os.path.exists(binary):
            os.unlink(binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
