#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = '/home/user/process_data.py'
RESULTS_PATH = '/home/user/results.json'
DB_PATH = '/home/user/research.db'
READINGS_PATH = '/home/user/readings.jsonl'


def run_script():
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"Expected {SCRIPT_PATH} to be a regular file."

    if os.path.lexists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), f"Expected output file {RESULTS_PATH} does not exist."


def load_and_check_results(expected_data):
    with open(RESULTS_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array (list)."

    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be an object (dictionary)."
        assert set(item.keys()) == {"participant_id", "avg_heart_rate"}, "Each object must have exactly 'participant_id' and 'avg_heart_rate' keys."
        assert isinstance(item["participant_id"], str), "'participant_id' must be a string."
        assert isinstance(item["avg_heart_rate"], (int, float)), "'avg_heart_rate' must be a number."

    participant_ids = [item["participant_id"] for item in data]
    assert participant_ids == sorted(participant_ids), "The array must be sorted alphabetically by 'participant_id'."

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} participant records, found {len(data)}."

    for item in data:
        pid = item["participant_id"]
        assert pid in expected_data, f"Unexpected participant_id '{pid}' in results."
        expected_hr = expected_data[pid]
        actual_hr = item["avg_heart_rate"]
        assert round(actual_hr, 2) == actual_hr, f"avg_heart_rate for {pid} is not rounded to 2 decimal places."
        assert abs(actual_hr - expected_hr) < 0.001, f"Expected avg_heart_rate for {pid} to be {expected_hr}, got {actual_hr}."


def test_script_executes_and_processes_inputs():
    # First execute the submitted artifact against the supplied datasets and retain
    # all checks made by the original verifier.
    run_script()
    load_and_check_results({"P001": 72.5, "P004": 70.0})

    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, 'research.db')
        readings_backup = os.path.join(backup_dir, 'readings.jsonl')
        shutil.copy2(DB_PATH, db_backup)
        shutil.copy2(READINGS_PATH, readings_backup)

        try:
            token = secrets.token_hex(6).upper()
            p1 = 'A_' + token
            p2 = 'Z_' + token
            treatment = 'TREAT_' + token
            fed_only = 'FED_' + token

            t1 = 'F1_' + token
            t2 = 'F2_' + token
            t3 = 'F3_' + token
            fed_trial = 'FD_' + token
            treatment_trial = 'TR_' + token
            fed_only_trial = 'FO_' + token

            rates1 = [51 + secrets.randbelow(20), 80 + secrets.randbelow(15), 63 + secrets.randbelow(12)]
            rates2 = [58 + secrets.randbelow(18), 91 + secrets.randbelow(8)]

            os.unlink(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            try:
                conn.execute('CREATE TABLE participants (participant_id TEXT PRIMARY KEY, age INTEGER, cohort TEXT)')
                conn.execute('CREATE TABLE trials (trial_id TEXT PRIMARY KEY, participant_id TEXT, condition TEXT)')
                conn.executemany('INSERT INTO participants VALUES (?, ?, ?)', [
                    (p1, 31, 'control'),
                    (p2, 42, 'control'),
                    (treatment, 27, 'treatment'),
                    (fed_only, 36, 'control'),
                ])
                conn.executemany('INSERT INTO trials VALUES (?, ?, ?)', [
                    (t1, p1, 'fasting'),
                    (t2, p1, 'fasting'),
                    (fed_trial, p1, 'fed'),
                    (t3, p2, 'fasting'),
                    (treatment_trial, treatment, 'fasting'),
                    (fed_only_trial, fed_only, 'fed'),
                ])
                conn.commit()
            finally:
                conn.close()

            readings = [
                {"trial_id": t1, "timestamp": "08:00", "sensor_data": {"heart_rate": rates1[0], "bp": 111}},
                {"trial_id": t1, "timestamp": "08:05", "sensor_data": {"heart_rate": rates1[1], "bp": 112}},
                {"trial_id": t2, "timestamp": "09:00", "sensor_data": {"heart_rate": rates1[2], "bp": 113}},
                {"trial_id": t3, "timestamp": "10:00", "sensor_data": {"heart_rate": rates2[0], "bp": 114}},
                {"trial_id": t3, "timestamp": "10:05", "sensor_data": {"heart_rate": rates2[1], "bp": 115}},
                {"trial_id": fed_trial, "timestamp": "12:00", "sensor_data": {"heart_rate": 199, "bp": 116}},
                {"trial_id": treatment_trial, "timestamp": "07:00", "sensor_data": {"heart_rate": 188, "bp": 117}},
                {"trial_id": fed_only_trial, "timestamp": "13:00", "sensor_data": {"heart_rate": 177, "bp": 118}},
                {"trial_id": 'UNKNOWN_' + token, "timestamp": "14:00", "sensor_data": {"heart_rate": 166, "bp": 119}},
            ]
            secrets.SystemRandom().shuffle(readings)
            with open(READINGS_PATH, 'w') as f:
                for reading in readings:
                    f.write(json.dumps(reading) + '\n')

            expected = {
                p1: round(sum(rates1) / len(rates1), 2),
                p2: round(sum(rates2) / len(rates2), 2),
            }
            run_script()
            load_and_check_results(expected)
        finally:
            shutil.copy2(db_backup, DB_PATH)
            shutil.copy2(readings_backup, READINGS_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
