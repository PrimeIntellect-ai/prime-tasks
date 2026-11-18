#!/bin/bash
set -e
mkdir -p /logs/verifier

# Keep the uploaded oracle private from the unprivileged agent account while it is used.
chmod 700 /tests/oracle_audit

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_audit_query_fuzz_equivalence():
    student_binary = "/home/user/audit_query/target/release/audit_query"
    oracle_binary = "/tests/oracle_audit"

    assert os.path.exists(student_binary), f"Student binary not found at {student_binary}"
    assert os.access(student_binary, os.X_OK), f"Student binary at {student_binary} is not executable"

    assert os.path.exists(oracle_binary), f"Oracle binary not found at {oracle_binary}"
    assert os.access(oracle_binary, os.X_OK), f"Oracle binary at {oracle_binary} is not executable"

    random.seed(42)
    num_iterations = 50
    max_frames = 1000
    cases = []

    # Compute all expected answers before running the submission, then remove the
    # oracle so the submitted executable cannot delegate its work to it.
    for i in range(num_iterations):
        start_frame = random.randint(0, max_frames - 1)
        end_frame = random.randint(start_frame, max_frames - 1)
        args = [str(start_frame), str(end_frame)]

        try:
            oracle_proc = subprocess.run(
                [oracle_binary] + args,
                capture_output=True,
                text=True,
                timeout=10
            )
            oracle_out = oracle_proc.stdout.strip()
        except Exception as e:
            pytest.fail(f"Oracle program failed on input: {start_frame} {end_frame}. Error: {e}")

        assert oracle_proc.returncode == 0, f"Oracle program exited with non-zero code {oracle_proc.returncode} on input: {start_frame} {end_frame}"
        cases.append((start_frame, end_frame, oracle_out))

    os.remove(oracle_binary)

    for start_frame, end_frame, oracle_out in cases:
        args = [str(start_frame), str(end_frame)]

        try:
            student_proc = subprocess.run(
                [student_binary] + args,
                capture_output=True,
                text=True,
                timeout=10
            )
            student_out = student_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Student program timed out on input: {start_frame} {end_frame}")
        except Exception as e:
            pytest.fail(f"Student program failed to run on input: {start_frame} {end_frame}. Error: {e}")

        assert student_proc.returncode == 0, f"Student program exited with non-zero code {student_proc.returncode} on input: {start_frame} {end_frame}\nStderr: {student_proc.stderr}"

        assert student_out == oracle_out, (
            f"Mismatch on input: start_frame={start_frame}, end_frame={end_frame}\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Student output: '{student_out}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
