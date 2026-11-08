#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import subprocess
from collections import defaultdict

import pytest

DB_PATH = "/home/user/compliance.db"
CSV_PATH = "/home/user/filtered_tx.csv"
C_FILE_PATH = "/home/user/graph_audit.c"
VIOLATIONS_PATH = "/home/user/violations.txt"
EXECUTABLE_PATH = "/tmp/graph_audit_submission"


def compute_expected_anomalous(db_path):
    """Compute the expected anomalous transaction IDs and complete rows."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT tx_id, src_account, dst_account, amount, timestamp "
        "FROM transactions ORDER BY src_account, timestamp"
    )
    rows = cursor.fetchall()
    conn.close()

    history = defaultdict(list)
    anomalous = {}
    for row in rows:
        tx_id, src, dst, amt, ts = row
        hist = history[src]
        if len(hist) == 0:
            avg = 0.0
        elif len(hist) == 1:
            avg = hist[0]
        else:
            avg = (hist[-1] + hist[-2]) / 2.0

        if amt > avg:
            anomalous[tx_id] = (tx_id, src, dst, float(amt), ts)
        hist.append(amt)

    return anomalous


def read_filtered_csv(path):
    rows = []
    with open(path, newline="") as f:
        reader = csv.reader(f)
        for line_no, row in enumerate(reader, 1):
            if not row:
                continue
            assert len(row) == 5, (
                f"CSV row {line_no} must contain exactly five fields "
                f"(tx_id,src_account,dst_account,amount,timestamp), got {row}"
            )
            try:
                parsed = (int(row[0]), int(row[1]), int(row[2]), float(row[3]), int(row[4]))
            except ValueError:
                pytest.fail(f"Invalid value in CSV row {line_no}: {row}")
            rows.append(parsed)
    return rows


def expected_cycles(rows):
    """Derive required cycle lines directly from a filtered transaction set."""
    outgoing = defaultdict(list)
    for row in rows:
        outgoing[row[1]].append(row)

    cycles = set()
    for first in rows:
        _, a, b, _, t1 = first
        for second in outgoing.get(b, []):
            _, _, c, _, t2 = second
            if len({a, b, c}) != 3:
                continue
            for third in outgoing.get(c, []):
                _, _, destination, _, t3 = third
                if destination != a or max(t1, t2, t3) - min(t1, t2, t3) > 86400:
                    continue

                edges = [(a, b, t1), (b, c, t2), (c, a, t3)]
                earliest = min(edges, key=lambda edge: edge[2])
                start = earliest[0]
                if start == a:
                    cycle = (a, b, c)
                elif start == b:
                    cycle = (b, c, a)
                else:
                    cycle = (c, a, b)
                cycles.add(cycle)

    return [f"{a},{b},{c}" for a, b, c in sorted(cycles)]


def read_violation_lines():
    assert os.path.isfile(VIOLATIONS_PATH), f"Violations output not found at {VIOLATIONS_PATH}"
    with open(VIOLATIONS_PATH) as f:
        return [line.strip() for line in f if line.strip()]


def run_program(rows=None):
    if rows is not None:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerows(rows)

    if os.path.exists(VIOLATIONS_PATH):
        os.remove(VIOLATIONS_PATH)
    result = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled graph_audit program exited with {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    return read_violation_lines()


def test_filtered_tx_csv_exists_and_correct():
    """Verify every anomalous CSV row, including all five required values."""
    assert os.path.isfile(CSV_PATH), f"CSV file not found at {CSV_PATH}"

    expected = compute_expected_anomalous(DB_PATH)
    actual_rows = read_filtered_csv(CSV_PATH)
    actual_ids = [row[0] for row in actual_rows]
    actual_id_set = set(actual_ids)
    expected_id_set = set(expected)

    missing = expected_id_set - actual_id_set
    extra = actual_id_set - expected_id_set
    assert not missing, f"Missing anomalous transactions in CSV: {missing}"
    assert not extra, f"Extra non-anomalous transactions in CSV: {extra}"
    assert len(actual_ids) == len(actual_id_set), "Duplicate transaction IDs found in CSV"

    for row in actual_rows:
        assert row == expected[row[0]], (
            f"Incorrect fields for transaction {row[0]}: expected {expected[row[0]]}, got {row}"
        )


def test_c_program_exists_and_compiles():
    """Verify that graph_audit.c is a compilable C program."""
    assert os.path.isfile(C_FILE_PATH), f"C program not found at {C_FILE_PATH}"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"graph_audit.c failed to compile: {result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH), "Compilation did not create an executable"


def test_violations_output_from_program():
    """Run the submitted program on the agent's CSV and verify all derived cycles."""
    rows = read_filtered_csv(CSV_PATH)
    expected = expected_cycles(rows)
    actual = run_program()
    assert actual == expected, f"Expected violations {expected}, found {actual}"


def test_program_handles_derived_inputs():
    """Exercise the compiled artifact on unpredictable graph inputs."""
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_violations = None
    if os.path.exists(VIOLATIONS_PATH):
        with open(VIOLATIONS_PATH, "rb") as f:
            original_violations = f.read()

    try:
        chosen = set()
        while len(chosen) < 15:
            chosen.add(1000 + secrets.randbelow(900000))
        ids = list(chosen)
        base = 100000 + secrets.randbelow(1000000)

        # First ensure a program cannot pass by always printing a fixed cycle.
        no_cycle_rows = [
            (1, ids[0], ids[1], 1.25, base),
            (2, ids[1], ids[2], 2.50, base + 10),
            (3, ids[3], ids[4], 3.75, base + 20),
        ]
        assert run_program(no_cycle_rows) == expected_cycles(no_cycle_rows)

        # Two valid cycles (including the exact 86400-second boundary), one
        # over-time cycle, and unrelated edges. Earliest edges use different
        # rotations so output cannot simply be normalized by smallest ID.
        rows = [
            (10, ids[0], ids[1], 10.0, base + 300),
            (11, ids[1], ids[2], 11.0, base + 500),
            (12, ids[2], ids[0], 12.0, base + 700),
            (20, ids[3], ids[4], 20.0, base + 2000),
            (21, ids[4], ids[5], 21.0, base + 1000),
            (22, ids[5], ids[3], 22.0, base + 87400),
            (30, ids[6], ids[7], 30.0, base + 100),
            (31, ids[7], ids[8], 31.0, base + 200),
            (32, ids[8], ids[6], 32.0, base + 86502),
            (40, ids[9], ids[10], 40.0, base + 50),
            (41, ids[10], ids[11], 41.0, base + 60),
        ]
        expected = expected_cycles(rows)
        actual = run_program(rows)
        assert actual == expected, f"Expected derived violations {expected}, found {actual}"
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if original_violations is None:
            if os.path.exists(VIOLATIONS_PATH):
                os.remove(VIOLATIONS_PATH)
        else:
            with open(VIOLATIONS_PATH, "wb") as f:
                f.write(original_violations)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
