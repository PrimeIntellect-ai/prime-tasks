#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/research_data.db"
JSON_PATH = "/home/user/summary_results.json"
GO_PATH = "/home/user/organize_data.go"
BIN_PATH = "/tmp/organize_data_test_bin"
VALID_ARMS = ("Arm A", "Arm B", "Placebo")


def expected_results(min_age, condition):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            SELECT t.treatment_arm, AVG(o.recovery_days)
            FROM patient_records p
            JOIN trial_assignments t ON p.p_id = t.fk_patient
            JOIN observation_metrics o ON t.t_id = o.fk_trial
            WHERE p.patient_age >= ?
              AND p.primary_condition = ?
              AND t.treatment_arm IN ('Arm A', 'Arm B', 'Placebo')
            GROUP BY t.treatment_arm
            ORDER BY t.treatment_arm ASC
            """,
            (min_age, condition),
        ).fetchall()
    finally:
        conn.close()

    result = []
    for arm, avg_days in rows:
        if arm not in VALID_ARMS or avg_days is None:
            continue
        if not math.isfinite(avg_days) or avg_days < 0:
            continue
        result.append({
            "treatment_arm": arm,
            "avg_recovery_days": round(avg_days, 2),
        })
    return result


def read_and_check_output(expected):
    assert os.path.exists(JSON_PATH), f"Output file missing at {JSON_PATH}"
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file"
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(data, list), "JSON output must be a list of objects"
    assert len(data) == len(expected), f"Expected {len(expected)} records, got {len(data)}"

    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Record {i} must be an object"
        assert set(actual.keys()) == {"treatment_arm", "avg_recovery_days"}, \
            f"Record {i} must contain exactly treatment_arm and avg_recovery_days"
        assert isinstance(actual["treatment_arm"], str), \
            f"Record {i} treatment_arm must be a string"
        assert actual["treatment_arm"] == wanted["treatment_arm"], \
            f"Record {i} expected treatment_arm {wanted['treatment_arm']!r}, got {actual['treatment_arm']!r}"
        value = actual["avg_recovery_days"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Record {i} avg_recovery_days must be a number"
        assert math.isfinite(value) and value >= 0, \
            f"Record {i} avg_recovery_days must be a finite nonnegative number"
        assert abs(value - wanted["avg_recovery_days"]) < 0.01, \
            f"Record {i} for {actual['treatment_arm']} expected {wanted['avg_recovery_days']}, got {value}"


def run_program(*args):
    try:
        os.remove(JSON_PATH)
    except FileNotFoundError:
        pass
    proc = subprocess.run(
        [BIN_PATH, *args],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, \
        f"Program failed for arguments {args}:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(JSON_PATH), "Program did not create summary_results.json"


def install_controlled_fixture():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM observation_metrics")
        conn.execute("DELETE FROM trial_assignments")
        conn.execute("DELETE FROM patient_records")

        patients = [
            (1, 30, "Asthma"),
            (2, 45, "Asthma"),
            (3, 55, "Asthma"),
            (4, 20, "Asthma"),
            (5, 60, "Diabetes"),
            (6, 70, "Asthma"),
            (7, 70, "Asthma"),
            (8, 70, "Asthma"),
            (9, 40, "NegativeCase"),
            (10, 40, "NegativeCase"),
            (11, 40, "NegativeCase"),
            (12, 40, "Overflow"),
            (13, 40, "Overflow"),
        ]
        assignments = [
            (101, 1, "Arm A"),
            (102, 2, "Arm A"),
            (103, 3, "Arm B"),
            (104, 4, "Arm A"),
            (105, 5, "Arm B"),
            (106, 6, "Placebo"),
            (107, 7, "Arm C"),
            (108, 8, "UNKNOWN"),
            (109, 9, "Arm A"),
            (110, 10, "Arm B"),
            (111, 11, "Placebo"),
            (112, 12, "Arm A"),
            (113, 13, "Arm A"),
        ]
        observations = [
            (1001, 101, 10.0),
            (1002, 102, 14.0),
            (1003, 103, 8.0),
            (1004, 104, 100.0),
            (1005, 105, 50.0),
            (1006, 106, 20.0),
            (1007, 107, 3.0),
            (1008, 108, 2.0),
            (1009, 109, -5.0),
            (1010, 110, 4.0),
            (1011, 111, None),
            (1012, 112, 1e308),
            (1013, 113, 1e308),
        ]
        conn.executemany(
            "INSERT INTO patient_records (p_id, patient_age, primary_condition) VALUES (?, ?, ?)",
            patients,
        )
        conn.executemany(
            "INSERT INTO trial_assignments (t_id, fk_patient, treatment_arm) VALUES (?, ?, ?)",
            assignments,
        )
        conn.executemany(
            "INSERT INTO observation_metrics (o_id, fk_trial, recovery_days) VALUES (?, ?, ?)",
            observations,
        )
        conn.commit()
    finally:
        conn.close()


def test_go_program_and_generated_results():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file"
    assert os.path.exists(GO_PATH), f"Go source missing at {GO_PATH}"
    assert os.path.isfile(GO_PATH), f"{GO_PATH} is not a regular file"
    assert not os.path.islink(GO_PATH), f"{GO_PATH} must be an actual Go source file"

    with open(GO_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "Go source file is empty"
    assert "min-age" in source and "condition" in source, \
        "Go program must define both min-age and condition flags"

    # Require SQL bind markers and a query call that supplies arguments. Behavioral
    # injection testing below additionally verifies that condition is treated exactly.
    named_markers = re.findall(r"(?:[:@][A-Za-z_]\w*|\$[A-Za-z_]\w*|\$\d+)", source)
    assert source.count("?") >= 2 or len(named_markers) >= 2, \
        "SQL query must contain parameter placeholders for both filters"
    query_calls = re.findall(
        r"\.(?:Query|QueryContext|QueryRow|QueryRowContext)\s*\((.{0,1500}?)\)",
        source,
        flags=re.DOTALL,
    )
    assert any(call.count(",") >= 1 for call in query_calls), \
        "SQL query must be executed with bound parameter arguments"

    for arm in VALID_ARMS:
        assert arm in source, f"Validation code must recognize {arm!r}"
    assert re.search(r"(?:>=\s*0(?:\.0)?|<\s*0(?:\.0)?)", source), \
        "Go code must validate that aggregate values are nonnegative"

    build = subprocess.run(
        ["go", "build", "-o", BIN_PATH, GO_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, \
        f"organize_data.go does not compile:\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"

    fd, backup_path = tempfile.mkstemp(prefix="research_data_backup_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        # Preserve and exercise the originally required invocation and assertions.
        run_program("--min-age", "30", "--condition", "Asthma")
        read_and_check_output(expected_results(30, "Asthma"))

        # Use controlled data so a prewritten output cannot satisfy the verifier.
        install_controlled_fixture()
        cases = [
            (["--min-age", "30", "--condition", "Asthma"], 30, "Asthma"),
            (["--min-age=40", "--condition=Asthma"], 40, "Asthma"),
            (["--min-age", "0", "--condition", "Diabetes"], 0, "Diabetes"),
            (["--min-age", "0", "--condition", "Asthma' OR 1=1 --"], 0, "Asthma' OR 1=1 --"),
            (["--min-age", "0", "--condition", "NegativeCase"], 0, "NegativeCase"),
            (["--min-age", "0", "--condition", "Overflow"], 0, "Overflow"),
        ]
        for args, min_age, condition in cases:
            run_program(*args)
            read_and_check_output(expected_results(min_age, condition))
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        # Leave the required final output generated against the original database.
        if os.path.isfile(BIN_PATH):
            subprocess.run(
                [BIN_PATH, "--min-age", "30", "--condition", "Asthma"],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
