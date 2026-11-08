#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
RAW_PATH = "/home/user/raw_data.csv"
CORR_PATH = "/home/user/correlation.txt"
CLEAN_PATH = "/home/user/clean_data.csv"

ORIGINAL_DATA = """id,f1,f2,f3,label
1,2.5,5.1,10.0,0
2,3.0,5.9,8.0,1
3,3.5,7.2,6.0,0
4,4.0,8.0,4.0,1
5,4.5,9.1,2.0,0
"""


def run_pipeline(data):
    with open(RAW_PATH, "w", newline="") as f:
        f.write(data)

    for path in (CORR_PATH, CLEAN_PATH):
        if os.path.lexists(path):
            assert os.path.isfile(path) or os.path.islink(path), f"{path} is not a file"
            os.remove(path)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"pipeline.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CORR_PATH), f"File {CORR_PATH} was not generated."
    assert os.path.isfile(CLEAN_PATH), f"File {CLEAN_PATH} was not generated."


def expected_outputs(data):
    rows = list(csv.DictReader(data.splitlines()))
    f1 = [float(row["f1"]) for row in rows]
    f2 = [float(row["f2"]) for row in rows]
    f3 = [float(row["f3"]) for row in rows]

    mean1 = sum(f1) / len(f1)
    mean2 = sum(f2) / len(f2)
    mean3 = sum(f3) / len(f3)
    numerator = sum((a - mean1) * (b - mean2) for a, b in zip(f1, f2))
    denominator = math.sqrt(
        sum((a - mean1) ** 2 for a in f1)
        * sum((b - mean2) ** 2 for b in f2)
    )
    correlation = numerator / denominator

    drop_f2 = correlation >= 0.85
    output = ["id,f1,f3,label" if drop_f2 else "id,f1,f2,f3,label"]
    for row, a, b, c in zip(rows, f1, f2, f3):
        if drop_f2:
            output.append(f'{row["id"]},{a - mean1:.3f},{c - mean3:.3f},{row["label"]}')
        else:
            output.append(
                f'{row["id"]},{a - mean1:.3f},{b:.3f},{c - mean3:.3f},{row["label"]}'
            )
    return f"{correlation:.3f}", "\n".join(output)


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_pipeline_script_no_python():
    script_path = "/home/user/pipeline.sh"
    with open(script_path, 'r') as f:
        content = f.read().lower()

    assert "python" not in content, "The script must not use Python."
    assert "perl" not in content, "The script must not use Perl."
    assert "ruby" not in content, "The script must not use Ruby."


def test_correlation_txt():
    run_pipeline(ORIGINAL_DATA)
    corr_path = "/home/user/correlation.txt"
    assert os.path.exists(corr_path), f"File {corr_path} is missing."

    with open(corr_path, 'r') as f:
        content = f.read().strip()

    assert content == "0.998", f"Expected correlation to be '0.998', but got '{content}'"


def test_clean_data_csv():
    run_pipeline(ORIGINAL_DATA)
    clean_data_path = "/home/user/clean_data.csv"
    assert os.path.exists(clean_data_path), f"File {clean_data_path} is missing."

    expected_content = """id,f1,f3,label
1,-1.000,4.000,0
2,-0.500,2.000,1
3,0.000,0.000,0
4,0.500,-2.000,1
5,1.000,-4.000,0"""

    with open(clean_data_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, "The contents of clean_data.csv do not match the expected output."


def test_pipeline_recomputes_outputs_for_new_inputs():
    shift1 = secrets.randbelow(101) + 20
    shift2 = secrets.randbelow(101) + 200
    shift3 = secrets.randbelow(101) - 50
    ids = [secrets.randbelow(1000) + 1001 + i * 1000 for i in range(4)]

    high_rows = []
    for i, delta in enumerate((-3, -1, 1, 3)):
        a = shift1 + delta
        b = 2 * a + shift2
        c = shift3 + (-6, -2, 2, 6)[i]
        high_rows.append(f"{ids[i]},{a}.0,{b}.0,{c}.0,{i % 2}")
    high_data = "id,f1,f2,f3,label\n" + "\n".join(high_rows) + "\n"

    low_rows = []
    f2_offsets = (1, -1, -1, 1)
    for i, delta in enumerate((-3, -1, 1, 3)):
        a = shift1 + delta
        b = shift2 + f2_offsets[i]
        c = shift3 + (6, 2, -2, -6)[i]
        low_rows.append(f"{ids[i]},{a}.0,{b}.0,{c}.0,{(i + 1) % 2}")
    low_data = "id,f1,f2,f3,label\n" + "\n".join(low_rows) + "\n"

    try:
        for data in (high_data, low_data):
            expected_corr, expected_clean = expected_outputs(data)
            run_pipeline(data)
            with open(CORR_PATH) as f:
                actual_corr = f.read().strip()
            with open(CLEAN_PATH) as f:
                actual_clean = f.read().strip()
            assert actual_corr == expected_corr
            assert actual_clean == expected_clean
    finally:
        run_pipeline(ORIGINAL_DATA)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
