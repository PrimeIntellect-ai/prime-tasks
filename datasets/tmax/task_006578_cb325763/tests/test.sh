#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import json
import pytest

SCRIPT_PATH = "/home/user/fuzz_routing.sh"
OUT_FILE = "/home/user/routing_tests.jsonl"


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def run_and_validate():
    """Run the script and validate one generated output file."""
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} was not created."

    with open(OUT_FILE, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 100, (
        f"Expected exactly 100 lines in {OUT_FILE}, got {len(lines)}."
    )

    versions = []
    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        assert "client_version" in data, (
            f"Line {i+1} missing 'client_version': {line}"
        )
        assert "expected_routing" in data, (
            f"Line {i+1} missing 'expected_routing': {line}"
        )

        version = data["client_version"]
        action = data["expected_routing"]
        versions.append(version)

        parts = version.split(".")
        assert len(parts) == 3, (
            f"Line {i+1} version '{version}' is not in Major.Minor.Patch format."
        )

        try:
            major, minor, patch = map(int, parts)
        except ValueError:
            pytest.fail(f"Line {i+1} version '{version}' contains non-integer parts.")

        assert 0 <= major <= 3, (
            f"Line {i+1} Major version {major} out of range [0, 3]."
        )
        assert 0 <= minor <= 15, (
            f"Line {i+1} Minor version {minor} out of range [0, 15]."
        )
        assert 0 <= patch <= 15, (
            f"Line {i+1} Patch version {patch} out of range [0, 15]."
        )

        expected_action = "route_v1"
        if major > 1:
            expected_action = "route_v2"
        elif major == 1:
            if minor > 10:
                expected_action = "route_v2"
            elif minor == 10:
                if patch >= 5:
                    expected_action = "route_v2"

        assert action == expected_action, (
            f"Line {i+1} version '{version}' expected "
            f"'{expected_action}', got '{action}'."
        )

    # Random draws from 1024 possible versions should have substantial diversity.
    assert len(set(versions)) >= 80, (
        f"Expected random, diverse versions; only {len(set(versions))} unique "
        "versions were generated out of 100."
    )
    return versions


def test_script_execution_and_output():
    """Validate correctness, diversity, rerun variability, and overwrite behavior."""
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)

    runs = [run_and_validate() for _ in range(3)]
    version_sets = [frozenset(run) for run in runs]

    assert len(set(version_sets)) == len(version_sets), (
        "Repeated executions produced the same set of versions; output does not "
        "appear to be randomly generated."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
