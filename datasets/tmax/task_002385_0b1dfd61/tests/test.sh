#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import sys
import tempfile


def test_recovered_records_exists_and_correct():
    path = "/home/user/recovered_records.csv"
    assert os.path.exists(path), f"File {path} does not exist. Did you recover it?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = """1,100,200
2,500,600
3,60000,50000
4,-10,20
5,70000,40000"""

    assert content == expected_content, "The recovered records do not match the expected original file contents."


def _check_processor(binary, left, right, expected):
    result = subprocess.run(
        [binary, str(left), str(right)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Processor returned non-zero for {left} * {right}."
    assert result.stdout.strip() == str(expected), (
        f"Processor returned {result.stdout.strip()!r} for {left} * {right}; "
        f"expected {expected}."
    )


def test_processor_compiled_and_correct():
    c_path = "/home/user/processor.c"
    bin_path = "/home/user/processor"

    assert os.path.exists(c_path), f"{c_path} is missing."
    assert os.path.exists(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."

    result = subprocess.run([bin_path, "60000", "50000"], capture_output=True, text=True)
    assert result.returncode == 0, "Processor binary crashed or returned non-zero."
    assert result.stdout.strip() == "3000000000", "Processor did not output the correct 64-bit multiplication result for large inputs."

    result_neg = subprocess.run([bin_path, "-10", "20"], capture_output=True, text=True)
    assert result_neg.returncode == 0, "Processor binary crashed on negative input."
    assert result_neg.stdout.strip() == "-1", "Processor did not output -1 for negative inputs."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "processor")
        compile_result = subprocess.run(
            ["gcc", c_path, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, f"processor.c does not compile: {compile_result.stderr}"

        cases = [(60000, 50000, 3000000000), (-10, 20, -1)]
        for _ in range(12):
            left = 2_147_483_648 + secrets.randbelow(2_000_000_000)
            right = 2 + secrets.randbelow(1_000_000)
            cases.append((left, right, left * right))
        for _ in range(4):
            left = 1 + secrets.randbelow(1_000_000)
            right = 1 + secrets.randbelow(1_000_000)
            cases.append((-left, right, -1))
            cases.append((left, -right, -1))

        for binary in (bin_path, rebuilt):
            for left, right, expected in cases:
                _check_processor(binary, left, right, expected)


def _run_daemon(csv_path, expected):
    daemon_path = "/home/user/daemon.py"
    output_path = "/home/user/final_sum.txt"
    assert os.path.exists(daemon_path), f"{daemon_path} is missing."

    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [sys.executable, daemon_path, csv_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"daemon.py failed for {csv_path}: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.exists(output_path), "daemon.py did not write /home/user/final_sum.txt."
    with open(output_path, "r") as f:
        actual = f.read().strip()
    assert actual == str(expected), f"Expected daemon total {expected}, but got {actual!r}."


def test_daemon_executes_and_handles_dynamic_records():
    rows = []
    expected = 0
    for record_id in range(1, 9):
        base = 2_147_483_648 + secrets.randbelow(1_000_000_000)
        multiplier = 2 + secrets.randbelow(1000)
        if record_id in (3, 6):
            base = -(1 + secrets.randbelow(10000))
        elif record_id == 5:
            multiplier = -(1 + secrets.randbelow(10000))
        else:
            expected += base * multiplier
        rows.append(f"{record_id},{base},{multiplier}\n")

    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        f.writelines(rows)
        dynamic_csv = f.name

    try:
        _run_daemon(dynamic_csv, expected)
    finally:
        os.unlink(dynamic_csv)

    _run_daemon("/home/user/recovered_records.csv", 5800320000)


def test_final_sum_correct():
    path = "/home/user/final_sum.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did daemon.py write the final sum?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "5800320000", f"Expected final sum to be 5800320000, but got {content}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
