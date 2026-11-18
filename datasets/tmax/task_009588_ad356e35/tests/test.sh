#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/prepare_data.sh')
SOURCE_A = Path('/home/user/data/features_a.csv')
SOURCE_B = Path('/home/user/data/features_b.csv')
OUTPUT = Path('/home/user/data/training_set.csv')


def run_script():
    subprocess.run([str(SCRIPT)], cwd='/home/user', check=True, timeout=20)


def test_script_exists_and_executable():
    script_path = '/home/user/prepare_data.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_training_set_exists():
    output_path = '/home/user/data/training_set.csv'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."


def test_script_reproduces_training_set():
    OUTPUT.unlink(missing_ok=True)
    run_script()
    assert OUTPUT.is_file(), f"Script did not create {OUTPUT}."


def test_training_set_content():
    output_path = '/home/user/data/training_set.csv'

    expected_lines = [
        "id,f1,f2,y",
        "4,10,1,89",
        "5,7,0,35",
        "2,5,5,26",
        "3,2,8,14",
        "1,4,2,8"
    ]

    with open(output_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {output_path} is incorrect. Expected {expected_lines}, got {actual_lines}"


def test_script_performs_pipeline_on_new_inputs():
    rng = random.SystemRandom()
    ids = rng.sample(range(100, 1000), 8)

    pairs = [(rng.randint(4, 14), rng.randint(0, 9)) for _ in range(3)]
    tie_pair = (rng.randint(5, 12), rng.randint(0, 5))
    joined = [
        (ids[0], *pairs[0]),
        (ids[1], *pairs[1]),
        (ids[2], *pairs[2]),
        (ids[3], 1, 0),
        (ids[4], *tie_pair),
        (ids[5], *tie_pair),
    ]

    rows_a = [(record[0], record[1]) for record in joined] + [(ids[6], 99)]
    rows_b = [(record[0], record[2]) for record in joined] + [(ids[7], 99)]
    rng.shuffle(rows_a)
    rng.shuffle(rows_b)

    old_a = SOURCE_A.read_bytes()
    old_b = SOURCE_B.read_bytes()
    old_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        with SOURCE_A.open('w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'f1'])
            writer.writerows(rows_a)
        with SOURCE_B.open('w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'f2'])
            writer.writerows(rows_b)

        with SOURCE_A.open(newline='') as f:
            a_values = {int(row['id']): int(row['f1']) for row in csv.DictReader(f)}
        with SOURCE_B.open(newline='') as f:
            b_values = {int(row['id']): int(row['f2']) for row in csv.DictReader(f)}

        expected_rows = []
        for user_id in a_values.keys() & b_values.keys():
            f1 = a_values[user_id]
            f2 = b_values[user_id]
            y = f1 ** 2 + 3 * f2 - 14
            if y > 0:
                expected_rows.append((user_id, f1, f2, y))
        expected_rows.sort(key=lambda row: (-row[3], row[0]))
        expected_lines = ['id,f1,f2,y'] + [','.join(map(str, row)) for row in expected_rows]

        OUTPUT.unlink(missing_ok=True)
        run_script()
        assert OUTPUT.is_file(), 'Script did not create the output for changed source data.'
        with OUTPUT.open() as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert actual_lines == expected_lines, (
            f"Script did not correctly process changed source data. "
            f"Expected {expected_lines}, got {actual_lines}"
        )
    finally:
        SOURCE_A.write_bytes(old_a)
        SOURCE_B.write_bytes(old_b)
        if old_output is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.write_bytes(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
