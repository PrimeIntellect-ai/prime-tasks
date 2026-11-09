#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_student_program_exists_and_executable():
    student_path = "/home/user/query_engine"
    assert os.path.isfile(student_path), f"Student program {student_path} is missing."
    assert os.access(student_path, os.X_OK), f"Student program {student_path} is not executable."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_query_engine"
    student_path = "/home/user/query_engine"
    video_path = "/app/experiment.mp4"

    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} is missing."
    assert os.path.isfile(student_path), f"Student program {student_path} is missing."

    random.seed(42)
    entity_classes = ["cell", "bacteria", "virus", "protein"]

    for i in range(30):
        frame_number = random.randint(0, 100)
        entity_class = random.choice(entity_classes)

        args = [video_path, str(frame_number), entity_class]

        oracle_cmd = [oracle_path] + args
        student_cmd = [student_path] + args

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True, timeout=10)
            oracle_output = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            oracle_output = f"ORACLE ERROR: {e.stderr.strip()}"
        except subprocess.TimeoutExpired:
            oracle_output = "ORACLE TIMEOUT"

        try:
            student_res = subprocess.run(student_cmd, capture_output=True, text=True, check=True, timeout=10)
            student_output = student_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            student_output = f"STUDENT ERROR: {e.stderr.strip()}"
        except subprocess.TimeoutExpired:
            student_output = "STUDENT TIMEOUT"

        assert student_output == oracle_output, (
            f"Output mismatch on input: frame_number={frame_number}, entity_class={entity_class}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Student): {student_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
