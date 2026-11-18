#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import subprocess

TEST_FILE = "/home/user/test_math_utility.py"
MODULE_FILE = "/home/user/math_utility.py"

CANONICAL = '''import ctypes
from packaging import import version
import math

def run_calculation(lib_path, value):
    try:
        lib = ctypes.CDLL(lib_path)
    except OSError:
        return None

    lib.get_version.restype = ctypes.c_char_p
    v_str = lib.get_version().decode('utf-8')

    if version.parse(v_str) >= version.parse("2.0.0"):
        lib.advanced_calc.restype = ctypes.c_double
        lib.advanced_calc.argtypes = [ctypes.c_double]
        return lib.advanced_calc(float(value))
    else:
        return math.sqrt(float(value))
'''

# Correct a construction typo without changing the module under test.
CANONICAL = CANONICAL.replace("from packaging import version", "from packaging import version")


def run_user_tests(node=None):
    for path in glob.glob("/home/user/__pycache__/math_utility*.pyc"):
        os.remove(path)
    target = TEST_FILE if node is None else f"{TEST_FILE}::{node}"
    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user" + os.pathsep + env.get("PYTHONPATH", "")
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return subprocess.run(
        ["python3", "-B", "-m", "pytest", "-q", target],
        cwd="/home/user",
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def install_module(source):
    with open(MODULE_FILE, "w", encoding="utf-8") as f:
        f.write(source)


def assert_mutant_is_caught(name, node, source):
    install_module(source)
    result = run_user_tests(node)
    assert result.returncode != 0, (
        f"{node} did not detect the {name} defect.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_test_file_exists():
    """Verify that the test file was created."""
    assert os.path.isfile(TEST_FILE), "The file /home/user/test_math_utility.py is missing."


def test_results_file_exists():
    """Verify that the test results file was created."""
    assert os.path.isfile("/home/user/test_results.txt"), "The file /home/user/test_results.txt is missing."


def test_test_file_contents():
    """Verify that the test file contains the required test cases and uses mock."""
    with open(TEST_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    assert "def test_legacy_version_fallback" in content, "Missing test_legacy_version_fallback in test_math_utility.py."
    assert "def test_modern_version_abi" in content, "Missing test_modern_version_abi in test_math_utility.py."
    assert "mock" in content, "Missing mock usage in test_math_utility.py."


def test_saved_results_are_pytest_output():
    with open("/home/user/test_results.txt", "r", encoding="utf-8", errors="replace") as f:
        output = f.read()
    match = re.search(r"\b(\d+) passed\b", output)
    assert match and int(match.group(1)) >= 2, (
        "test_results.txt does not contain successful pytest output for at least two tests."
    )
    assert not re.search(r"\b(?:failed|error)s?\b", output, re.IGNORECASE), (
        "test_results.txt contains a pytest failure or error."
    )


def test_pytest_passes():
    """Verify that the tests written in test_math_utility.py pass successfully."""
    result = subprocess.run(
        ["python3", "-m", "pytest", TEST_FILE],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"pytest failed on test_math_utility.py.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_required_tests_exercise_all_required_behavior():
    with open(MODULE_FILE, "r", encoding="utf-8") as f:
        original_module = f.read()

    try:
        # First ensure the named tests pass independently against the real supplied implementation.
        install_module(CANONICAL)
        for node in ("test_legacy_version_fallback", "test_modern_version_abi"):
            result = run_user_tests(node)
            assert result.returncode == 0, (
                f"{node} does not pass against the supplied implementation.\n"
                f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            )

        legacy_path = CANONICAL.replace(
            "    lib.get_version.restype = ctypes.c_char_p",
            "    if lib_path == 'dummy_path.so':\n        return 5.0\n\n    lib.get_version.restype = ctypes.c_char_p",
        )
        assert_mutant_is_caught("wrong legacy result for dummy_path.so", "test_legacy_version_fallback", legacy_path)

        legacy_version = CANONICAL.replace(
            "    if version.parse(v_str) >= version.parse(\"2.0.0\"):",
            "    if v_str == '1.9.9':\n        return 5.0\n\n    if version.parse(v_str) >= version.parse(\"2.0.0\"):",
        )
        assert_mutant_is_caught("wrong behavior specifically for version 1.9.9", "test_legacy_version_fallback", legacy_version)

        legacy_calls_advanced = CANONICAL.replace(
            "    else:\n        return math.sqrt(float(value))",
            "    else:\n        lib.advanced_calc(float(value))\n        return math.sqrt(float(value))",
        )
        assert_mutant_is_caught("advanced_calc called on the legacy path", "test_legacy_version_fallback", legacy_calls_advanced)

        modern_path = CANONICAL.replace(
            "    lib.get_version.restype = ctypes.c_char_p",
            "    if lib_path == 'dummy_path.so':\n        return 88.8\n\n    lib.get_version.restype = ctypes.c_char_p",
        )
        assert_mutant_is_caught("wrong modern result for dummy_path.so", "test_modern_version_abi", modern_path)

        modern_version = CANONICAL.replace(
            "    if version.parse(v_str) >= version.parse(\"2.0.0\"):",
            "    if v_str == '2.1.0':\n        return 88.8\n\n    if version.parse(v_str) >= version.parse(\"2.0.0\"):",
        )
        assert_mutant_is_caught("wrong behavior specifically for version 2.1.0", "test_modern_version_abi", modern_version)

        modern_return = CANONICAL.replace(
            "        return lib.advanced_calc(float(value))",
            "        lib.advanced_calc(float(value))\n        return 88.8",
        )
        assert_mutant_is_caught("wrong modern return value", "test_modern_version_abi", modern_return)

        modern_argument = CANONICAL.replace(
            "        return lib.advanced_calc(float(value))",
            "        return lib.advanced_calc(float(value) + 1.0)",
        )
        assert_mutant_is_caught("wrong advanced_calc argument", "test_modern_version_abi", modern_argument)

        modern_twice = CANONICAL.replace(
            "        return lib.advanced_calc(float(value))",
            "        lib.advanced_calc(float(value))\n        return lib.advanced_calc(float(value))",
        )
        assert_mutant_is_caught("advanced_calc called twice", "test_modern_version_abi", modern_twice)
    finally:
        install_module(original_module)
        for path in glob.glob("/home/user/__pycache__/math_utility*.pyc"):
            os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
