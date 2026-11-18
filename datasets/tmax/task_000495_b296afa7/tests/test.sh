#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import os
import random
import shutil
import string
import subprocess
import sys

import pytest

PROJECT = "/app/waf-emu"
AGENT_SCRIPT = "/home/user/evaluate.py"
ORACLE_PATH = "/opt/oracle/evaluate_reference"
LIB_PATH = "/app/waf-emu/py-emu/libwaf_core.so"
RELEASE_LIB = "/app/waf-emu/rust-core/target/release/libwaf_core.so"


def generate_hex_string(length):
    return ''.join(random.choices('0123456789abcdef', k=length))


def generate_payload(length):
    printable = string.ascii_letters + string.digits + string.punctuation + ' '
    return ''.join(random.choices(printable, k=length))


@pytest.fixture(scope="session", autouse=True)
def build_and_validate_artifacts():
    subprocess.run(
        ["cargo", "clean"],
        cwd=os.path.join(PROJECT, "rust-core"),
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)

    result = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, \
        f"make failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(RELEASE_LIB), "make did not build the release Rust shared library"
    assert os.path.isfile(LIB_PATH), "make did not copy libwaf_core.so into py-emu"
    assert open(RELEASE_LIB, "rb").read() == open(LIB_PATH, "rb").read(), \
        "py-emu/libwaf_core.so is not the release library produced by Cargo"
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libwaf_core.so is not an ELF shared library"


def test_evaluate_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), "/home/user/evaluate.py is missing."
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"
    assert open(AGENT_SCRIPT, "rb").read() != open(ORACLE_PATH, "rb").read(), \
        "evaluate.py must not be a byte-identical copy of the reference implementation"


def test_python_abi_signatures_and_calls():
    sys.path.insert(0, os.path.join(PROJECT, "py-emu"))
    try:
        sys.modules.pop("abi", None)
        abi = importlib.import_module("abi")
        assert abi.lib.evaluate_bytecode.argtypes == [ctypes.c_char_p, ctypes.c_char_p]
        assert abi.lib.evaluate_bytecode.restype is ctypes.c_void_p, \
            "evaluate_bytecode must return an owned pointer, not ctypes.c_char_p"
        assert abi.lib.free_string.argtypes == [ctypes.c_void_p]
        assert abi.lib.free_string.restype is None
        assert abi.evaluate(b"00", b"payload") == "ALLOW"
        assert abi.evaluate(b"0", b"payload") == "BLOCK"
        for _ in range(100):
            assert abi.evaluate(b"0011", b"repeated-call") == "ALLOW"
    finally:
        sys.path.pop(0)
        sys.modules.pop("abi", None)


def test_script_uses_fixed_python_abi(tmp_path):
    fake_c = tmp_path / "fake.c"
    fake_so = tmp_path / "libwaf_core.so"
    fake_c.write_text(
        '#include <stdlib.h>\n'
        '#include <string.h>\n'
        'char *evaluate_bytecode(const char *b, const char *p) { '
        '(void)b; (void)p; return strdup("BLOCK"); }\n'
        'void free_string(char *s) { free(s); }\n'
    )
    compile_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(fake_so), str(fake_c)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    backup = tmp_path / "real-libwaf_core.so"
    shutil.copy2(LIB_PATH, backup)
    try:
        shutil.copy2(fake_so, LIB_PATH)
        result = subprocess.run(
            ["python3", AGENT_SCRIPT, "00", "abi-dependency-check"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == "BLOCK\n", \
            "evaluate.py did not use the ABI wrapper backed by py-emu/libwaf_core.so"
        assert result.stderr == ""
    finally:
        shutil.copy2(backup, LIB_PATH)


def test_exact_cli_arity():
    for args in ([], ["00"], ["00", "payload", "extra"]):
        result = subprocess.run(
            ["python3", AGENT_SCRIPT, *args],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode != 0, f"evaluate.py accepted invalid argument list: {args}"


def test_fuzz_equivalence():
    random.seed(42)
    lengths = [1, 2, 3, 4, 63, 64, 127, 128]
    lengths.extend(random.randint(1, 128) for _ in range(492))

    for i, hex_len in enumerate(lengths):
        bytecode_hex = generate_hex_string(hex_len)
        payload_len = random.randint(1, 256)
        payload = generate_payload(payload_len)
        expected = "ALLOW" if len(bytecode_hex) % 2 == 0 else "BLOCK"

        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, bytecode_hex, payload],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: bytecode={bytecode_hex}, payload={payload}")

        try:
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, bytecode_hex, payload],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: bytecode={bytecode_hex}, payload={payload}")

        assert oracle_res.returncode == 0
        assert oracle_res.stdout == expected + "\n"
        assert agent_res.returncode == oracle_res.returncode, \
            f"Return code mismatch on iter {i}.\nInput: {bytecode_hex} {payload}\nOracle: {oracle_res.returncode}\nAgent: {agent_res.returncode}\nAgent stderr: {agent_res.stderr}"
        assert agent_res.stdout == expected + "\n", \
            f"Output mismatch on iter {i}.\nInput: {bytecode_hex} {payload}\nExpected: {expected}\nAgent stdout: {agent_res.stdout!r}"
        assert agent_res.stderr == "", \
            f"evaluate.py wrote unexpected stderr on iter {i}: {agent_res.stderr!r}"
        assert agent_res.stdout.strip() == oracle_res.stdout.strip()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
