#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import math
import csv
import re
import secrets
import shutil
import subprocess
import tempfile
import pytest

PIPELINE_DIR = "/home/user/pipeline"
DB_PATH = os.path.join(PIPELINE_DIR, "data.db")
ETL_PATH = os.path.join(PIPELINE_DIR, "etl.go")
GO_MOD = os.path.join(PIPELINE_DIR, "go.mod")
TRAIN_CSV = os.path.join(PIPELINE_DIR, "train_clean.csv")
TEST_CSV = os.path.join(PIPELINE_DIR, "test_clean.csv")


def expected_from_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, f1, f2, is_train FROM measurements ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    train_f1 = [r[1] for r in rows if r[3] == 1]
    train_f2 = [r[2] for r in rows if r[3] == 1]
    assert len(train_f1) >= 2 and len(train_f2) >= 2

    mean_f1 = sum(train_f1) / len(train_f1)
    mean_f2 = sum(train_f2) / len(train_f2)
    std_f1 = math.sqrt(sum((x - mean_f1) ** 2 for x in train_f1) / (len(train_f1) - 1))
    std_f2 = math.sqrt(sum((x - mean_f2) ** 2 for x in train_f2) / (len(train_f2) - 1))

    expected_train = []
    expected_test = []
    for id_val, f1_val, f2_val, is_train in rows:
        row = {
            "id": str(id_val),
            "f1": f"{(f1_val - mean_f1) / std_f1:.4f}",
            "f2": f"{(f2_val - mean_f2) / std_f2:.4f}",
        }
        (expected_train if is_train == 1 else expected_test).append(row)
    return expected_train, expected_test


def read_csv(filepath):
    with open(filepath, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "f1", "f2"], f"Incorrect header in {filepath}: {reader.fieldnames}"
        return list(reader)


def assert_csv_contents():
    expected_train, expected_test = expected_from_db()
    actual_train = read_csv(TRAIN_CSV)
    actual_test = read_csv(TEST_CSV)

    assert len(actual_train) == len(expected_train), f"Expected {len(expected_train)} rows in {TRAIN_CSV}, got {len(actual_train)}"
    assert len(actual_test) == len(expected_test), f"Expected {len(expected_test)} rows in {TEST_CSV}, got {len(actual_test)}"

    for i, (actual, expected) in enumerate(zip(actual_train, expected_train)):
        assert actual == expected, f"Row {i+1} in {TRAIN_CSV} mismatch. Expected {expected}, got {actual}. Data leakage might still be present."

    for i, (actual, expected) in enumerate(zip(actual_test, expected_test)):
        assert actual == expected, f"Row {i+1} in {TEST_CSV} mismatch. Expected {expected}, got {actual}. Data leakage might still be present."


def run_etl():
    for path in (TRAIN_CSV, TEST_CSV):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ["go", "run", "etl.go"],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Go ETL program failed:\n{result.stdout}"
    assert os.path.isfile(TRAIN_CSV), f"Running etl.go did not create {TRAIN_CSV}"
    assert os.path.isfile(TEST_CSV), f"Running etl.go did not create {TEST_CSV}"


def test_csv_files_exist():
    assert os.path.isfile(TRAIN_CSV), f"Expected output file {TRAIN_CSV} is missing. Did the program run?"
    assert os.path.isfile(TEST_CSV), f"Expected output file {TEST_CSV} is missing. Did the program run?"


def test_csv_contents():
    assert_csv_contents()


def test_go_source_and_module_exist():
    assert os.path.isfile(ETL_PATH), f"Expected Go source file {ETL_PATH} is missing"
    assert os.path.isfile(GO_MOD), f"Expected Go module file {GO_MOD} is missing"
    with open(GO_MOD, "r", encoding="utf-8") as f:
        go_mod = f.read()
    assert re.search(r"(?m)^\s*module\s+\S+", go_mod), "go.mod does not declare a module"
    result = subprocess.run(
        ["go", "list", "-m"], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"Invalid Go module:\n{result.stdout}"


def test_running_go_program_regenerates_correct_outputs():
    run_etl()
    assert_csv_contents()


def test_go_program_on_unseen_database():
    with tempfile.TemporaryDirectory() as tmp:
        db_backup = os.path.join(tmp, "data.db")
        train_backup = os.path.join(tmp, "train_clean.csv")
        test_backup = os.path.join(tmp, "test_clean.csv")
        shutil.copy2(DB_PATH, db_backup)
        shutil.copy2(TRAIN_CSV, train_backup)
        shutil.copy2(TEST_CSV, test_backup)

        try:
            os.remove(DB_PATH)
            rng = secrets.SystemRandom()
            id_base = rng.randrange(1000, 9000)
            train_positions = set(rng.sample(range(8), 5))
            f1_values = rng.sample(range(-500, 700), 8)
            f2_values = rng.sample(range(1000, 9000), 8)

            conn = sqlite3.connect(DB_PATH)
            conn.execute("CREATE TABLE measurements (id INTEGER, f1 REAL, f2 REAL, is_train INTEGER)")
            for i in range(8):
                conn.execute(
                    "INSERT INTO measurements VALUES (?, ?, ?, ?)",
                    (id_base + i, float(f1_values[i]), float(f2_values[i]), 1 if i in train_positions else 0),
                )
            conn.commit()
            conn.close()

            run_etl()
            assert_csv_contents()
        finally:
            shutil.copy2(db_backup, DB_PATH)
            shutil.copy2(train_backup, TRAIN_CSV)
            shutil.copy2(test_backup, TEST_CSV)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
