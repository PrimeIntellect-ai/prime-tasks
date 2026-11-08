#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import sqlite3
import subprocess
from decimal import Decimal, ROUND_HALF_UP

ROOT = "/home/user/ticket_8492"


def test_final_report_exists_and_correct():
    report_path = os.path.join(ROOT, "final_report.txt")
    assert os.path.isfile(report_path), f"File {report_path} does not exist. Did you run report.sh and redirect output to it?"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_results = {}
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 3, f"Invalid format in final_report.txt: {line}"
        user_id = int(parts[0])
        avg_amt = float(parts[1])
        variance = float(parts[2])
        parsed_results[user_id] = (avg_amt, variance)

    assert 1 in parsed_results, "User 1 is missing from final_report.txt"
    assert math.isclose(parsed_results[1][0], 1000000.02, rel_tol=1e-9), f"User 1 avg_amount incorrect: {parsed_results[1][0]}"
    assert math.isclose(parsed_results[1][1], 0.0001, rel_tol=1e-3, abs_tol=1e-4), f"User 1 variance incorrect in report: {parsed_results[1][1]}"
    # The original tolerance admitted zero; require the correctly rounded value too.
    assert abs(parsed_results[1][1] - 0.0001) < 1e-8, f"User 1 variance was not correctly rounded: {parsed_results[1][1]}"

    assert 3 in parsed_results, "User 3 is missing from final_report.txt"
    assert math.isclose(parsed_results[3][0], 150.0, rel_tol=1e-9), f"User 3 avg_amount incorrect: {parsed_results[3][0]}"
    assert math.isclose(parsed_results[3][1], 0.0, abs_tol=1e-4), f"User 3 variance incorrect in report: {parsed_results[3][1]}"

    assert 2 not in parsed_results, "User 2 should not be in final_report.txt (avg_amount <= 100)"


def test_database_state():
    db_path = os.path.join(ROOT, "summary.db")
    assert os.path.isfile(db_path), f"Database {db_path} does not exist. Did you run process.sh?"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT user_id, avg_amount, variance FROM user_stats ORDER BY user_id")
    rows = cursor.fetchall()

    assert len(rows) == 3, f"Expected 3 users in the database, found {len(rows)}"
    user_dict = {row[0]: (row[1], row[2]) for row in rows}

    assert 1 in user_dict, "User 1 missing from database"
    assert math.isclose(user_dict[1][0], 1000000.02, rel_tol=1e-9), f"User 1 DB avg_amount incorrect: {user_dict[1][0]}"
    assert math.isclose(user_dict[1][1], 0.00006666666666666667, rel_tol=1e-2, abs_tol=1e-4), f"User 1 DB variance incorrect: {user_dict[1][1]}"
    # Reject the zero variance accepted by the old absolute tolerance.
    assert math.isclose(user_dict[1][1], 0.00006666666666666667, rel_tol=1e-3, abs_tol=1e-8), f"User 1 DB variance lacks required precision: {user_dict[1][1]}"

    assert 2 in user_dict, "User 2 missing from database"
    assert math.isclose(user_dict[2][0], 53.0, rel_tol=1e-9), f"User 2 DB avg_amount incorrect: {user_dict[2][0]}"
    assert math.isclose(user_dict[2][1], 6.25, rel_tol=1e-5), f"User 2 DB variance incorrect: {user_dict[2][1]}"

    assert 3 in user_dict, "User 3 missing from database"
    assert math.isclose(user_dict[3][0], 150.0, rel_tol=1e-9), f"User 3 DB avg_amount incorrect: {user_dict[3][0]}"
    assert math.isclose(user_dict[3][1], 0.0, abs_tol=1e-9), f"User 3 DB variance incorrect: {user_dict[3][1]}"
    conn.close()


def _population_stats(values):
    vals = [Decimal(v) for v in values]
    mean = sum(vals) / Decimal(len(vals))
    variance = sum((v - mean) ** 2 for v in vals) / Decimal(len(vals))
    return mean, variance


def test_scripts_are_executable_and_work_on_unseen_data():
    process_path = os.path.join(ROOT, "process.sh")
    report_path = os.path.join(ROOT, "report.sh")
    for path in (process_path, report_path):
        assert os.path.isfile(path), f"Required script missing: {path}"
        assert os.access(path, os.X_OK), f"Required script is not executable: {path}"
        syntax = subprocess.run(["bash", "-n", path], text=True, capture_output=True)
        assert syntax.returncode == 0, f"Shell syntax error in {path}: {syntax.stderr}"

    # Runtime-randomized IDs and baseline prevent a precomputed database/report
    # for the setup fixture from satisfying this test.
    ids = []
    while len(ids) < 4:
        candidate = 1000 + secrets.randbelow(800000)
        if candidate not in ids:
            ids.append(candidate)
    unstable_id, low_id, high_id, boundary_id = ids
    baseline = 100000000 + secrets.randbelow(800000000)

    groups = {
        unstable_id: [f"{baseline}.01", f"{baseline}.02", f"{baseline}.03"],
        low_id: ["40.25", "60.75"],
        high_id: ["125.10", "125.30", "125.50"],
        boundary_id: ["99.99", "100.01"],
    }
    expected = {uid: _population_stats(values) for uid, values in groups.items()}

    data_path = os.path.join(ROOT, "data.csv")
    db_path = os.path.join(ROOT, "summary.db")
    final_path = os.path.join(ROOT, "final_report.txt")
    backups = {}
    for path in (data_path, db_path, final_path):
        if os.path.exists(path):
            backup = path + ".verifier_backup"
            shutil.copy2(path, backup)
            backups[path] = backup

    try:
        with open(data_path, "w") as f:
            f.write("user_id,amount\n")
            # Interleave users so processing must genuinely group the CSV rows.
            max_len = max(len(v) for v in groups.values())
            for i in range(max_len):
                for uid, values in groups.items():
                    if i < len(values):
                        f.write(f"{uid},{values[i]}\n")

        proc = subprocess.run([process_path], cwd=ROOT, text=True, capture_output=True, timeout=20)
        assert proc.returncode == 0, f"process.sh failed on unseen data:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        assert os.path.isfile(db_path), "process.sh did not create summary.db"

        conn = sqlite3.connect(db_path)
        schema = conn.execute("PRAGMA table_info(user_stats)").fetchall()
        assert [(r[1], r[2], r[5]) for r in schema] == [
            ("user_id", "INTEGER", 1),
            ("count", "INTEGER", 0),
            ("avg_amount", "REAL", 0),
            ("variance", "REAL", 0),
        ], f"The user_stats schema was changed: {schema}"
        rows = conn.execute("SELECT user_id, avg_amount, variance FROM user_stats").fetchall()
        conn.close()
        assert len(rows) == len(groups), f"Expected {len(groups)} dynamically generated users, got {len(rows)}"
        actual = {int(uid): (float(avg), float(var)) for uid, avg, var in rows}
        assert set(actual) == set(groups), f"Database user IDs are incorrect: {set(actual)}"
        for uid, (mean, variance) in expected.items():
            got_mean, got_variance = actual[uid]
            assert math.isclose(got_mean, float(mean), rel_tol=1e-12, abs_tol=1e-7), f"Incorrect mean for dynamic user {uid}: {got_mean}"
            assert got_variance >= 0, f"Negative variance for dynamic user {uid}: {got_variance}"
            assert math.isclose(got_variance, float(variance), rel_tol=1e-3, abs_tol=1e-8), f"Numerically unstable variance for dynamic user {uid}: got {got_variance}, expected {variance}"

        report = subprocess.run([report_path], cwd=ROOT, text=True, capture_output=True, timeout=20)
        assert report.returncode == 0, f"report.sh failed on unseen data:\nstdout: {report.stdout}\nstderr: {report.stderr}"
        lines = [line.strip() for line in report.stdout.splitlines() if line.strip()]
        parsed = {}
        for line in lines:
            parts = line.split(',')
            assert len(parts) == 3, f"Invalid report row: {line}"
            uid = int(parts[0])
            assert uid not in parsed, f"Duplicate report row for user {uid}"
            parsed[uid] = (float(parts[1]), float(parts[2]))

        expected_ids = {uid for uid, (mean, _) in expected.items() if mean > Decimal("100.0")}
        assert set(parsed) == expected_ids, f"report.sh did not apply avg_amount > 100.0: got {set(parsed)}, expected {expected_ids}"
        for uid in expected_ids:
            mean, variance = expected[uid]
            rounded_mean = mean.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
            rounded_variance = variance.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
            assert math.isclose(parsed[uid][0], float(rounded_mean), abs_tol=1e-8), f"Incorrect reported average for user {uid}"
            assert math.isclose(parsed[uid][1], float(rounded_variance), abs_tol=1e-8), f"Incorrect rounded variance for user {uid}"
    finally:
        for path in (data_path, db_path, final_path):
            backup = backups.get(path)
            if backup and os.path.exists(backup):
                os.replace(backup, path)
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
