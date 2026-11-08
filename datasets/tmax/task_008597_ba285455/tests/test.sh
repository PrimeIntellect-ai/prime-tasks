#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/find_cycles.sh"
REPORT_PATH = "/home/user/deadlock_report.log"
INPUT_PATH = "/home/user/iam_edges.tsv"


def test_script_exists_and_executable():
    """Check if the find_cycles.sh script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_report_exists():
    """Check if the deadlock_report.log file was generated."""
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"


def test_report_content():
    """Check if the deadlock_report.log contains the correct length-3 cycles."""
    expected_lines = [
        "auditor-billing-compliance",
        "dev-qa-staging"
    ]

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Report content does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def expected_cycles(edges):
    edge_set = set(edges)
    nodes = sorted({node for edge in edges for node in edge})
    result = []
    for triple in itertools.combinations(nodes, 3):
        if any(
            (a, b) in edge_set and (b, c) in edge_set and (c, a) in edge_set
            for a, b, c in itertools.permutations(triple)
        ):
            result.append("-".join(sorted(triple)))
    return sorted(result)


def run_case(edges):
    with tempfile.TemporaryDirectory(prefix="cycle_test_") as tempdir:
        input_path = os.path.join(tempdir, secrets.token_hex(8) + ".tsv")
        output_path = os.path.join(tempdir, secrets.token_hex(8) + ".log")
        with open(input_path, "w") as f:
            for source, destination in edges:
                f.write(f"{source}\t{destination}\n")
        with open(output_path, "w") as f:
            f.write("stale-output-that-must-be-replaced\n")

        completed = subprocess.run(
            [SCRIPT_PATH, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, (
            f"Script failed with exit code {completed.returncode}.\n"
            f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
        )
        assert os.path.isfile(output_path), "Script did not create the requested output file"

        with open(output_path, "r") as f:
            actual = f.read().splitlines()
        expected = expected_cycles(edges)
        assert actual == expected, f"Expected {expected}, got {actual}"


def test_script_processes_supplied_graphs():
    token = secrets.token_hex(8)
    roles = [f"role_{i:02d}_{token}" for i in range(16)]
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = roles

    edges = [
        (a, b), (b, c), (c, a),
        (d, e), (e, f), (f, d),
        (a, d), (d, g), (g, a),
        (h, i), (i, j),
        (k, l), (l, k),
        (m, m),
        (n, o), (o, p), (p, j), (j, n),
        (a, b),
    ]
    run_case(edges)
    run_case([(a, b), (b, c), (c, d), (d, a), (e, e), (f, g), (g, f)])


def test_script_regenerates_required_report():
    expected_lines = [
        "auditor-billing-compliance",
        "dev-qa-staging"
    ]
    completed = subprocess.run(
        [SCRIPT_PATH, INPUT_PATH, REPORT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, completed.stderr
    with open(REPORT_PATH, "r") as f:
        actual_lines = f.read().splitlines()
    assert actual_lines == expected_lines


def test_script_requires_exactly_two_arguments():
    invocations = [
        [SCRIPT_PATH],
        [SCRIPT_PATH, INPUT_PATH],
        [SCRIPT_PATH, INPUT_PATH, REPORT_PATH, "extra-argument"],
    ]
    for command in invocations:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode != 0, f"Accepted invalid invocation: {command}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
