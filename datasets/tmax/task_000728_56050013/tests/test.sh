#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/seq_splitter.py"
REGRESSION_LOG = "/home/user/regression_log.txt"


def expected_output(seq):
    boundaries = []

    def split_domain(start, end):
        if end - start < 10:
            return

        mid = start + (end - start) // 2
        left = seq[start:mid]
        right = seq[mid:end]

        l1_distance = 0.0
        for nucleotide in "ACGT":
            left_probability = left.count(nucleotide) / len(left)
            right_probability = right.count(nucleotide) / len(right)
            l1_distance += abs(left_probability - right_probability)

        if l1_distance > 0.40:
            split_domain(start, mid)
            boundaries.append(mid)
            split_domain(mid, end)

    split_domain(0, len(seq))
    boundaries.sort()
    return ",".join(str(value) for value in boundaries) + "\n"


def run_agent(seq):
    result = subprocess.run(
        ["python3", AGENT_SCRIPT, seq],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        pytest.fail(
            f"Agent script failed on input of length {len(seq)}.\n"
            f"Input: {seq}\nStderr: {result.stderr}"
        )
    return result.stdout


def test_required_artifacts():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert stat.S_ISREG(os.lstat(AGENT_SCRIPT).st_mode), "Agent script must be a regular file."

    assert os.path.isfile(REGRESSION_LOG), f"Regression log {REGRESSION_LOG} does not exist."
    assert stat.S_ISREG(os.lstat(REGRESSION_LOG).st_mode), "Regression log must be a regular file."
    with open(REGRESSION_LOG, "r", encoding="utf-8") as handle:
        log_contents = handle.read()
    assert log_contents.strip(), "Regression log is empty."
    assert re.search(r"[ACGT]+", log_contents), "Regression log does not contain a DNA input."


def test_crafted_equivalence():
    cases = [
        "A",
        "ACGTACGTA",
        "A" * 10,
        "A" * 5 + "C" * 5,
        "A" * 10 + "A" * 8 + "C" * 2,
        "A" * 10 + "A" * 7 + "C" * 3,
        "A" * 20 + "C" * 20,
        "A" * 16 + "C" * 16 + "G" * 16 + "T" * 16,
        "ACGT" * 31 + "A",
        "A" * 25 + "CGTAC" + "T" * 26,
    ]

    for seq in cases:
        assert run_agent(seq) == expected_output(seq), f"Output mismatch for crafted input {seq!r}"


def test_fuzz_equivalence():
    random.seed(42)
    chars = ["A", "C", "G", "T"]
    n = 200

    for _ in range(n):
        length = random.randint(20, 500)
        seq = "".join(random.choices(chars, k=length))
        oracle_out = expected_output(seq)
        agent_out = run_agent(seq)

        assert agent_out == oracle_out, (
            f"Output mismatch on input of length {length}.\n"
            f"Input: {seq}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output:  {agent_out!r}"
        )
TEST_EOF

# The oracle was available during the task for reverse engineering, but must not
# remain callable while the submitted implementation is being evaluated.
if rm -f /app/seq_domain_splitter && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
