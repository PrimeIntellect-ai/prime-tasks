#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

import pytest

APP_DIR = "/home/user/app"
BUILD_SCRIPT = os.path.join(APP_DIR, "build_and_test.sh")
RESULT_JSON = os.path.join(APP_DIR, "result.json")
INPUT_JSON = os.path.join(APP_DIR, "input.json")
ASM_HELPER_C = os.path.join(APP_DIR, "asm_helper.c")
ASM_HELPER_SO = os.path.join(APP_DIR, "libasm_helper.so")
RUST_DIR = os.path.join(APP_DIR, "rust_transform")
RUST_SOURCE = os.path.join(RUST_DIR, "src", "lib.rs")
RUST_TARGET_SO = os.path.join(RUST_DIR, "target", "release", "librust_transform.so")
RUST_TRANSFORM_SO = os.path.join(APP_DIR, "librust_transform.so")


def run_build():
    return subprocess.run(
        [BUILD_SCRIPT],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def xor_bytes(data):
    checksum = 0
    for byte in data:
        checksum ^= byte
    return checksum


def test_build_script_exists_and_executable():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script {BUILD_SCRIPT} does not exist."
    assert os.access(BUILD_SCRIPT, os.X_OK), f"Build script {BUILD_SCRIPT} is not executable."


def test_build_and_test_execution():
    # Remove result.json if it exists to ensure the script generates it
    if os.path.exists(RESULT_JSON):
        os.remove(RESULT_JSON)

    result = run_build()
    assert result.returncode == 0, f"build_and_test.sh failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_shared_libraries_generated():
    assert os.path.isfile(ASM_HELPER_SO), f"C shared library {ASM_HELPER_SO} was not generated."
    assert os.path.isfile(RUST_TRANSFORM_SO), f"Rust shared library {RUST_TRANSFORM_SO} was not copied to the app directory."


def test_result_json_correct():
    assert os.path.isfile(RESULT_JSON), f"Output file {RESULT_JSON} was not created."

    with open(INPUT_JSON, "r") as f:
        input_data = json.load(f)

    with open(RESULT_JSON, "r") as f:
        try:
            result_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_JSON} is not valid JSON.")

    assert isinstance(result_data, list), "result.json should contain a JSON array."
    assert len(result_data) == len(input_data), f"result.json should have {len(input_data)} items, got {len(result_data)}."

    expected_results = []
    for item in input_data:
        payload = item.get("payload", "")
        reversed_payload = payload[::-1]
        checksum = 0
        for char in reversed_payload:
            checksum ^= ord(char)
        expected_results.append({
            "id": item.get("id"),
            "reversed": reversed_payload,
            "checksum": checksum,
        })

    for expected, actual in zip(expected_results, result_data):
        assert actual.get("id") == expected["id"], f"Expected id {expected['id']}, got {actual.get('id')}."
        assert actual.get("reversed") == expected["reversed"], f"Expected reversed payload '{expected['reversed']}', got '{actual.get('reversed')}'."
        assert actual.get("checksum") == expected["checksum"], f"Expected checksum {expected['checksum']} for '{expected['reversed']}', got {actual.get('checksum')}."


def test_native_libraries_export_working_functions():
    assert os.path.isfile(ASM_HELPER_C), f"Missing C source {ASM_HELPER_C}."
    assert os.path.isfile(RUST_SOURCE), f"Missing Rust source {RUST_SOURCE}."

    try:
        rust = ctypes.CDLL(RUST_TRANSFORM_SO)
        reverse_string = rust.reverse_string
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load reverse_string from {RUST_TRANSFORM_SO}: {exc}")

    reverse_string.argtypes = [ctypes.c_char_p]
    reverse_string.restype = ctypes.c_void_p
    for text in ["", "Agent-42", "hé🙂"]:
        ptr = reverse_string(text.encode("utf-8"))
        assert ptr, "reverse_string returned a null pointer."
        actual = ctypes.string_at(ptr).decode("utf-8")
        assert actual == text[::-1], f"reverse_string({text!r}) returned {actual!r}."

    try:
        asm = ctypes.CDLL(ASM_HELPER_SO)
        xor_checksum = asm.xor_checksum
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load xor_checksum from {ASM_HELPER_SO}: {exc}")

    xor_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]
    xor_checksum.restype = ctypes.c_uint8
    for data, length in [(b"", 0), (b"abcdef", 6), (b"abcdef", 3), (b"\xff\x80A", 3)]:
        actual = xor_checksum(data, length)
        assert actual == xor_bytes(data[:length]), f"xor_checksum returned {actual} for {data[:length]!r}."


def test_sources_build_into_working_shared_libraries():
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_c = os.path.join(temp_dir, "libasm_helper.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", ASM_HELPER_C, "-o", rebuilt_c],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"asm_helper.c did not compile.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        rebuilt = ctypes.CDLL(rebuilt_c)
        rebuilt.xor_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]
        rebuilt.xor_checksum.restype = ctypes.c_uint8
        sample = b"source-check"
        assert rebuilt.xor_checksum(sample, len(sample)) == xor_bytes(sample)

    submitted_hash = hashlib.sha256(open(RUST_TRANSFORM_SO, "rb").read()).hexdigest()
    clean = subprocess.run(["cargo", "clean"], cwd=RUST_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert clean.returncode == 0, f"cargo clean failed.\n{clean.stderr}"
    rebuilt = subprocess.run(["cargo", "build", "--release"], cwd=RUST_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert rebuilt.returncode == 0, f"Rust source did not compile in release mode.\nSTDOUT:\n{rebuilt.stdout}\nSTDERR:\n{rebuilt.stderr}"
    assert os.path.isfile(RUST_TARGET_SO), "cargo build --release did not create librust_transform.so."
    target_hash = hashlib.sha256(open(RUST_TARGET_SO, "rb").read()).hexdigest()
    assert submitted_hash == target_hash, "The app Rust library is not the release library produced from the submitted Rust crate."


def test_build_pipeline_handles_derived_input():
    with open(INPUT_JSON, "rb") as f:
        original_input = f.read()
    original_result = None
    if os.path.exists(RESULT_JSON):
        with open(RESULT_JSON, "rb") as f:
            original_result = f.read()

    derived_input = [
        {"id": 701, "payload": "not-the-fixture"},
        {"id": -8, "payload": "AaZ09!?"},
        {"id": 33, "payload": ""},
    ]
    try:
        with open(INPUT_JSON, "w") as f:
            json.dump(derived_input, f)
        if os.path.exists(RESULT_JSON):
            os.remove(RESULT_JSON)
        result = run_build()
        assert result.returncode == 0, f"Build failed on a derived input.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        with open(RESULT_JSON, "r") as f:
            actual = json.load(f)
        expected = []
        for item in derived_input:
            reversed_payload = item["payload"][::-1]
            expected.append({
                "id": item["id"],
                "reversed": reversed_payload,
                "checksum": xor_bytes(reversed_payload.encode("utf-8")),
            })
        assert actual == expected
    finally:
        with open(INPUT_JSON, "wb") as f:
            f.write(original_input)
        if original_result is None:
            if os.path.exists(RESULT_JSON):
                os.remove(RESULT_JSON)
        else:
            with open(RESULT_JSON, "wb") as f:
                f.write(original_result)


def test_main_uses_both_ffi_libraries():
    rust_shim_source = r'''
#include <stdlib.h>
#include <string.h>
char *reverse_string(const char *input) {
    const char prefix[] = "ffi:";
    size_t n = strlen(input);
    char *out = malloc(n + sizeof(prefix));
    memcpy(out, prefix, sizeof(prefix) - 1);
    memcpy(out + sizeof(prefix) - 1, input, n + 1);
    return out;
}
'''
    asm_shim_source = r'''
#include <stdint.h>
uint8_t xor_checksum(const char *data, int len) {
    unsigned int value = 0xA5;
    for (int i = 0; i < len; ++i)
        value = (value + (unsigned char)data[i] + (unsigned int)i * 17U) & 0xFFU;
    return (uint8_t)value;
}
'''
    probe_input = [
        {"id": 91, "payload": "alpha"},
        {"id": 92, "payload": "Z9!"},
    ]

    def shim_checksum(data):
        value = 0xA5
        for index, byte in enumerate(data):
            value = (value + byte + index * 17) & 0xFF
        return value

    with tempfile.TemporaryDirectory() as temp_dir:
        rust_c = os.path.join(temp_dir, "rust_shim.c")
        asm_c = os.path.join(temp_dir, "asm_shim.c")
        rust_so = os.path.join(temp_dir, "rust_shim.so")
        asm_so = os.path.join(temp_dir, "asm_shim.so")
        rust_backup = os.path.join(temp_dir, "rust_backup.so")
        asm_backup = os.path.join(temp_dir, "asm_backup.so")
        input_backup = os.path.join(temp_dir, "input.json")
        result_backup = os.path.join(temp_dir, "result.json")

        with open(rust_c, "w") as f:
            f.write(rust_shim_source)
        with open(asm_c, "w") as f:
            f.write(asm_shim_source)
        for source, output in [(rust_c, rust_so), (asm_c, asm_so)]:
            compiled = subprocess.run(["gcc", "-shared", "-fPIC", source, "-o", output], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            assert compiled.returncode == 0, compiled.stderr

        shutil.copy2(RUST_TRANSFORM_SO, rust_backup)
        shutil.copy2(ASM_HELPER_SO, asm_backup)
        shutil.copy2(INPUT_JSON, input_backup)
        had_result = os.path.exists(RESULT_JSON)
        if had_result:
            shutil.copy2(RESULT_JSON, result_backup)

        try:
            os.replace(rust_so, RUST_TRANSFORM_SO)
            os.replace(asm_so, ASM_HELPER_SO)
            with open(INPUT_JSON, "w") as f:
                json.dump(probe_input, f)
            if os.path.exists(RESULT_JSON):
                os.remove(RESULT_JSON)

            result = subprocess.run(
                ["python3", os.path.join(APP_DIR, "main.py")],
                cwd=APP_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert result.returncode == 0, f"main.py failed with FFI probe libraries.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            with open(RESULT_JSON, "r") as f:
                actual = json.load(f)

            expected = []
            for item in probe_input:
                transformed = "ffi:" + item["payload"]
                expected.append({
                    "id": item["id"],
                    "reversed": transformed,
                    "checksum": shim_checksum(transformed.encode("utf-8")),
                })
            assert actual == expected, "main.py did not use the return values from both shared libraries."
        finally:
            os.replace(rust_backup, RUST_TRANSFORM_SO)
            os.replace(asm_backup, ASM_HELPER_SO)
            os.replace(input_backup, INPUT_JSON)
            if had_result:
                os.replace(result_backup, RESULT_JSON)
            elif os.path.exists(RESULT_JSON):
                os.remove(RESULT_JSON)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
