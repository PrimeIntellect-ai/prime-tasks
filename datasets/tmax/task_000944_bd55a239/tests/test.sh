#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import ctypes
import secrets


def test_project_directory_exists():
    assert os.path.isdir('/home/user/project'), "Directory /home/user/project/ does not exist."


def test_build_and_test_script_execution():
    script_path = '/home/user/project/build_and_test.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Execute the script
    result = subprocess.run(
        [script_path],
        cwd='/home/user/project',
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"build_and_test.sh failed with exit code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_library_and_log_exist():
    # These should exist after the script runs
    so_path = '/home/user/project/libbloom.so'
    log_path = '/home/user/project/result.log'

    assert os.path.isfile(so_path), f"Shared library {so_path} does not exist after running build_and_test.sh."
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist after running build_and_test.sh."

    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == "SUCCESS: ALL PROPERTIES PASSED", f"Unexpected content in result.log: {content}"


def load_library():
    so_path = '/home/user/project/libbloom.so'
    assert os.path.isfile(so_path), f"Shared library {so_path} is missing."

    try:
        lib = ctypes.CDLL(so_path)
    except OSError as e:
        assert False, f"Failed to load shared library: {e}"

    try:
        lib.bloom_create.argtypes = [ctypes.c_int, ctypes.c_double]
        lib.bloom_create.restype = ctypes.c_void_p

        lib.bloom_add.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.bloom_add.restype = None

        lib.bloom_check.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.bloom_check.restype = ctypes.c_int

        lib.bloom_destroy.argtypes = [ctypes.c_void_p]
        lib.bloom_destroy.restype = None
    except AttributeError as e:
        assert False, f"Library is missing required ABI function: {e}"

    return lib


def test_bloom_filter_abi_and_logic():
    lib = load_library()

    # Test logic
    bloom = lib.bloom_create(1000, 0.01)
    assert bloom is not None, "bloom_create returned NULL pointer."

    try:
        lib.bloom_add(bloom, b"test_string_1")
        lib.bloom_add(bloom, b"test_string_2")

        assert lib.bloom_check(bloom, b"test_string_1") == 1, "False negative on test_string_1"
        assert lib.bloom_check(bloom, b"test_string_2") == 1, "False negative on test_string_2"
        assert lib.bloom_check(bloom, b"test_string_3") == 0, "False positive on empty filter for test_string_3 (or extremely unlucky collision)"
    finally:
        lib.bloom_destroy(bloom)


def random_strings(count, tag):
    values = set()
    while len(values) < count:
        values.add((tag + secrets.token_hex(24)).encode('ascii'))
    return list(values)


def test_randomized_no_false_negatives_and_fresh_fixtures():
    """Exercise independently generated inputs that cannot be hardcoded."""
    lib = load_library()

    for trial in range(4):
        inserted = random_strings(160, f"insert-{trial}-")
        outsiders = random_strings(768, f"outside-{trial}-")
        bloom = lib.bloom_create(256, 0.02)
        assert bloom, "bloom_create returned NULL pointer."

        try:
            # A newly created Bloom filter has no set bits, so arbitrary strings
            # must be definitely absent.
            for value in outsiders[:64]:
                result = lib.bloom_check(bloom, value)
                assert result in (0, 1), f"bloom_check returned invalid value {result}"
                assert result == 0, "Fresh Bloom filter reported an element present"

            for value in inserted:
                lib.bloom_add(bloom, value)

            # Core required property: every generated inserted string is found.
            for value in inserted:
                assert lib.bloom_check(bloom, value) == 1, \
                    f"False negative for randomized input {value!r}"

            # Bloom filters may have false positives, but a filter configured for
            # 2% must still distinguish overwhelmingly many non-members. The loose
            # bound avoids relying on an exact hash implementation.
            results = [lib.bloom_check(bloom, value) for value in outsiders]
            assert all(value in (0, 1) for value in results), \
                "bloom_check must return exactly 0 or 1"
            false_positives = sum(results)
            assert false_positives <= 64, \
                f"Excessive false positives: {false_positives} of {len(outsiders)}"
        finally:
            lib.bloom_destroy(bloom)


def test_randomized_filter_isolation():
    lib = load_library()
    left_values = random_strings(120, "left-")
    right_values = random_strings(120, "right-")
    left = lib.bloom_create(256, 0.01)
    right = lib.bloom_create(256, 0.01)
    assert left and right, "bloom_create returned NULL pointer."

    try:
        for value in left_values:
            lib.bloom_add(left, value)
        for value in right_values:
            lib.bloom_add(right, value)

        assert all(lib.bloom_check(left, value) == 1 for value in left_values), \
            "Left fixture produced a false negative"
        assert all(lib.bloom_check(right, value) == 1 for value in right_values), \
            "Right fixture produced a false negative"

        # Separate fixtures must not simply share global membership state.
        assert sum(lib.bloom_check(left, value) for value in right_values) <= 16, \
            "Left fixture appears contaminated by right fixture state"
        assert sum(lib.bloom_check(right, value) for value in left_values) <= 16, \
            "Right fixture appears contaminated by left fixture state"
    finally:
        lib.bloom_destroy(left)
        lib.bloom_destroy(right)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
