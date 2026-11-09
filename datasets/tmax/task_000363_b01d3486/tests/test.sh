#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import itertools
import subprocess
import pytest

def get_expected_pairs():
    csv_content = """id,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10
A,1,2,-1,0,3,0,0,1,-1,2
B,2,-1,0,1,0,0,0,0,0,0
C,0,0,0,0,0,1,-1,2,0,0
D,-1,-2,1,0,-3,0,0,-1,1,-2
E,0,0,0,0,0,1,1,0,0,0
F,1,,3,4,5,6,7,8,9,0
G,2,4,-2,0,6,0,0,2,-2,4
H,1,1,1,1,1,1,1,1,1,1"""

    rows = csv_content.strip().split('\n')
    reader = csv.reader(rows)
    next(reader) # skip header

    vectors = {}
    for row in reader:
        # Drop rows with missing values
        if any(cell.strip() == '' for cell in row):
            continue
        vectors[row[0]] = [int(x) for x in row[1:]]

    pairs = []
    for (id1, v1), (id2, v2) in itertools.combinations(vectors.items(), 2):
        dot_product = sum(x * y for x, y in zip(v1, v2))
        if dot_product == 0:
            pair = tuple(sorted([id1, id2]))
            pairs.append(pair)

    pairs.sort()
    return [f"{p[0]},{p[1]}" for p in pairs]

def test_virtual_environment_and_dependencies():
    venv_python = "/home/user/venv/bin/python"
    assert os.path.exists(venv_python), f"Virtual environment Python executable not found at {venv_python}"

    try:
        subprocess.run(
            [venv_python, "-c", "import pandas; import numpy"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to import pandas or numpy in the virtual environment. Error: {e.stderr}")

def test_orthogonal_pairs_output():
    output_file = "/home/user/orthogonal_pairs.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]
    expected_lines = get_expected_pairs()

    assert actual_lines == expected_lines, (
        f"Contents of {output_file} do not match the expected orthogonal pairs.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
