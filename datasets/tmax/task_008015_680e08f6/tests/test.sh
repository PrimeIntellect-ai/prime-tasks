#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

APP = "/home/user/app"
LIB = os.path.join(APP, "libsec.so")
BUILD = os.path.join(APP, "build.sh")
REST = os.path.join(APP, "rest_api.sh")
TEST_LIB = os.path.join(APP, "test_lib.py")
C_SOURCE = os.path.join(APP, "crypto_check.c")


def clean_build_outputs():
    for name in ("libsec.so", "crypto_check.o", "verify_hash.o"):
        path = os.path.join(APP, name)
        if os.path.lexists(path):
            os.remove(path)


def run_build():
    return subprocess.run(
        [BUILD], cwd=APP, capture_output=True, text=True, timeout=30
    )


def load_unique_copy(path):
    fd, copy_path = tempfile.mkstemp(prefix="libsec-check-", suffix=".so")
    os.close(fd)
    shutil.copy2(path, copy_path)
    return ctypes.CDLL(copy_path), copy_path


def test_build_script_rebuilds_pic_shared_library():
    assert os.path.isfile(BUILD), f"{BUILD} does not exist."
    assert os.stat(BUILD).st_mode & stat.S_IXUSR, f"{BUILD} is not executable."
    assert os.path.isfile(C_SOURCE), f"{C_SOURCE} does not exist."

    with open(C_SOURCE, "rb") as f:
        original_source = f.read()

    # Accessing a global from a shared object requires position-independent C
    # code. This makes a clean build fail if build.sh still omits the required
    # PIC compilation option, rather than merely inspecting the script text.
    pic_probe = b"\nint verifier_pic_global = 739391;\nint verifier_pic_probe(void) { return verifier_pic_global; }\n"
    probe_result = None
    probe_value = None
    probe_error = None
    restore_result = None

    try:
        with open(C_SOURCE, "wb") as f:
            f.write(original_source + pic_probe)
        clean_build_outputs()
        probe_result = run_build()
        if probe_result.returncode == 0 and os.path.isfile(LIB):
            try:
                lib, copied = load_unique_copy(LIB)
                try:
                    func = lib.verifier_pic_probe
                    func.argtypes = []
                    func.restype = ctypes.c_int
                    probe_value = func()
                finally:
                    os.remove(copied)
            except Exception as exc:
                probe_error = repr(exc)
    finally:
        with open(C_SOURCE, "wb") as f:
            f.write(original_source)
        clean_build_outputs()
        restore_result = run_build()

    assert probe_result is not None
    assert probe_result.returncode == 0, (
        "build.sh failed a clean shared-library build requiring PIC:\n"
        + probe_result.stdout + probe_result.stderr
    )
    assert probe_error is None, f"PIC probe was not exported correctly: {probe_error}"
    assert probe_value == 739391, "The rebuilt library did not contain working compiled C probe code."
    assert restore_result is not None and restore_result.returncode == 0, (
        "build.sh failed while rebuilding the original sources:\n"
        + (restore_result.stdout + restore_result.stderr if restore_result else "")
    )

    assert os.path.isfile(LIB), f"{LIB} does not exist. Did you run the fixed build.sh?"
    file_result = subprocess.run(["file", LIB], capture_output=True, text=True)
    assert "shared object" in file_result.stdout, f"{LIB} is not a valid shared object."

    for obj in ("crypto_check.o", "verify_hash.o"):
        obj_path = os.path.join(APP, obj)
        assert os.path.isfile(obj_path), f"build.sh did not produce {obj}."
        obj_file = subprocess.run(["file", obj_path], capture_output=True, text=True)
        assert "relocatable" in obj_file.stdout, f"{obj} is not a compiled relocatable object."

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", LIB], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    exported = {line.split()[-1] for line in symbols if line.split()}
    assert "validate_token" in exported, "libsec.so does not export validate_token."
    assert "verify_asm" in exported, "libsec.so does not contain/export the assembly function verify_asm."


def test_libsec_validation_behavior():
    assert os.path.isfile(LIB)
    lib, copied = load_unique_copy(LIB)
    try:
        validate = lib.validate_token
        validate.argtypes = [ctypes.c_char_p]
        validate.restype = ctypes.c_int

        suffixes = [secrets.token_hex(10) for _ in range(8)]
        cases = [("A" + suffixes[0], 1), ("A " + suffixes[1], 1)]
        cases.extend((prefix + suffix, 0) for prefix, suffix in zip("BCxyz0", suffixes[2:]))
        for token, expected in cases:
            assert validate(token.encode("utf-8")) == expected, (
                f"validate_token returned the wrong result for {token!r}."
            )
        assert validate(None) == 0, "validate_token must reject a null token pointer."
    finally:
        os.remove(copied)


def assert_api_output(token, valid):
    result = subprocess.run([REST, token], capture_output=True, text=True, timeout=15)
    expected = json.dumps(
        {"endpoint": "/api/validate", "token_valid": valid}, separators=(", ", ": ")
    )
    assert result.stdout.strip() == expected, (
        f"Expected output {expected!r} for token {token!r}, got {result.stdout.strip()!r}"
    )


def test_rest_api_exists_and_uses_real_library():
    assert os.path.isfile(REST), f"{REST} does not exist."
    assert os.stat(REST).st_mode & stat.S_IXUSR, f"{REST} is not executable."

    # Retain the original fixed checks and add verifier-generated inputs.
    assert_api_output("A123", True)
    assert_api_output("B123", False)
    nonce = secrets.token_hex(16)
    assert_api_output("A value;$-" + nonce, True)
    assert_api_output("Z value;$-" + nonce, False)


def test_rest_api_calls_test_lib_and_obeys_its_exit_status():
    assert os.path.isfile(TEST_LIB), f"{TEST_LIB} does not exist."
    with open(TEST_LIB, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(TEST_LIB).st_mode)

    log_fd, log_path = tempfile.mkstemp(prefix="test-lib-calls-", suffix=".jsonl")
    os.close(log_fd)
    os.chmod(log_path, 0o666)

    nonce = secrets.token_hex(18)
    # These outcomes intentionally contradict the library's first-byte rule,
    # so implementing that rule directly cannot pass this test.
    cases = [
        ("A-probe-" + nonce, False),
        ("B-probe-" + nonce, True),
        ("Q value ;$ " + nonce, True),
        ("R value ;$ " + nonce, False),
    ]
    valid_tokens = [token for token, valid in cases if valid]
    probe = f'''#!/usr/bin/env python3
import json
import sys
LOG = {log_path!r}
VALID = {valid_tokens!r}
with open(LOG, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) != 2:
    sys.exit(97)
sys.exit(0 if sys.argv[1] in VALID else 1)
'''

    try:
        with open(TEST_LIB, "w", encoding="utf-8") as f:
            f.write(probe)
        os.chmod(TEST_LIB, 0o755)

        for index, (token, valid) in enumerate(cases, 1):
            assert_api_output(token, valid)
            with open(log_path, encoding="utf-8") as f:
                calls = [json.loads(line) for line in f if line.strip()]
            assert len(calls) == index, "rest_api.sh must call test_lib.py exactly once per request."
            assert calls[-1] == [token], "rest_api.sh did not pass the token as exactly one argument."

        with open(log_path, encoding="utf-8") as f:
            call_count = sum(1 for line in f if line.strip())
        subprocess.run([REST], capture_output=True, text=True, timeout=15)
        subprocess.run([REST, "one", "two"], capture_output=True, text=True, timeout=15)
        with open(log_path, encoding="utf-8") as f:
            final_count = sum(1 for line in f if line.strip())
        assert final_count == call_count, "rest_api.sh must reject requests not having exactly one argument."
    finally:
        with open(TEST_LIB, "wb") as f:
            f.write(original)
        os.chmod(TEST_LIB, original_mode)
        os.remove(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
