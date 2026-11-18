#!/bin/bash
set -e
mkdir -p /logs/verifier

# The oracle is uploaded only at verification time. Keep it inaccessible to the
# unprivileged account used to execute the submitted script.
chmod 700 /tests/reference_checksum_calc

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import random
import subprocess
import pytest


def test_recovered_records_exist_and_valid():
    path = "/home/user/recovered_records.txt"
    assert os.path.isfile(path), f"File {path} does not exist. You must extract valid records."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, "Recovered records file is empty."

    # Valid record format: [TIMESTAMP] (ID) DATA_VALUE
    valid_record_pattern = re.compile(r"^\[\d+\] \(\d+\) -?\d+$")
    for line in lines:
        assert valid_record_pattern.match(line), (
            f"Invalid or corrupted record found in recovered_records.txt: '{line}'"
        )

    # Require recovery of the complete set of valid records, in WAL order,
    # rather than accepting one fabricated, plausibly formatted record.
    expected = [
        "[1623423400] (1) 10",
        "[1623423401] (2) 20",
        "[1623423402] (3) 30",
        "[1623423403] (4) 40",
        "[1623423404] (5) 50",
        "[1623423423] (12) 0",
    ]
    expected.extend(f"[16234234{i}] ({i}) {i}" for i in range(14, 61))
    assert lines == expected, "recovered_records.txt does not contain exactly all valid WAL records in order."


def test_robust_checksum_fuzz_equivalence():
    agent_script = "/home/user/robust_checksum.sh"
    oracle_bin = "/tests/reference_checksum_calc"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} does not exist."

    random.seed(42)
    fuzz_inputs = [random.randint(0, 1000000) for _ in range(1000)]

    for val in fuzz_inputs:
        val_str = str(val)

        oracle_proc = subprocess.run(
            [oracle_bin, val_str],
            capture_output=True,
            text=True,
        )
        assert oracle_proc.returncode == 0, f"Oracle binary failed on input {val_str}"
        oracle_out = oracle_proc.stdout.strip()

        # Execute the submission as the unprivileged agent account so it cannot
        # delegate computation to the root-only verification oracle.
        agent_proc = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", agent_script, val_str],
            capture_output=True,
            text=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on input {val_str}. Stderr: {agent_proc.stderr.strip()}"
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on input {val_str}.\n"
            f"Oracle expected: '{oracle_out}'\n"
            f"Agent produced : '{agent_out}'"
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Standard output was not bit-exact on input {val_str}."
        )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF
chmod 600 /tmp/test_final_state.py

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
