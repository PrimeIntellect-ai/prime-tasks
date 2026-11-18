#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/project"
APP_AMD64 = f"{PROJECT}/bin/app-amd64"
LIB_AMD64 = f"{PROJECT}/lib/amd64/libfasthash.so"
APP_ARM64 = f"{PROJECT}/bin/app-arm64"
LIB_ARM64 = f"{PROJECT}/lib/arm64/libfasthash.so"
C_SOURCE = f"{PROJECT}/c/fasthash.c"


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=20, **kwargs)
    assert result.returncode == 0, (
        f"Command {command!r} failed with code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def assert_needed_fasthash(binary):
    dynamic = run_checked(["readelf", "-d", binary]).stdout
    assert re.search(r"\(NEEDED\).*\[libfasthash\.so\]", dynamic), (
        f"{binary} is not dynamically linked against libfasthash.so."
    )


def assert_exports_fast_hash(library):
    symbols = run_checked(["readelf", "-Ws", library]).stdout
    assert re.search(r"\bGLOBAL\b.*\bfast_hash\s*$", symbols, re.MULTILINE), (
        f"{library} does not export fast_hash."
    )


def exercise_library(library, inputs):
    helper = r'''
import ctypes
import json
import sys

library = ctypes.CDLL(sys.argv[1])
library.fast_hash.argtypes = [ctypes.c_char_p]
library.fast_hash.restype = ctypes.c_void_p
libc = ctypes.CDLL(None)
libc.free.argtypes = [ctypes.c_void_p]
libc.free.restype = None

for value in json.load(sys.stdin):
    raw = value.encode("ascii")
    result = library.fast_hash(raw)
    if not result:
        raise SystemExit("fast_hash returned NULL")
    try:
        actual = ctypes.string_at(result)
    finally:
        libc.free(result)
    expected = raw[::-1] + b"HASH"
    if actual != expected:
        raise SystemExit("wrong result: %r != %r" % (actual, expected))
'''
    result = subprocess.run(
        ["python3", "-c", helper, library],
        input=json.dumps(inputs),
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"fast_hash in {library} failed behavioral tests.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_run_log_output():
    log_path = "/home/user/project/run.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "ataDterceSrepuSHASH", f"Expected 'ataDterceSrepuSHASH' in run.log, but got '{content}'."


def test_fasthash_c_fixed():
    c_file = "/home/user/project/c/fasthash.c"
    assert os.path.isfile(c_file), f"File {c_file} is missing."

    with open(c_file, "r") as f:
        content = f.read()

    # Preserve the original allocation assertion.
    match = re.search(r'malloc\s*\([^)]*\+\s*5\s*\)', content)
    assert match is not None, "fasthash.c does not appear to allocate 'len + 5' (or similar) in malloc."

    # Compile and execute the submitted source so a regex-only edit cannot pass.
    with tempfile.TemporaryDirectory() as tmp:
        compiled = os.path.join(tmp, "libsubmitted-fasthash.so")
        run_checked([
            "gcc", "-shared", "-fPIC", "-O2",
            "-I", f"{PROJECT}/c", C_SOURCE, "-o", compiled,
        ])
        random_value = secrets.token_hex(128)
        exercise_library(compiled, ["", "a", "SuperSecretData", random_value, "Z" * 65536])


def test_amd64_binaries():
    app_amd64 = "/home/user/project/bin/app-amd64"
    lib_amd64 = "/home/user/project/lib/amd64/libfasthash.so"

    assert os.path.isfile(app_amd64), f"File {app_amd64} is missing."
    assert os.path.isfile(lib_amd64), f"File {lib_amd64} is missing."

    out = subprocess.run(["file", app_amd64], capture_output=True, text=True).stdout
    assert "ELF 64-bit LSB executable" in out and "x86-64" in out, f"{app_amd64} is not an x86-64 ELF executable."

    out = subprocess.run(["file", lib_amd64], capture_output=True, text=True).stdout
    assert "ELF 64-bit LSB shared object" in out and "x86-64" in out, f"{lib_amd64} is not an x86-64 ELF shared object."

    assert_needed_fasthash(app_amd64)
    assert_exports_fast_hash(lib_amd64)


def test_arm64_binaries():
    app_arm64 = "/home/user/project/bin/app-arm64"
    lib_arm64 = "/home/user/project/lib/arm64/libfasthash.so"

    assert os.path.isfile(app_arm64), f"File {app_arm64} is missing."
    assert os.path.isfile(lib_arm64), f"File {lib_arm64} is missing."

    out = subprocess.run(["file", app_arm64], capture_output=True, text=True).stdout
    assert "ELF 64-bit LSB executable" in out and "aarch64" in out, f"{app_arm64} is not an ARM aarch64 ELF executable."

    out = subprocess.run(["file", lib_arm64], capture_output=True, text=True).stdout
    assert "ELF 64-bit LSB shared object" in out and "aarch64" in out, f"{lib_arm64} is not an ARM aarch64 ELF shared object."

    assert_needed_fasthash(app_arm64)
    assert_exports_fast_hash(lib_arm64)


def test_amd64_library_behavior():
    random_value = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(4096))
    exercise_library(LIB_AMD64, ["", "x", "abcdef", "SuperSecretData", random_value, "Q" * 65536])


def test_amd64_application_behavior_and_runtime_linking():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.dirname(LIB_AMD64)

    values = [
        "SuperSecretData",
        secrets.token_hex(32),
        ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8192)),
    ]
    for value in values:
        result = run_checked([APP_AMD64, value], env=env)
        assert result.stdout.strip() == value[::-1] + "HASH", (
            f"app-amd64 returned the wrong result for an exercised input: {result.stdout!r}"
        )

    # Replace the runtime library with a verifier-generated shim carrying an
    # unpredictable response. This proves the Go executable actually calls
    # fast_hash through libfasthash.so instead of printing a hardcoded result.
    with tempfile.TemporaryDirectory() as tmp:
        token = "LINKED_" + secrets.token_hex(24)
        shim_source = os.path.join(tmp, "shim.c")
        shim_library = os.path.join(tmp, "libfasthash.so")
        with open(shim_source, "w") as f:
            f.write(
                '#include <stdlib.h>\n'
                '#include <string.h>\n'
                'char *fast_hash(const char *input) {\n'
                f'  const char value[] = "{token}";\n'
                '  char *out = malloc(sizeof(value));\n'
                '  if (out) memcpy(out, value, sizeof(value));\n'
                '  return out;\n'
                '}\n'
            )
        run_checked(["gcc", "-shared", "-fPIC", shim_source, "-o", shim_library])
        shim_env = os.environ.copy()
        shim_env["LD_LIBRARY_PATH"] = tmp
        result = run_checked([APP_AMD64, secrets.token_hex(12)], env=shim_env)
        assert result.stdout.strip() == token, (
            "app-amd64 did not use the runtime libfasthash.so fast_hash symbol."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
