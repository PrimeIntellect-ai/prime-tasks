#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

SUITE = "/home/user/sec_suite"
UTILS = os.path.join(SUITE, "utils.sh")
RUNNER = os.path.join(SUITE, "run_tests.sh")
LOG = "/home/user/test_results.log"


def run_function(name, *args):
    result = subprocess.run(
        ["bash", "-c", 'source "$1" && shift && "$@"', "_", UTILS, name, *map(str, args)],
        capture_output=True,
        text=True,
        timeout=3,
    )
    assert result.returncode == 0, f"{name}{args} failed: {result.stderr}"
    return result.stdout.strip()


def lucas(n):
    if n == 0:
        return 2
    a, b = 2, 1
    for _ in range(1, n):
        a, b = b, a + b
    return b


def test_results_log_exists():
    assert os.path.exists(LOG), f"The log file {LOG} does not exist. Did you run the test suite and redirect the output?"
    assert os.path.isfile(LOG), f"{LOG} is not a valid file."


def test_results_log_contents():
    if not os.path.exists(LOG):
        pytest.fail(f"Log file {LOG} missing.")

    with open(LOG, "r") as f:
        content = f.read()

    assert "[PASS] Auth Test" in content, "Auth Test did not pass. Check your compare_versions logic."
    assert "[PASS] GraphQL Test" in content, "GraphQL Test did not pass. Check your generate_fuzz_length logic."
    assert "[PASS] REST Test" in content, "REST Test did not pass. Check your compare_versions logic."
    assert "[FAIL]" not in content, "There are still failing tests in the log output."


def test_run_tests_no_infinite_loop_and_log_is_genuine():
    assert os.path.exists(RUNNER), f"{RUNNER} does not exist."

    try:
        result = subprocess.run(
            ["bash", RUNNER],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Running run_tests.sh timed out. The circular sourcing (infinite recursion) issue has not been fully resolved.")

    assert result.returncode == 0, f"Script failed to run with return code {result.returncode}. Error: {result.stderr}"
    assert "Starting Security Test Suite..." in result.stdout
    assert "Test Suite Completed." in result.stdout
    assert "[PASS] Auth Test" in result.stdout
    assert "[PASS] GraphQL Test" in result.stdout
    assert "[PASS] REST Test" in result.stdout
    assert "[FAIL]" not in result.stdout

    with open(LOG, "r") as f:
        saved_log = f.read()
    assert saved_log == result.stdout, "test_results.log is not the output produced by the current run_tests.sh"


def test_include_guards_in_every_shell_file():
    shell_files = sorted(
        os.path.join(SUITE, name)
        for name in os.listdir(SUITE)
        if name.endswith(".sh")
    )
    assert shell_files, "No .sh files found in the suite"

    assignment_re = re.compile(r"^(\s*)(?:(?:export|readonly)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")

    for path in shell_files:
        assert os.path.isfile(path), f"{path} is not a regular shell file"
        with open(path, "r") as f:
            lines = f.readlines()

        meaningful = [
            (i, line) for i, line in enumerate(lines)
            if line.strip() and not line.lstrip().startswith("#")
        ]
        candidate = None
        for position, (line_index, line) in enumerate(meaningful[:20]):
            match = assignment_re.match(line)
            if not match:
                continue
            variable = match.group(2)
            prefix = "".join(x for _, x in meaningful[:position])
            variable_tested = re.search(r"\$(?:\{)?" + re.escape(variable) + r"(?:\}|\b|:)", prefix)
            early_return_guard = variable_tested and re.search(r"\breturn\b", prefix)
            wrapper_guard = variable_tested and re.search(r"\bif\b", prefix) and meaningful[-1][1].strip() == "fi"
            if early_return_guard or wrapper_guard:
                candidate = (line_index, match.group(1), variable)
                break

        assert candidate is not None, f"{path} does not contain a standard top-level Bash include guard"

        line_index, indentation, variable = candidate
        marker = "__INCLUDE_GUARD_MARKER_" + secrets.token_hex(12)
        patched = list(lines)
        patched.insert(line_index + 1, f"{indentation}printf '%s\\n' '{marker}' >&9\n")

        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as temp:
            temp.writelines(patched)
            temp_path = temp.name
        try:
            result = subprocess.run(
                ["bash", "-c", 'exec 9>&1; source "$1"; source "$1"', "_", temp_path],
                capture_output=True,
                text=True,
                timeout=3,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Sourcing {path} twice timed out; its include guard is ineffective")
        finally:
            os.unlink(temp_path)

        assert result.returncode == 0, f"Sourcing {path} twice failed: {result.stderr}"
        assert result.stdout.splitlines().count(marker) == 1, f"The include guard in {path} did not prevent a second evaluation"


def test_compare_versions_logic():
    test_cases = [
        ("1.2.10", "1.2.9", "1"),
        ("2.0.0", "2.0.0", "0"),
        ("1.9.9", "2.0.0", "-1"),
        ("0.0.1", "0.0.2", "-1"),
        ("10.0.0", "9.9.9", "1"),
    ]

    rng = secrets.SystemRandom()
    for _ in range(30):
        left = tuple(rng.randrange(0, 1_000_000) for _ in range(3))
        right = tuple(rng.randrange(0, 1_000_000) for _ in range(3))
        expected = "1" if left > right else "-1" if left < right else "0"
        test_cases.append((".".join(map(str, left)), ".".join(map(str, right)), expected))

    for _ in range(5):
        version = tuple(rng.randrange(0, 1_000_000) for _ in range(3))
        text = ".".join(map(str, version))
        test_cases.append((text, text, "0"))

    for v1, v2, expected in test_cases:
        output = run_function("compare_versions", v1, v2)
        assert output == expected, f"compare_versions {v1} {v2} returned '{output}', expected '{expected}'"


def test_generate_fuzz_length_logic():
    fixed = [(0, 2), (1, 1), (2, 3), (3, 4), (4, 7), (7, 29), (10, 123)]
    rng = secrets.SystemRandom()
    random_inputs = rng.sample(range(5, 51), 18)
    test_cases = fixed + [(n, lucas(n)) for n in random_inputs]

    for n, expected in test_cases:
        output = run_function("generate_fuzz_length", n)
        assert output == str(expected), f"generate_fuzz_length {n} returned '{output}', expected '{expected}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
