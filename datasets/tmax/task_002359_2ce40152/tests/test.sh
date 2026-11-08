#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import time

SOURCE = "/home/user/secure_reader.c"
EXE = "/home/user/secure_reader"
DATA_DIR = "/home/user/data"
VALID_TOKEN = "AUDITOR_TOKEN_99"


def run_reader(path, token=VALID_TOKEN, timeout=10):
    env = os.environ.copy()
    if token is None:
        env.pop("AUTH_TOKEN", None)
    else:
        env["AUTH_TOKEN"] = token
    return subprocess.run([EXE, path], env=env, capture_output=True, timeout=timeout)


def test_source_code_exists_and_contains_seccomp():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    assert "PR_SET_SECCOMP" in content, "PR_SET_SECCOMP not found in source code."
    result = subprocess.run(
        ["gcc", "-fsyntax-only", "-Wall", SOURCE], capture_output=True, text=True
    )
    assert result.returncode == 0, f"Source does not compile as C: {result.stderr}"


def test_executable_exists():
    assert os.path.exists(EXE), f"Executable {EXE} does not exist."
    mode = os.stat(EXE).st_mode
    assert stat.S_ISREG(mode), f"File {EXE} is not a regular file."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_reader is not a compiled ELF executable."


def test_auth_token_validation():
    probe = os.path.join(DATA_DIR, "auth_" + secrets.token_hex(8))

    result = run_reader(probe, token=None)
    assert result.returncode == 1, f"Expected exit code 1 for missing token, got {result.returncode}"

    for wrong in ("WRONG_TOKEN_" + secrets.token_hex(8), VALID_TOKEN + "x", ""):
        result = run_reader(probe, token=wrong)
        assert result.returncode == 1, f"Expected exit code 1 for wrong token, got {result.returncode}"


def test_path_enforcement():
    suffix = secrets.token_hex(8)
    invalid_paths = [
        f"/tmp/{suffix}",
        f"/home/user/datax/{suffix}",
        f"home/user/data/{suffix}",
        f"/home/user/data/../data/{suffix}",
    ]
    for path in invalid_paths:
        result = run_reader(path)
        assert result.returncode == 2, f"Expected exit code 2 for invalid path {path!r}, got {result.returncode}"

    os.makedirs(DATA_DIR, exist_ok=True)
    dotted = os.path.join(DATA_DIR, f"safe..looking_{suffix}")
    with open(dotted, "wb") as f:
        f.write(os.urandom(31))
    try:
        result = run_reader(dotted)
        assert result.returncode == 2, f"Expected exit code 2 for path containing '..', got {result.returncode}"
    finally:
        os.remove(dotted)


def test_file_preparation():
    missing = os.path.join(DATA_DIR, "missing_" + secrets.token_hex(16))
    assert not os.path.exists(missing)
    result = run_reader(missing)
    assert result.returncode == 3, f"Expected exit code 3 for missing file, got {result.returncode}"


def test_valid_execution_and_encryption_on_generated_inputs():
    os.makedirs(DATA_DIR, exist_ok=True)
    payloads = [
        b"",
        os.urandom(1),
        bytes(range(256)) + os.urandom(37),
        os.urandom(4097),
        os.urandom(131071),
    ]

    for plaintext in payloads:
        path = os.path.join(DATA_DIR, "generated_" + secrets.token_hex(12) + ".bin")
        with open(path, "wb") as f:
            f.write(plaintext)
        try:
            result = run_reader(path)
            assert result.returncode == 0, f"Expected exit code 0 for valid execution, got {result.returncode}"
            expected = bytes(value ^ 0x5A for value in plaintext)
            assert result.stdout == expected, "Output data does not match XOR of generated file contents."
        finally:
            os.remove(path)


def test_strict_seccomp_is_actually_active_during_reading():
    os.makedirs(DATA_DIR, exist_ok=True)
    path = os.path.join(DATA_DIR, "seccomp_" + secrets.token_hex(12) + ".bin")
    plaintext = os.urandom(3 * 1024 * 1024 + 113)
    with open(path, "wb") as f:
        f.write(plaintext)

    env = os.environ.copy()
    env["AUTH_TOKEN"] = VALID_TOKEN
    proc = subprocess.Popen([EXE, path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    observed_modes = []
    try:
        deadline = time.monotonic() + 5
        strict_active = False
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            try:
                with open(f"/proc/{proc.pid}/status", "r", encoding="ascii") as status_file:
                    for line in status_file:
                        if line.startswith("Seccomp:"):
                            mode = int(line.split(":", 1)[1].strip())
                            observed_modes.append(mode)
                            if mode == 1:
                                strict_active = True
                            break
            except FileNotFoundError:
                break
            if strict_active:
                break
            time.sleep(0.01)

        assert strict_active, (
            "Process never entered SECCOMP_MODE_STRICT after opening a valid file; "
            f"observed Seccomp modes: {observed_modes}, return code: {proc.poll()}"
        )

        stdout, stderr = proc.communicate(timeout=20)
        assert proc.returncode == 0, f"Expected clean exit 0 under strict seccomp, got {proc.returncode}; stderr={stderr!r}"
        expected = bytes(value ^ 0x5A for value in plaintext)
        assert stdout == expected, "Large generated input was not completely XOR-encrypted under seccomp."
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate()
        os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
