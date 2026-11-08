#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import subprocess
import tempfile
import pytest

TASK_DIR = "/home/user/abi_task"
OLD_SO = os.path.join(TASK_DIR, "libold.so")
NEW_SO = os.path.join(TASK_DIR, "libnew.so")
SHIM_S = os.path.join(TASK_DIR, "shim.s")
SHIM_SO = os.path.join(TASK_DIR, "libshim.so")
FINAL_SYMBOLS = os.path.join(TASK_DIR, "final_symbols.txt")

EXPECTED_SYMBOLS = [
    "core_process",
    "legacy_hash_func",
    "matrix_transform_v1",
    "matrix_transform_v2",
    "optimize_path",
    "validate_state"
]


def exported_functions(path):
    try:
        output = subprocess.check_output(
            ["nm", "-D", "--defined-only", path],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {path}: {e.output}")
    except FileNotFoundError:
        pytest.fail("The 'nm' tool is not available.")

    symbols = set()
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in ("T", "W"):
            name = parts[2]
            if not name.startswith("_"):
                symbols.add(name)
    return symbols


def assert_functions_return_zero(library_path, names):
    try:
        library = ctypes.CDLL(library_path)
    except OSError as e:
        pytest.fail(f"Could not load {library_path} as a shared library: {e}")

    cases = [
        (0, 0, 0, 0, 0, 0),
        (1, 2, 3, 4, 5, 6),
        (-1, -7, 19, 0, 12345, -999),
    ]
    for name in sorted(names):
        try:
            function = getattr(library, name)
        except AttributeError:
            pytest.fail(f"{library_path} does not export {name}")
        function.restype = ctypes.c_int
        function.argtypes = [ctypes.c_int] * 6
        for args in cases:
            result = function(*args)
            assert result == 0, (
                f"{name} from {library_path} returned {result} for {args}, not integer 0"
            )


def test_shim_assembly_exists():
    assert os.path.isfile(SHIM_S), f"Assembly shim file not found at {SHIM_S}"


def test_shim_library_exists():
    assert os.path.isfile(SHIM_SO), f"Compiled shim library not found at {SHIM_SO}"


def test_shim_exports_missing_symbols():
    exported_symbols = exported_functions(SHIM_SO)
    assert "legacy_hash_func" in exported_symbols, "libshim.so is missing the export for 'legacy_hash_func'"
    assert "matrix_transform_v1" in exported_symbols, "libshim.so is missing the export for 'matrix_transform_v1'"

    old_symbols = exported_functions(OLD_SO)
    new_symbols = exported_functions(NEW_SO)
    missing_symbols = old_symbols - new_symbols
    assert exported_symbols == missing_symbols, (
        f"libshim.so exports {sorted(exported_symbols)}, but the missing functions are "
        f"{sorted(missing_symbols)}"
    )
    assert_functions_return_zero(SHIM_SO, missing_symbols)


def test_assembly_builds_the_required_shim():
    old_symbols = exported_functions(OLD_SO)
    new_symbols = exported_functions(NEW_SO)
    missing_symbols = old_symbols - new_symbols

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_so = os.path.join(temp_dir, "libshim_rebuilt.so")
        try:
            subprocess.check_output(
                ["gcc", "-shared", "-fPIC", SHIM_S, "-o", rebuilt_so],
                stderr=subprocess.STDOUT,
                text=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"shim.s could not be compiled into a shared library:\n{e.output}")

        rebuilt_symbols = exported_functions(rebuilt_so)
        assert rebuilt_symbols == missing_symbols, (
            f"A library rebuilt from shim.s exports {sorted(rebuilt_symbols)}, but the "
            f"missing functions are {sorted(missing_symbols)}"
        )
        assert_functions_return_zero(rebuilt_so, missing_symbols)


def test_final_symbols_file():
    assert os.path.isfile(FINAL_SYMBOLS), f"Final symbols file not found at {FINAL_SYMBOLS}"

    with open(FINAL_SYMBOLS, "r") as f:
        actual_symbols = [line.strip() for line in f if line.strip()]

    assert actual_symbols == EXPECTED_SYMBOLS, (
        f"Contents of {FINAL_SYMBOLS} do not match the expected list.\n"
        f"Expected: {EXPECTED_SYMBOLS}\n"
        f"Actual: {actual_symbols}"
    )

    merged_symbols = sorted(exported_functions(NEW_SO) | exported_functions(SHIM_SO))
    assert actual_symbols == merged_symbols, (
        f"Contents of {FINAL_SYMBOLS} are not the sorted, deduplicated exports of "
        f"libnew.so and libshim.so.\nExpected from libraries: {merged_symbols}\n"
        f"Actual: {actual_symbols}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
