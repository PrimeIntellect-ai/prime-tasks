#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import shutil
import secrets
import subprocess
import tempfile
from decimal import Decimal

import pytest

SUMMARY_FILE = "/home/user/experiments/summary.csv"
CPP_SOURCE = "/home/user/experiments/process_logs.cpp"
CPP_BIN = "/home/user/experiments/process_logs"
LOG_DIR = "/home/user/experiments/logs"


def test_summary_file_exists():
    """Check if the summary.csv file was generated."""
    assert os.path.isfile(SUMMARY_FILE), f"The file {SUMMARY_FILE} does not exist. Did the C++ program run successfully?"


def test_summary_csv_content():
    """Validate the contents, sorting, and formatting of summary.csv."""
    assert os.path.isfile(SUMMARY_FILE), "Summary file missing."

    with open(SUMMARY_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "summary.csv is empty."

    header = rows[0]
    expected_header = ["learning_rate", "batch_size", "mean_val_accuracy", "total_training_time", "mean_optimizer"]
    assert header == expected_header, f"Header is incorrect. Expected {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected 4 data rows, got {len(data_rows)}"

    expected_data = [
        (0.05, 128, 0.9000, 435, 0.6666666667),
        (0.01, 64, 0.8800, 105, 1.0000),
        (0.01, 32, 0.8550, 190, 0.5000),
        (0.001, 64, 0.8100, 230, 0.5000),
    ]

    for i, (row, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(row) == 5, f"Row {i+1} does not have 5 columns: {row}"

        lr_str, bs_str, acc_str, time_str, opt_str = row
        exp_lr, exp_bs, exp_acc, exp_time, exp_opt = expected

        assert math.isclose(float(lr_str), exp_lr, rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} learning_rate expected ~{exp_lr}, got {lr_str}"
        assert math.isclose(float(bs_str), exp_bs, rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} batch_size expected ~{exp_bs}, got {bs_str}"
        assert math.isclose(float(acc_str), exp_acc, rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} mean_val_accuracy expected ~{exp_acc}, got {acc_str}"
        assert math.isclose(float(time_str), exp_time, rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} total_training_time expected ~{exp_time}, got {time_str}"
        assert math.isclose(float(opt_str), exp_opt, rel_tol=1e-4, abs_tol=1e-4), f"Row {i+1} mean_optimizer expected ~{exp_opt}, got {opt_str}"

        for val_str, col_name in [(lr_str, "learning_rate"), (acc_str, "mean_val_accuracy"), (opt_str, "mean_optimizer")]:
            if '.' in val_str:
                decimals = len(val_str.split('.')[1])
                assert decimals == 4, f"Column {col_name} in row {i+1} must have exactly 4 decimal places. Got {val_str}"


def test_cpp_files_exist():
    """Check if the C++ source and binary exist."""
    assert os.path.isfile(CPP_SOURCE), f"The C++ source file {CPP_SOURCE} does not exist."
    assert os.path.isfile(CPP_BIN), f"The compiled binary {CPP_BIN} does not exist."
    assert os.access(CPP_BIN, os.X_OK), f"The file {CPP_BIN} is not executable."


def test_program_rebuilds_and_processes_unseen_logs():
    """Rebuild the submitted source and exercise the resulting artifact on unseen inputs."""
    temp_root = tempfile.mkdtemp(prefix="process_logs_verify_")
    logs_backup = os.path.join(temp_root, "logs")
    if os.path.isdir(LOG_DIR):
        shutil.copytree(LOG_DIR, logs_backup)

    summary_existed = os.path.isfile(SUMMARY_FILE)
    summary_backup = os.path.join(temp_root, "summary.csv")
    if summary_existed:
        shutil.copy2(SUMMARY_FILE, summary_backup)

    binary_existed = os.path.isfile(CPP_BIN)
    binary_backup = os.path.join(temp_root, "process_logs")
    if binary_existed:
        shutil.copy2(CPP_BIN, binary_backup)

    try:
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", CPP_SOURCE, "-o", CPP_BIN],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"process_logs.cpp did not compile as C++17:\n{build.stderr}"
        assert os.path.isfile(CPP_BIN) and os.access(CPP_BIN, os.X_OK), "Compilation did not produce an executable process_logs binary."

        if os.path.isdir(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        os.makedirs(LOG_DIR)

        rng = secrets.SystemRandom()
        lr_units = sorted(rng.sample(range(10, 900), 3))
        lr_low = f"{lr_units[0] / 10000:.4f}"
        lr_mid = f"{lr_units[1] / 10000:.4f}"
        lr_high = f"{lr_units[2] / 10000:.4f}"
        base = rng.randrange(7000, 7900)

        def acc(units):
            return f"{units / 10000:.4f}"

        groups = [
            (lr_mid, 32, [base + 1100, base + 1200, base + 1300], ["adam", "sgd", "adam"], [0, 1, 2]),
            (lr_high, 64, [base + 550, base + 650], ["sgd", "adam"], [0, 2]),
            (lr_low, 64, [base + 500, base + 700], ["adam", "adam"], [1, 2]),
            (lr_mid, 128, [base + 50, base + 150], ["sgd", "adam"], [0, 1]),
        ]

        files = [[], [], []]
        all_rows = []
        row_number = 0
        for lr, batch_size, accuracies, optimizers, file_indexes in groups:
            for accuracy, optimizer, file_index in zip(accuracies, optimizers, file_indexes):
                row_number += 1
                training_time = rng.randrange(40, 240)
                row = [
                    f"dynamic_{row_number}_{secrets.token_hex(3)}",
                    lr,
                    str(batch_size),
                    optimizer,
                    acc(accuracy),
                    str(training_time),
                ]
                files[file_index].append(row)
                all_rows.append(row)

        header = ["experiment_id", "learning_rate", "batch_size", "optimizer", "val_accuracy", "training_time"]
        for index, file_rows in enumerate(files):
            with open(os.path.join(LOG_DIR, f"unseen_{index}.csv"), "w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(header)
                writer.writerows(file_rows)

        expected_groups = {}
        for row in all_rows:
            key = (Decimal(row[1]), int(row[2]))
            item = expected_groups.setdefault(key, {"accuracy": Decimal("0"), "time": Decimal("0"), "optimizer": Decimal("0"), "count": 0})
            item["accuracy"] += Decimal(row[4])
            item["time"] += Decimal(row[5])
            item["optimizer"] += Decimal(1 if row[3] == "adam" else 0)
            item["count"] += 1

        expected = []
        for (lr, batch_size), item in expected_groups.items():
            count = Decimal(item["count"])
            expected.append((lr, batch_size, item["accuracy"] / count, item["time"], item["optimizer"] / count))
        expected.sort(key=lambda item: (-item[2], -item[0]))

        if os.path.exists(SUMMARY_FILE):
            os.remove(SUMMARY_FILE)

        run = subprocess.run(
            [CPP_BIN],
            cwd="/home/user/experiments",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert run.returncode == 0, f"process_logs failed on unseen logs (exit {run.returncode}):\n{run.stderr}"
        assert os.path.isfile(SUMMARY_FILE), "Running process_logs did not create summary.csv."

        with open(SUMMARY_FILE, "r", newline="") as f:
            actual_rows = list(csv.reader(f))

        expected_header = ["learning_rate", "batch_size", "mean_val_accuracy", "total_training_time", "mean_optimizer"]
        assert actual_rows and actual_rows[0] == expected_header, f"Header is incorrect on unseen input: {actual_rows[0] if actual_rows else 'missing'}"
        assert len(actual_rows[1:]) == len(expected), f"Expected {len(expected)} aggregate rows on unseen input, got {len(actual_rows[1:])}"

        tolerance = Decimal("0.000051")
        for index, (actual, wanted) in enumerate(zip(actual_rows[1:], expected), 1):
            assert len(actual) == 5, f"Dynamic output row {index} does not have 5 columns: {actual}"
            lr_str, batch_str, accuracy_str, time_str, optimizer_str = actual
            for value, name in [(lr_str, "learning_rate"), (accuracy_str, "mean_val_accuracy"), (optimizer_str, "mean_optimizer")]:
                assert re.fullmatch(r"-?\d+\.\d{4}", value), f"Column {name} in dynamic row {index} must have exactly 4 decimal places. Got {value}"

            exp_lr, exp_batch, exp_accuracy, exp_time, exp_optimizer = wanted
            parsed = [Decimal(lr_str), Decimal(accuracy_str), Decimal(time_str), Decimal(optimizer_str)]
            assert all(value.is_finite() for value in parsed), f"Dynamic output row {index} contains a non-finite number."
            assert int(batch_str) == exp_batch, f"Dynamic row {index} batch_size expected {exp_batch}, got {batch_str}"
            assert abs(parsed[0] - exp_lr) <= tolerance, f"Dynamic row {index} learning_rate expected {exp_lr}, got {lr_str}"
            assert abs(parsed[1] - exp_accuracy) <= tolerance, f"Dynamic row {index} mean_val_accuracy expected {exp_accuracy}, got {accuracy_str}"
            assert abs(parsed[2] - exp_time) <= tolerance, f"Dynamic row {index} total_training_time expected {exp_time}, got {time_str}"
            assert abs(parsed[3] - exp_optimizer) <= tolerance, f"Dynamic row {index} mean_optimizer expected {exp_optimizer}, got {optimizer_str}"
    finally:
        if os.path.isdir(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        if os.path.isdir(logs_backup):
            shutil.copytree(logs_backup, LOG_DIR)
        else:
            os.makedirs(LOG_DIR, exist_ok=True)

        if summary_existed and os.path.isfile(summary_backup):
            shutil.copy2(summary_backup, SUMMARY_FILE)
        elif os.path.exists(SUMMARY_FILE):
            os.remove(SUMMARY_FILE)

        if binary_existed and os.path.isfile(binary_backup):
            shutil.copy2(binary_backup, CPP_BIN)
        elif os.path.exists(CPP_BIN):
            os.remove(CPP_BIN)

        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
