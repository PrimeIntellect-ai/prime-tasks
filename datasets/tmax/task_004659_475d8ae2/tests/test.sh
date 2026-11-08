#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SOURCE = "/home/user/evaluate_experiments.c"
REPORT = "/home/user/report.csv"
PARAMS = "/home/user/params.csv"
METRICS = "/home/user/metrics.csv"
BINARY = "/tmp/evaluate_experiments_test"


def normalized_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def test_c_source_file_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} was not created."


def test_report_csv_exists_and_correct():
    assert os.path.isfile(REPORT), f"Output file {REPORT} was not generated."

    expected_content = """exp_id,status
1,Success
2,Invalid
3,Failure
4,Invalid
5,Success
6,Invalid
7,Failure"""

    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
    assert normalized_lines(REPORT) == expected_lines, \
        f"Content of {REPORT} does not match the expected output."


def classify(record):
    exp_id, learning_rate, epochs, initial_loss, final_loss = record
    if learning_rate <= 0 or epochs < 1 or initial_loss < 0 or final_loss < 0:
        return exp_id, "Invalid"
    predicted_loss = initial_loss / epochs
    return exp_id, "Success" if final_loss < predicted_loss else "Failure"


def write_inputs(records, rng):
    params_rows = [(r[0], r[1], r[2], r[3]) for r in records]
    metrics_rows = [(r[0], r[4]) for r in records]
    rng.shuffle(params_rows)
    rng.shuffle(metrics_rows)

    with open(PARAMS, "w") as f:
        f.write("exp_id,learning_rate,epochs,initial_loss\n")
        for row in params_rows:
            f.write(",".join(str(value) for value in row) + "\n")

    with open(METRICS, "w") as f:
        f.write("exp_id,final_loss\n")
        for row in metrics_rows:
            f.write(",".join(str(value) for value in row) + "\n")


def test_source_compiles_and_processes_changed_inputs():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", BINARY, "-lm"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        f"C source did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    rng = random.SystemRandom()
    for _ in range(2):
        ids = rng.sample(range(100, 10000), 7)
        records = [
            (ids[0], 0.01, 10, 5.0, 0.2),   # Success
            (ids[1], 0.02, 4, 8.0, 2.0),    # Failure: equality
            (ids[2], 0.03, 2, 3.0, 2.0),    # Failure
            (ids[3], 0.0, 5, 2.0, 0.1),     # Invalid learning rate
            (ids[4], 0.1, 0, 2.0, 0.1),     # Invalid epochs
            (ids[5], 0.1, 5, -0.5, 0.1),    # Invalid initial loss
            (ids[6], 0.1, 5, 2.0, -0.2),    # Invalid final loss
        ]
        write_inputs(records, rng)

        if os.path.lexists(REPORT):
            os.unlink(REPORT)

        run_result = subprocess.run(
            [BINARY],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert run_result.returncode == 0, \
            f"Compiled program failed:\n{run_result.stderr}"
        assert os.path.isfile(REPORT), f"Program did not generate {REPORT}."

        expected = ["exp_id,status"]
        expected.extend(
            f"{exp_id},{status}"
            for exp_id, status in sorted(classify(r) for r in records)
        )
        assert normalized_lines(REPORT) == expected, \
            "Program produced an incorrect report for changed input files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
