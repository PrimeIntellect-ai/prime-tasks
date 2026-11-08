#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import secrets
import shutil
import subprocess


def test_clean_data_exists():
    """Test that the clean data file exists."""
    file_path = "/home/user/clean_data.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing. The C++ program did not produce the expected output file."
    assert os.path.isfile(file_path), f"{file_path} should be a file."


def test_clean_data_content():
    """Test that the clean data file contains the correct processed data."""
    file_path = "/home/user/clean_data.csv"
    expected_content = """record_id,masked_email,quarter,score
101,a***@company.com,Q1,85
101,a***@company.com,Q2,92
101,a***@company.com,Q3,95
101,a***@company.com,Q4,100
102,b***@domain.org,Q1,70
102,b***@domain.org,Q3,80
103,c***@startup.io,Q1,50
103,c***@startup.io,Q3,60
103,c***@startup.io,Q4,70
104,d***@enterprise.net,Q4,100
"""
    with open(file_path, "r") as f:
        content = f.read()

    actual_lines = [line.strip() for line in content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]
    assert actual_lines == expected_lines, (
        f"Content of {file_path} does not match expected clean data.\n"
        f"Expected:\n{expected_content}\nActual:\n{content}"
    )


def _expected_output(rows):
    latest = {}
    for row in rows:
        rid = int(row[0])
        timestamp = int(row[6])
        if rid not in latest or timestamp > int(latest[rid][6]):
            latest[rid] = row

    output = [["record_id", "masked_email", "quarter", "score"]]
    for rid in sorted(latest):
        row = latest[rid]
        local, domain = row[1].split("@", 1)
        masked = local[0] + "***@" + domain
        for index, quarter in enumerate(("Q1", "Q2", "Q3", "Q4"), start=2):
            score = row[index]
            if score == "":
                continue
            numeric_score = float(score)
            if 0 <= numeric_score <= 100:
                output.append([str(rid), masked, quarter, score])
    return output


def test_cpp_program_compiles_and_processes_fresh_input():
    source = "/home/user/process.cpp"
    raw_path = "/home/user/raw_data.csv"
    clean_path = "/home/user/clean_data.csv"
    binary = "/tmp/submitted_process"

    assert os.path.exists(source), f"Required source file {source} is missing."
    assert os.path.isfile(source), f"{source} must be a regular file."
    assert os.path.getsize(source) > 0, f"{source} is empty."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "process.cpp did not compile successfully.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    original_raw = open(raw_path, "rb").read()
    original_clean = open(clean_path, "rb").read()

    ids = random.SystemRandom().sample(range(2000, 9000), 3)
    token = secrets.token_hex(5)
    rows = [
        [str(ids[0]), "newalpha" + token + "@latest.example", "0", "100", "-7", "101", "900"],
        [str(ids[1]), "oldbeta" + token + "@old.example", "12", "13", "14", "15", "300"],
        [str(ids[2]), "gamma" + token + "@third.example", "88", "", "99", "1", "500"],
        [str(ids[0]), "oldalpha" + token + "@old.example", "21", "22", "23", "24", "100"],
        [str(ids[1]), "newbeta" + token + "@current.example", "", "40", "55", "", "700"],
    ]
    random.SystemRandom().shuffle(rows)

    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["record_id", "email", "Q1_score", "Q2_score", "Q3_score", "Q4_score", "timestamp"])
    writer.writerows(rows)

    try:
        with open(raw_path, "w", newline="") as f:
            f.write(buffer.getvalue())
        if os.path.lexists(clean_path):
            os.remove(clean_path)

        run_result = subprocess.run(
            [binary],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "The compiled program failed on a fresh input fixture.\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )
        assert os.path.isfile(clean_path), "The compiled program did not create clean_data.csv."

        with open(clean_path, newline="") as f:
            actual = list(csv.reader(f))
        expected = _expected_output(rows)
        assert actual == expected, (
            "The compiled program produced incorrect output for a fresh, randomized fixture.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        with open(clean_path, "wb") as f:
            f.write(original_clean)
        if os.path.exists(binary):
            os.remove(binary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
