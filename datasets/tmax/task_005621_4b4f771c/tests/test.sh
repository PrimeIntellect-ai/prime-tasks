#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest


def test_analyze_script_exists_is_executable_and_runs():
    """Verify the requested deliverable exists, is executable, and generates fresh outputs."""
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist or is not a regular file"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    for output_path in ("/home/user/sample.txt", "/home/user/best_match.txt"):
        if os.path.lexists(output_path):
            os.remove(output_path)

    try:
        subprocess.run(
            ["./analyze.sh"],
            cwd="/home/user",
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"analyze.sh failed with exit code {e.returncode}. "
            f"stdout: {e.stdout!r}; stderr: {e.stderr!r}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.sh did not complete within 30 seconds")


def get_expected_descriptions():
    descriptions = []
    for i in range(1, 51):
        file_path = f"/home/user/artifacts/exp_{i}.log"
        assert os.path.isfile(file_path), f"Missing artifact file: {file_path}"
        with open(file_path, "r") as f:
            found = False
            for line in f:
                if line.startswith("Artifact-Desc: "):
                    descriptions.append(line.strip().replace("Artifact-Desc: ", "", 1))
                    found = True
                    break
            assert found, f"No 'Artifact-Desc: ' line found in {file_path}"
    return descriptions


def get_expected_indices():
    cmd = ["bash", "-c", "RANDOM=123; for i in {1..20}; do echo $((RANDOM % 50)); done"]
    output = subprocess.check_output(cmd, text=True)
    return [int(x) for x in output.strip().split()]


def test_sample_txt_content():
    """Test that sample.txt contains the correct bootstrap sample based on Bash's RANDOM=123."""
    sample_path = "/home/user/sample.txt"
    assert os.path.isfile(sample_path), f"{sample_path} does not exist"

    descriptions = get_expected_descriptions()
    indices = get_expected_indices()

    expected_sample = [descriptions[i] for i in indices]

    with open(sample_path, "r") as f:
        actual_sample = [line.strip() for line in f if line.strip()]

    assert actual_sample == expected_sample, f"Contents of {sample_path} do not match the expected bootstrap sample. Ensure ordering and RANDOM=123 logic are correct."


def test_best_match_txt_content():
    """Test that best_match.txt contains the correct output from retrieve.py."""
    best_match_path = "/home/user/best_match.txt"
    sample_path = "/home/user/sample.txt"

    assert os.path.isfile(best_match_path), f"{best_match_path} does not exist"
    assert os.path.isfile(sample_path), f"{sample_path} does not exist for retrieval"

    query = "robust convolutional network with dropout"
    cmd = ["python3", "/home/user/retrieve.py", sample_path, query]

    try:
        expected_output = subprocess.check_output(cmd, text=True).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run retrieve.py to compute expected output: {e}")

    with open(best_match_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Contents of {best_match_path} do not match the expected best match."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
