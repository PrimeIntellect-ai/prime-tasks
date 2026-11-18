#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile
import pytest

AGENT_PATH = "/app/libcsv-graph/in_degree"
NUM_FUZZ_CASES = 50


def generate_fuzz_case(seed):
    random.seed(seed)
    num_edges = random.randint(10, 500)
    csv_lines = []
    for _ in range(num_edges):
        source = random.randint(1, 100)
        target = random.randint(1, 100)
        weight = random.randint(1, 50)
        csv_lines.append(f"{source},{target},{weight}")

    threshold = random.randint(0, 100)
    limit = random.randint(1, 20)
    offset = random.randint(0, 20)
    return "\n".join(csv_lines) + "\n", threshold, limit, offset


def expected_output(csv_content, threshold, limit, offset):
    degrees = {}
    for line in csv_content.splitlines():
        _source, target, weight = map(int, line.split(","))
        if 0 <= target < 100000:
            degrees[target] = degrees.get(target, 0) + weight

    nodes = [
        (target, degree)
        for target, degree in degrees.items()
        if degree >= threshold
    ]
    nodes.sort(key=lambda item: (-item[1], item[0]))
    page = nodes[offset:offset + limit]
    return "".join(
        f"Node: {target}, In-Degree: {degree}\n"
        for target, degree in page
    )


def run_program(executable, csv_path, threshold, limit, offset):
    cmd = [executable, csv_path, str(threshold), str(limit), str(offset)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout, result.stderr, result.returncode


def test_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Executable not found at {AGENT_PATH}. Did you run 'make'?"
    assert os.access(AGENT_PATH, os.X_OK), f"File at {AGENT_PATH} is not executable."


def test_fuzz_equivalence():
    for i in range(NUM_FUZZ_CASES):
        csv_content, threshold, limit, offset = generate_fuzz_case(i + 1000)
        expected_stdout = expected_output(csv_content, threshold, limit, offset)

        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv") as tmp:
            tmp.write(csv_content)
            tmp_path = tmp.name

        try:
            agent_stdout, agent_stderr, agent_rc = run_program(
                AGENT_PATH, tmp_path, threshold, limit, offset
            )
            error_msg = (
                f"Mismatch on fuzz case {i} (seed {i+1000}):\n"
                f"Threshold: {threshold}, Limit: {limit}, Offset: {offset}\n"
                f"Input CSV:\n{csv_content[:200]}...\n\n"
                f"Expected Output:\n{expected_stdout}\n"
                f"Agent Output:\n{agent_stdout}\n"
            )

            assert agent_rc == 0, f"Return code mismatch. Expected: 0, Agent: {agent_rc}\n{error_msg}"
            assert agent_stdout == expected_stdout, f"Output mismatch.\n{error_msg}"
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
