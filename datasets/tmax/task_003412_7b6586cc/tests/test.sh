#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
EXE = os.path.join(HOME, "log_analyzer")


def get_expected_results(log_path):
    expected = []
    with open(log_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 4:
                ip = parts[0]
                status = int(parts[2])
                bytes_val = int(parts[3])

                score = 1.0
                epsilon = 0.001
                iterations = 0

                while True:
                    old_score = score
                    score = (score + (bytes_val / float(status + 1))) / 2.0
                    diff = abs(score - old_score)
                    if diff <= epsilon or iterations >= 100:
                        break
                    iterations += 1

                expected.append(f"IP: {ip}, Score: {score:.3f}")
    return expected


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_executable_exists():
    exe_path = "/home/user/log_analyzer"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} is missing. Did you run make?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def test_source_rebuilds_to_compiled_executable():
    completed = subprocess.run(
        ["make", "-B"], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert completed.returncode == 0, f"Rebuilding with the provided Makefile failed:\n{completed.stdout}"
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK)
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_analyzer is not a compiled ELF executable."


def test_executable_on_derived_mixed_date_inputs(tmp_path):
    nonce = secrets.token_hex(6)
    input_path = tmp_path / f"mixed-{nonce}.log"
    output_path = tmp_path / f"mixed-{nonce}.txt"

    records = []
    for i in range(12):
        status = 100 + secrets.randbelow(500)
        # Include decreasing-score cases, which expose a missing absolute value.
        if i in (0, 2):
            bytes_val = 0
        else:
            bytes_val = 17 + secrets.randbelow(8000)
        year = 1995 + secrets.randbelow(30)
        month_num = 1 + secrets.randbelow(12)
        day = 1 + secrets.randbelow(28)
        if i % 2 == 0:
            months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            date = f"{day:02d}/{months[month_num - 1]}/{year}"
        else:
            date = f"{year}-{month_num:02d}-{day:02d}"
        ip = f"10.{i}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"
        records.append((ip, date, status, bytes_val))

    with open(input_path, "w") as f:
        for record in records:
            f.write("%s %s %d %d\n" % record)

    expected_lines = get_expected_results(input_path)
    completed = subprocess.run(
        [EXE, str(input_path), str(output_path)], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert completed.returncode == 0, (
        f"log_analyzer failed on mixed date formats. stdout={completed.stdout!r}, "
        f"stderr={completed.stderr!r}"
    )
    assert output_path.is_file(), "The executable did not create its requested output file."
    assert read_nonempty_lines(output_path) == expected_lines


def test_results_txt_exists_and_correct():
    results_path = "/home/user/results.txt"
    log_path = "/home/user/server.log"

    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    # Generate the required artifact with the rebuilt executable, rather than
    # trusting a manually written results file.
    completed = subprocess.run(
        [EXE, log_path, results_path], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert completed.returncode == 0, (
        f"log_analyzer failed on server.log. stdout={completed.stdout!r}, "
        f"stderr={completed.stderr!r}"
    )
    assert os.path.isfile(results_path), f"Output file {results_path} was not generated."

    expected_lines = get_expected_results(log_path)
    actual_lines = read_nonempty_lines(results_path)

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {results_path}, but found {len(actual_lines)}. "
        "Make sure the date parsing handles both formats correctly."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} in {results_path} is incorrect.\n"
            f"Expected: '{expected}'\n"
            f"Actual:   '{actual}'\n"
            "Check your convergence logic and date parsing."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
