#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import shutil
import subprocess
import tempfile

import pytest


def py_checksum(data: bytes) -> int:
    hash_val = 0x811c9dc5
    for byte in data:
        hash_val ^= byte
        hash_val = (hash_val * 0x01000193) & 0xFFFFFFFF
    return hash_val


def test_shared_library_exists():
    """Test that the C library was compiled into a shared object."""
    path = "/home/user/libmath_lib.so"
    assert os.path.isfile(path), "/home/user/libmath_lib.so is missing. Did you compile the C code?"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmath_lib.so is not an ELF shared library."


def test_shared_library_loads_and_calculates_checksum():
    """Load the submitted library and exercise its exported function on derived inputs."""
    try:
        lib = ctypes.CDLL("/home/user/libmath_lib.so")
        calculate = lib.calculate_checksum
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load calculate_checksum from libmath_lib.so: {exc}")

    calculate.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    calculate.restype = ctypes.c_uint32

    cases = [
        b"",
        b"abc",
        b"before\x00\x00after\xff",
        bytes(range(256)),
        os.urandom(8193),
    ]
    for data in cases:
        storage = (ctypes.c_uint8 * max(1, len(data)))()
        if data:
            ctypes.memmove(storage, data, len(data))
        actual = int(calculate(storage, len(data)))
        assert actual == py_checksum(data), (
            f"calculate_checksum returned {actual} for a {len(data)}-byte test input; "
            f"expected {py_checksum(data)}"
        )


def test_app_py_modifications():
    """Test that app.py was modified to fix the ABI mismatch."""
    assert os.path.isfile("/home/user/app.py"), "app.py is missing."
    with open("/home/user/app.py", "r") as f:
        content = f.read()

    # Check that c_size_t and c_uint32 are used, or equivalent fixes for 64-bit compatibility
    assert "c_size_t" in content, "app.py does not seem to use ctypes.c_size_t for the length argument."
    assert "c_uint32" in content, "app.py does not seem to use ctypes.c_uint32 for the return type."


def test_app_runs_and_calls_ffi():
    """Run app.py fresh, verify it calls the FFI function, then run it with the submitted library."""
    library = "/home/user/libmath_lib.so"
    results = "/home/user/results.json"

    probe_source = r'''
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

uint32_t calculate_checksum(const uint8_t* data, size_t length) {
    const char *marker = getenv("CHECKSUM_FFI_MARKER");
    if (marker != NULL) {
        FILE *f = fopen(marker, "a");
        if (f != NULL) {
            fprintf(f, "%zu\n", length);
            fclose(f);
        }
    }
    uint32_t hash = 0x811c9dc5u;
    for (size_t i = 0; i < length; i++) {
        hash ^= data[i];
        hash *= 0x01000193u;
    }
    return hash;
}
'''

    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "probe.c")
        probe = os.path.join(td, "probe.so")
        marker = os.path.join(td, "ffi-called")
        backup = os.path.join("/home/user", ".libmath_lib.verifier-backup.so")
        with open(source, "w") as f:
            f.write(probe_source)
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", source, "-o", probe],
            text=True,
            capture_output=True,
        )
        assert built.returncode == 0, f"Verifier could not build its FFI probe: {built.stderr}"

        if os.path.exists(results):
            os.unlink(results)
        if os.path.exists(backup):
            os.unlink(backup)

        os.replace(library, backup)
        try:
            shutil.copy2(probe, library)
            env = os.environ.copy()
            env["CHECKSUM_FFI_MARKER"] = marker
            run = subprocess.run(
                ["python3", "/home/user/app.py"],
                cwd="/home/user",
                env=env,
                text=True,
                capture_output=True,
                timeout=30,
            )
            assert run.returncode == 0, f"app.py failed while exercising its FFI binding:\n{run.stdout}\n{run.stderr}"
            assert os.path.isfile(marker), "app.py did not call calculate_checksum through the shared library."
            with open(marker, "r") as f:
                lengths = [int(line.strip()) for line in f if line.strip()]
            assert os.path.getsize("/home/user/payload.bin") in lengths, (
                "app.py did not pass the complete payload length to calculate_checksum."
            )
        finally:
            if os.path.exists(backup):
                os.replace(backup, library)

    # Generate the final results using the agent's actual submitted library.
    if os.path.exists(results):
        os.unlink(results)
    run = subprocess.run(
        ["python3", "/home/user/app.py"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert run.returncode == 0, f"app.py failed with the submitted library:\n{run.stdout}\n{run.stderr}"


def test_results_json_exists():
    """Test that the app.py script successfully generated the results.json file."""
    assert os.path.isfile("/home/user/results.json"), "/home/user/results.json is missing. Did you run app.py?"


def test_results_json_content():
    """Test that results.json contains the correct checksum and benchmarking result."""
    assert os.path.isfile("/home/user/payload.bin"), "payload.bin is missing."
    assert os.path.isfile("/home/user/results.json"), "results.json is missing."

    with open("/home/user/payload.bin", "rb") as f:
        data = f.read()

    expected_checksum = py_checksum(data)

    with open("/home/user/results.json", "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file.")

    assert "checksum" in results, "results.json is missing the 'checksum' key."
    assert results["checksum"] == expected_checksum, f"Checksum in results.json ({results['checksum']}) does not match the expected value ({expected_checksum}). The FFI binding might still be truncating data or using wrong types."

    assert "c_faster_than_py" in results, "results.json is missing the 'c_faster_than_py' key."
    # The C version should generally be faster than the pure Python version.
    assert results["c_faster_than_py"] is True, "c_faster_than_py is not true. The C implementation should be faster."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
