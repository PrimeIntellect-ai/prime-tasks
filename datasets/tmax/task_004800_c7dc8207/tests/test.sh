#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import csv
import random
import string
import subprocess
from datetime import datetime, timedelta
import io

def generate_csv_data(num_rows):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['timestamp', 'sensor_id', 'temperature', 'status_log'])

    start_dt = datetime(2024, 1, 1)

    for _ in range(num_rows):
        offset = random.randint(0, 86400)
        dt = start_dt + timedelta(seconds=offset)
        timestamp = dt.isoformat() + "Z"

        letters = ''.join(random.choices(string.ascii_uppercase, k=3))
        numbers = ''.join(random.choices(string.digits, k=2))
        sensor_id = f"{letters}-{numbers}"

        temp = round(random.uniform(-10.0, 40.0), 2)

        length = random.randint(10, 50)
        chars = random.choices(string.ascii_letters + string.digits + " ", k=length)
        if random.random() < 0.2:
            insert_pos = random.randint(1, length - 2)
            chars[insert_pos] = '\n'
        status_log = ''.join(chars)

        writer.writerow([timestamp, sensor_id, temp, status_log])

    return output.getvalue()

def test_pipeline_fuzz_equivalence():
    student_script = "/home/user/pipeline.py"
    oracle_script = "/tests/pipeline_oracle.py"

    assert os.path.isfile(student_script), f"Student script not found at {student_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    N = 500
    for i in range(N):
        num_rows = random.randint(50, 500)
        csv_data = generate_csv_data(num_rows)

        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=csv_data,
            text=True,
            capture_output=True,
            check=False
        )

        student_proc = subprocess.run(
            [sys.executable, student_script],
            input=csv_data,
            text=True,
            capture_output=True,
            check=False
        )

        assert student_proc.returncode == 0, f"Student script failed with error:\n{student_proc.stderr}\nInput CSV:\n{csv_data}"

        oracle_out = oracle_proc.stdout.strip()
        student_out = student_proc.stdout.strip()

        if oracle_out != student_out:
            assert student_out == oracle_out, f"Mismatch on fuzz iteration {i+1}.\nInput CSV:\n{csv_data}\n\nExpected Output:\n{oracle_out}\n\nActual Output:\n{student_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
