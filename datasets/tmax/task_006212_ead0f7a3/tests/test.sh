#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import subprocess
import zlib

import pytest


def test_crc_algo_c_fixed():
    file_path = "/home/user/crc_algo.c"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    with open(file_path, "r") as f:
        content = f.read()
    # Preserve the original source assertion.
    assert "i <= len" not in content, "The out-of-bounds read bug 'i <= len' is still present in crc_algo.c"


def test_crc_algo_source_is_correct_and_memory_safe(tmp_path):
    """Compile the submitted algorithm directly and exercise it under Valgrind."""
    lengths = [0, 1, 2, 3, 7, 8, 15, 16, 31, 32, 63, 64, 127, 255]
    vectors = [secrets.token_bytes(length) for length in lengths]

    checks = []
    for index, data in enumerate(vectors, start=1):
        initializer = ", ".join(str(byte) for byte in data) if data else "0"
        expected = zlib.crc32(data)
        checks.append(
            f"    const uint8_t input_{index}[] = {{{initializer}}};\n"
            f"    if (custom_crc(input_{index}, {len(data)}) != UINT32_C({expected})) return {index};"
        )

    harness = tmp_path / "crc_harness.c"
    harness.write_text(
        "#include <stddef.h>\n"
        "#include <stdint.h>\n"
        "uint32_t custom_crc(const uint8_t *data, size_t len);\n"
        "int main(void) {\n"
        + "\n".join(checks)
        + "\n    return 0;\n}\n"
    )
    executable = tmp_path / "crc_harness"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O0", "-g", "/home/user/crc_algo.c", str(harness), "-o", str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Failed to compile crc_algo.c:\n{compile_result.stderr}"

    run_result = subprocess.run(
        [
            "valgrind",
            "--quiet",
            "--leak-check=full",
            "--errors-for-leak-kinds=definite,indirect",
            "--error-exitcode=97",
            str(executable),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "crc_algo.c produced an incorrect CRC or triggered a memory error under Valgrind.\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )


def test_checksum_result_file():
    file_path = "/home/user/checksum_result.txt"
    assert os.path.exists(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        result = f.read().strip()

    expected_checksum = str(zlib.crc32(b"ALGORITHMIC_DEBUGGING"))
    assert result == expected_checksum, f"Expected checksum {expected_checksum}, but got {result}"


def test_libwrapper_so_linked_and_functional():
    lib_path = "/home/user/libwrapper.so"
    assert os.path.exists(lib_path), f"Missing file: {lib_path}"

    try:
        lib = ctypes.CDLL(lib_path)
    except OSError as e:
        pytest.fail(f"Failed to load libwrapper.so, linking issue might not be fixed: {e}")

    assert hasattr(lib, "compute_checksum"), "compute_checksum function not found in libwrapper.so"

    lib.compute_checksum.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.compute_checksum.restype = ctypes.c_uint32

    # Preserve the original fixed-input assertion.
    test_str = b"ALGORITHMIC_DEBUGGING"
    calculated_crc = lib.compute_checksum(test_str, len(test_str))
    expected_crc = zlib.crc32(test_str)
    assert calculated_crc == expected_crc, f"Library computed incorrect CRC: {calculated_crc} instead of {expected_crc}. The memory bug might still be present."

    # Exercise unpredictable inputs so a hard-coded answer cannot pass.
    inputs = [b"", b"a", b"\x00", b"abc\x00def"]
    inputs.extend(secrets.token_bytes(secrets.randbelow(512)) for _ in range(32))
    for data in inputs:
        expected = zlib.crc32(data)
        first = lib.compute_checksum(data, len(data))
        second = lib.compute_checksum(data, len(data))
        assert first == expected, f"Incorrect CRC for a verifier-generated input of length {len(data)}"
        assert second == expected, f"Non-deterministic CRC for an input of length {len(data)}"


def test_python_script_runs_successfully():
    result = subprocess.run(
        ["python3", "/home/user/test.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"test.py failed:\n{result.stderr}"
    expected = str(zlib.crc32(b"ALGORITHMIC_DEBUGGING"))
    assert result.stdout.strip() == expected, f"test.py printed {result.stdout.strip()!r}, expected {expected!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
