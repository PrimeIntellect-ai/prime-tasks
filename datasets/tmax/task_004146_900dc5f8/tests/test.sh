#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import shutil
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/model_trainer"
SCRIPT = "/home/user/run_experiments.sh"
CSV_FILE = "/home/user/experiments.csv"
SOURCE = "/home/user/train_model.cpp"
EXPECTED_LRS = ["0.01", "0.05", "0.1"]


def expected_loss(lr):
    return 100.0 / (1.0 + lr * 100.5)


def run_checked(command, timeout=15):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def read_loss_from_program(path, lr):
    completed = run_checked([path, str(lr)])
    matches = re.findall(
        r"FINAL_LOSS\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
        completed.stdout,
    )
    assert matches, f"{path} did not output a FINAL_LOSS metric for LR {lr}. Output: {completed.stdout!r}"
    value = float(matches[-1])
    assert math.isfinite(value), f"Non-finite loss returned for LR {lr}: {value}"
    return value


def read_csv_exact(path):
    assert os.path.isfile(path), f"{path} does not exist."
    rows = []
    with open(path, newline="") as handle:
        for row in csv.reader(handle):
            assert row, "Blank rows are not allowed in experiments.csv"
            assert len(row) == 2, f"Expected exactly 2 columns in CSV, got {len(row)}: {row}"
            try:
                lr = float(row[0])
                loss = float(row[1])
            except ValueError:
                pytest.fail(f"Could not parse row as floats: {row}")
            assert math.isfinite(lr) and math.isfinite(loss), f"CSV contains non-finite values: {row}"
            rows.append((row[0], lr, loss))
    return rows


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "model_trainer must be a compiled executable."


def test_bash_script_exists():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_experiments_csv_contents():
    rows = read_csv_exact(CSV_FILE)
    results = {round(lr, 3): loss for _, lr, loss in rows}
    for lr in map(float, EXPECTED_LRS):
        key = round(lr, 3)
        assert key in results, f"Learning rate {lr} not found in {CSV_FILE}"
        expected = expected_loss(lr)
        actual = results[key]
        assert abs(actual - expected) < 0.01, f"Loss for LR {lr} is {actual}, expected ~{expected:.4f}. Precision might be lost."
        truncated = float(int(expected))
        assert abs(actual - truncated) > 0.01, f"Loss for LR {lr} appears truncated to {truncated}."


def test_fixed_source_and_compiled_artifacts_preserve_precision():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    source_text = open(SOURCE).read()
    assert not re.search(r"\b(?:signed\s+)?int\s+final_loss\b", source_text), \
        "train_model.cpp still declares final_loss as an int."

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "rebuilt_model_trainer")
        run_checked(["g++", "-std=c++11", SOURCE, "-o", rebuilt], timeout=30)
        for lr in (0.0137, 0.0823, 0.1579):
            expected = expected_loss(lr)
            rebuilt_loss = read_loss_from_program(rebuilt, lr)
            submitted_loss = read_loss_from_program(EXECUTABLE, lr)
            assert abs(rebuilt_loss - expected) <= 0.00011, \
                f"Program rebuilt from train_model.cpp returned {rebuilt_loss}, expected {expected:.4f} for LR {lr}."
            assert abs(submitted_loss - expected) <= 0.00011, \
                f"Submitted model_trainer returned {submitted_loss}, expected {expected:.4f} for LR {lr}."
            assert abs(rebuilt_loss - float(int(expected))) > 0.01
            assert abs(submitted_loss - float(int(expected))) > 0.01


def test_tracker_invokes_model_trainer_with_exact_rates_and_captures_output():
    backup = EXECUTABLE + ".verifier_backup"
    log_path = "/tmp/model_trainer_probe_calls.jsonl"
    markers = {"0.01": 901.2345, "0.05": 905.6789, "0.1": 910.4321}

    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(EXECUTABLE, backup)
    try:
        probe = '''#!/usr/bin/env python3
import json
import sys
with open("/tmp/model_trainer_probe_calls.jsonl", "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
values = {"0.01": "901.2345", "0.05": "905.6789", "0.1": "910.4321"}
if len(sys.argv) != 2 or sys.argv[1] not in values:
    sys.exit(23)
print("Training complete.")
print("FINAL_LOSS=" + values[sys.argv[1]])
'''
        with open(EXECUTABLE, "w") as handle:
            handle.write(probe)
        os.chmod(EXECUTABLE, 0o755)
        for path in (log_path, CSV_FILE):
            if os.path.exists(path):
                os.unlink(path)

        run_checked([SCRIPT], timeout=15)

        assert os.path.isfile(log_path), "run_experiments.sh never invoked /home/user/model_trainer."
        with open(log_path) as handle:
            calls = [json.loads(line) for line in handle if line.strip()]
        assert calls == [[lr] for lr in EXPECTED_LRS], \
            f"model_trainer must be called once with each exact LR, in order, and no extra arguments; got {calls}."

        rows = read_csv_exact(CSV_FILE)
        assert len(rows) == 3, f"Expected exactly three CSV rows, got {len(rows)}."
        assert [raw_lr for raw_lr, _, _ in rows] == EXPECTED_LRS, \
            f"CSV learning rates must be exactly {EXPECTED_LRS}, got {[r[0] for r in rows]}."
        for raw_lr, _, loss in rows:
            assert abs(loss - markers[raw_lr]) < 0.00001, \
                "run_experiments.sh did not capture the loss produced by model_trainer."
    finally:
        if os.path.lexists(EXECUTABLE):
            os.unlink(EXECUTABLE)
        os.replace(backup, EXECUTABLE)
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_running_real_tracker_generates_final_csv():
    if os.path.exists(CSV_FILE):
        os.unlink(CSV_FILE)
    run_checked([SCRIPT], timeout=15)
    rows = read_csv_exact(CSV_FILE)
    assert len(rows) == 3, f"Expected exactly three CSV rows, got {len(rows)}."
    assert [raw_lr for raw_lr, _, _ in rows] == EXPECTED_LRS, \
        f"CSV learning rates must be exactly {EXPECTED_LRS}, got {[r[0] for r in rows]}."
    for raw_lr, lr, loss in rows:
        expected = expected_loss(lr)
        assert abs(loss - expected) < 0.01, f"Loss for LR {raw_lr} is {loss}, expected ~{expected:.4f}."
        assert abs(loss - float(int(expected))) > 0.01, f"Loss for LR {raw_lr} is truncated."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
