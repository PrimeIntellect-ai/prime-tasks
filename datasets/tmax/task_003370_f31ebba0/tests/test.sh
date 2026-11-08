#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import shutil
import subprocess
import tempfile


def test_rust_project_configuration():
    cargo_toml_path = "/home/user/decoder/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"Cargo.toml missing at {cargo_toml_path}"

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    # Check for cdylib configuration
    assert "cdylib" in content, "Cargo.toml does not specify crate-type as 'cdylib'"


def test_rust_library_compiled():
    so_path = "/home/user/decoder/target/release/libdecoder.so"
    assert os.path.isfile(so_path), f"Compiled Rust library not found at {so_path}. Did you build in release mode?"


def _load_decoder():
    so_path = "/home/user/decoder/target/release/libdecoder.so"
    lib = ctypes.CDLL(so_path)
    func = lib.decode_payload
    func.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
    ]
    func.restype = ctypes.c_ssize_t
    return lib, func


def _call_decoder(func, encoded, max_len):
    input_array = (ctypes.c_uint8 * max(1, len(encoded)))()
    if encoded:
        ctypes.memmove(input_array, encoded, len(encoded))
    output_array = (ctypes.c_uint8 * max(1, max_len))()
    result = func(input_array, len(encoded), output_array, max_len)
    return result, bytes(output_array[:max(0, result)]) if result >= 0 else b""


def test_decode_payload_behavior():
    _lib, decode_payload = _load_decoder()

    payloads = [
        b"",
        b"Rust FFI",
        "Unicode: café / 東京 / 🦀".encode("utf-8"),
        b"embedded\x00nul",
        ("random-" + secrets.token_hex(31)).encode("ascii"),
    ]
    for plain in payloads:
        encoded = bytes(byte ^ 0xAA for byte in plain)
        result, output = _call_decoder(decode_payload, encoded, len(plain))
        assert result == len(plain)
        assert output == plain

        if plain:
            result, _ = _call_decoder(decode_payload, encoded, len(plain) - 1)
            assert result == -1, "decode_payload must reject output exceeding max_len"

    # These byte sequences become invalid UTF-8 after XOR decoding.
    for invalid_plain in (b"\xff", b"\xc3(", b"\xed\xa0\x80"):
        encoded = bytes(byte ^ 0xAA for byte in invalid_plain)
        result, _ = _call_decoder(decode_payload, encoded, 1024)
        assert result == -1, "decode_payload must reject invalid UTF-8"


def test_python_script_exists():
    script_path = "/home/user/app/process.py"
    assert os.path.isfile(script_path), f"Python script missing at {script_path}"


def test_process_executes_real_library_and_ffi_call():
    app = "/home/user/app"
    encoded_path = os.path.join(app, "encoded.dat")
    decoded_path = os.path.join(app, "decoded.txt")
    script_path = os.path.join(app, "process.py")
    so_path = "/home/user/decoder/target/release/libdecoder.so"

    original_encoded = open(encoded_path, "rb").read()
    original_decoded = open(decoded_path, "rb").read() if os.path.exists(decoded_path) else None

    try:
        # Exercise process.py on an unpredictable valid payload.
        plain = ("runtime-" + secrets.token_hex(40) + "-🦀").encode("utf-8")
        with open(encoded_path, "wb") as f:
            f.write(bytes(byte ^ 0xAA for byte in plain))
        subprocess.run(["python3", script_path], check=True, timeout=30)
        with open(decoded_path, "rb") as f:
            assert f.read() == plain

        # Replace the library briefly with a hidden test implementation whose
        # result cannot be reproduced by merely XORing encoded.dat in Python.
        marker = ("ffi-called-" + secrets.token_hex(24)).encode("ascii")
        with tempfile.TemporaryDirectory() as td:
            c_path = os.path.join(td, "shim.c")
            shim_path = os.path.join(td, "libdecoder.so")
            backup_path = os.path.join(td, "real-libdecoder.so")
            marker_values = ",".join(str(b) for b in marker)
            c_source = f'''\n#include <stdint.h>\n#include <stddef.h>\n#include <sys/types.h>\nssize_t decode_payload(const uint8_t *input, size_t input_len, uint8_t *output, size_t max_len) {{\n    (void)input; (void)input_len;\n    static const uint8_t value[] = {{{marker_values}}};\n    if (max_len < sizeof(value)) return -1;\n    for (size_t i = 0; i < sizeof(value); ++i) output[i] = value[i];\n    return (ssize_t)sizeof(value);\n}}\n'''
            with open(c_path, "w") as f:
                f.write(c_source)
            subprocess.run(["cc", "-shared", "-fPIC", "-o", shim_path, c_path], check=True, timeout=30)
            shutil.copy2(so_path, backup_path)
            try:
                os.replace(shim_path, so_path)
                with open(encoded_path, "wb") as f:
                    f.write(secrets.token_bytes(37))
                subprocess.run(["python3", script_path], check=True, timeout=30)
                with open(decoded_path, "rb") as f:
                    assert f.read() == marker, "process.py did not use the decode_payload result from libdecoder.so"
            finally:
                os.replace(backup_path, so_path)
    finally:
        with open(encoded_path, "wb") as f:
            f.write(original_encoded)
        if original_decoded is None:
            if os.path.exists(decoded_path):
                os.unlink(decoded_path)
        else:
            with open(decoded_path, "wb") as f:
                f.write(original_decoded)


def test_decoded_output():
    output_path = "/home/user/app/decoded.txt"
    assert os.path.isfile(output_path), f"Decoded output file missing at {output_path}"

    with open(output_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_text = "Secret Rust FFI Migration Payload 2024!"
    assert content == expected_text, f"Decoded text does not match the expected payload. Got: {content}"


def _apply_unified_diff(source_lines, patch_lines):
    result = []
    source_pos = 0
    i = 0
    saw_hunk = False

    while i < len(patch_lines):
        if not patch_lines[i].startswith("@@ "):
            i += 1
            continue

        saw_hunk = True
        match = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", patch_lines[i])
        assert match, f"Malformed unified diff hunk header: {patch_lines[i]!r}"
        old_start = int(match.group(1))
        old_count = int(match.group(2) or "1")
        new_count = int(match.group(4) or "1")
        target_pos = old_start - 1
        assert target_pos >= source_pos, "Overlapping or out-of-order patch hunks"
        result.extend(source_lines[source_pos:target_pos])
        source_pos = target_pos
        consumed_old = 0
        produced_new = 0
        i += 1

        while i < len(patch_lines) and not patch_lines[i].startswith("@@ "):
            line = patch_lines[i]
            assert line and line[0] in " +-\\", f"Invalid line in unified diff: {line!r}"
            if line.startswith("\\"):
                i += 1
                continue

            payload = line[1:]
            if i + 1 < len(patch_lines) and patch_lines[i + 1].startswith("\\ No newline"):
                payload = payload.rstrip("\r\n")

            if line[0] == " ":
                assert source_pos < len(source_lines) and source_lines[source_pos] == payload, "Patch context does not match legacy_process.py"
                result.append(payload)
                source_pos += 1
                consumed_old += 1
                produced_new += 1
            elif line[0] == "-":
                assert source_pos < len(source_lines) and source_lines[source_pos] == payload, "Patch removal does not match legacy_process.py"
                source_pos += 1
                consumed_old += 1
            elif line[0] == "+":
                result.append(payload)
                produced_new += 1
            i += 1

        assert consumed_old == old_count, "Patch hunk has an incorrect old-line count"
        assert produced_new == new_count, "Patch hunk has an incorrect new-line count"

    assert saw_hunk, "Patch contains no unified diff hunks"
    result.extend(source_lines[source_pos:])
    return result


def test_migration_patch():
    patch_path = "/home/user/app/migration.patch"
    assert os.path.isfile(patch_path), f"Migration patch missing at {patch_path}"

    with open(patch_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert len(lines) >= 2, "Patch file is too short"

    # Check for unified diff headers
    has_minus = any(line.startswith("--- ") for line in lines[:5])
    has_plus = any(line.startswith("+++ ") for line in lines[:5])

    assert has_minus and has_plus, "Patch file does not appear to be a valid unified diff (missing --- or +++ headers)"

    content = "".join(lines)
    assert "legacy_process.py" in content, "Patch file does not reference legacy_process.py"
    assert "process.py" in content, "Patch file does not reference process.py"

    with open("/home/user/app/legacy_process.py", "r", encoding="utf-8", newline="") as f:
        legacy_lines = f.readlines()
    with open("/home/user/app/process.py", "r", encoding="utf-8", newline="") as f:
        process_lines = f.readlines()

    reconstructed = _apply_unified_diff(legacy_lines, lines)
    assert reconstructed == process_lines, "migration.patch does not actually transform legacy_process.py into process.py"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
