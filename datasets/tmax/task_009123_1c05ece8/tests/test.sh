#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest


def test_c_program_builds_runs_and_produces_correct_log():
    source_path = "/home/user/train.c"
    binary_path = "/tmp/submission_train"
    log_path = "/home/user/experiment_log.json"
    expected_path = "/tests/.expected_log.json"

    assert os.path.isfile(source_path), f"File {source_path} is missing."
    assert os.path.getsize(source_path) > 0, f"File {source_path} is empty."
    assert os.path.isfile(expected_path), f"Ground truth file {expected_path} is missing."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source_path, "-lm", "-o", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, (
        "The C program did not compile successfully:\n" + compile_result.stderr
    )

    if os.path.exists(log_path):
        os.remove(log_path)

    try:
        run_result = subprocess.run(
            [binary_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The compiled C program did not finish within 30 seconds.")

    assert run_result.returncode == 0, (
        "The compiled C program exited unsuccessfully:\n" + run_result.stderr
    )
    assert os.path.isfile(log_path), (
        f"File {log_path} is missing. The C program did not output the experiment log."
    )

    with open(log_path, "r") as f:
        try:
            student_log = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {log_path} is not a valid JSON file.")

    with open(expected_path, "r") as f:
        expected_log = json.load(f)

    assert "best_epsilon" in student_log, "Key 'best_epsilon' is missing from the experiment log."
    assert "best_accuracy" in student_log, "Key 'best_accuracy' is missing from the experiment log."

    student_eps = float(student_log["best_epsilon"])
    student_acc = float(student_log["best_accuracy"])
    expected_eps = float(expected_log["best_epsilon"])
    expected_acc = float(expected_log["best_accuracy"])

    assert f"{student_eps:.2f}" == f"{expected_eps:.2f}", (
        f"Expected best_epsilon {expected_eps:.2f}, but got {student_eps:.2f}."
    )
    assert f"{student_acc:.2f}" == f"{expected_acc:.2f}", (
        f"Expected best_accuracy {expected_acc:.2f}, but got {student_acc:.2f}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
