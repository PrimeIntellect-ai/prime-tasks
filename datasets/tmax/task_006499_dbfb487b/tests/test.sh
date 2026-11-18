#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "analyze.go")
BINARY = "/tmp/analyze_under_test"
REPORT = os.path.join(HOME, "report.csv")
CYPHER = os.path.join(HOME, "import.cypher")
EMPLOYEES = os.path.join(HOME, "employees.csv")
COMMUNICATIONS = os.path.join(HOME, "communications.csv")


def write_fixture(employees, communications):
    with open(EMPLOYEES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        for emp_id, name, manager_id in employees:
            writer.writerow([emp_id, name, "" if manager_id is None else manager_id])
    with open(COMMUNICATIONS, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(communications)


def run_program():
    for path in (REPORT, CYPHER):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [BINARY], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Compiled analyze.go exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"Output file {REPORT} is missing after execution."
    assert os.path.isfile(CYPHER), f"Output file {CYPHER} is missing after execution."


def read_report():
    with open(REPORT, "r", newline="") as f:
        lines = [line.strip() for line in f if line.strip()]
    parsed = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 4, f"Invalid line format in report.csv: {line}"
        emp_id, name, score, rank = parts
        parsed.append((int(emp_id), name, int(score), int(rank)))
    return lines, parsed


def assert_report(expected):
    lines, parsed = read_report()
    parsed_records = set(parsed)
    for record in expected:
        assert record in parsed_records, f"Expected record {record} not found in {REPORT}."
    assert len(parsed_records) == len(expected), f"Found unexpected records in {REPORT}."
    assert len(lines) == len(expected), "report.csv contains duplicate or extra records."


def assert_cypher(expected_nodes, expected_reports, expected_communications):
    with open(CYPHER, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    node_indices = []
    report_indices = []
    comm_indices = []
    for i, line in enumerate(lines):
        if line in expected_nodes:
            node_indices.append(i)
        elif line in expected_reports:
            report_indices.append(i)
        elif line in expected_communications:
            comm_indices.append(i)
        else:
            pytest.fail(f"Unexpected or incorrectly formatted statement in {CYPHER}: {line}")

    assert len(node_indices) == len(expected_nodes), "Missing some Employee node creation statements."
    assert len(report_indices) == len(expected_reports), "Missing some REPORTS_TO relationship creation statements."
    assert len(comm_indices) == len(expected_communications), "Missing some COMMUNICATED_WITH relationship creation statements."
    assert set(lines) == expected_nodes | expected_reports | expected_communications, "Cypher statements do not exactly match the required graph."
    assert len(lines) == len(set(lines)), "import.cypher contains duplicate statements."

    assert node_indices and report_indices and comm_indices
    assert max(node_indices) < min(report_indices), "Employee node creations must appear before REPORTS_TO creations."
    assert max(report_indices) < min(comm_indices), "REPORTS_TO creations must appear before COMMUNICATED_WITH creations."


def derived_expectations(employees, communications):
    subordinate_counts = {emp_id: 0 for emp_id, _, _ in employees}
    receivers = {emp_id: set() for emp_id, _, _ in employees}
    for emp_id, _, manager_id in employees:
        if manager_id is not None:
            subordinate_counts[manager_id] += 1
    for sender, receiver, _, _ in communications:
        receivers[sender].add(receiver)

    scores = {
        emp_id: subordinate_counts[emp_id] * 2 + len(receivers[emp_id])
        for emp_id, _, _ in employees
    }
    distinct_scores = sorted(set(scores.values()), reverse=True)
    ranks = {score: i + 1 for i, score in enumerate(distinct_scores)}
    expected_report = {
        (emp_id, name, scores[emp_id], ranks[scores[emp_id]])
        for emp_id, name, _ in employees if ranks[scores[emp_id]] <= 3
    }

    expected_nodes = {
        f"CREATE (:Employee {{emp_id: {emp_id}, name: '{name}'}});"
        for emp_id, name, _ in employees
    }
    expected_reports = {
        f"MATCH (sub:Employee {{emp_id: {emp_id}}}), (mgr:Employee {{emp_id: {manager_id}}}) CREATE (sub)-[:REPORTS_TO]->(mgr);"
        for emp_id, _, manager_id in employees if manager_id is not None
    }
    expected_communications = {
        f"MATCH (s:Employee {{emp_id: {sender}}}), (r:Employee {{emp_id: {receiver}}}) CREATE (s)-[:COMMUNICATED_WITH]->(r);"
        for sender, receiver, _, _ in communications
    }
    return expected_report, expected_nodes, expected_reports, expected_communications


def test_submission():
    assert os.path.isfile(SOURCE), f"Required Go source file {SOURCE} is missing."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    assert re.search(r"(?m)^\s*package\s+main\b", source), "analyze.go must be a Go main package."
    assert "database/sql" in source, "analyze.go must use Go's database/sql package."
    assert "github.com/mattn/go-sqlite3" in source, "analyze.go must import the requested SQLite driver."
    assert re.search(r"\bsql\s*\.\s*Open\s*\(", source), "analyze.go must open a SQL database."
    assert re.search(r"DENSE_RANK\s*\(", source, re.IGNORECASE), "The SQL must use DENSE_RANK()."
    assert re.search(r"sqlite3", source, re.IGNORECASE), "analyze.go must initialize SQLite."

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, (
        f"analyze.go does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    # Execute against the original supplied data and retain the original assertions.
    original_employees = [
        (1, "Alice", None), (2, "Bob", 1), (3, "Charlie", 1),
        (4, "David", 2), (5, "Eve", 2), (6, "Frank", 3),
    ]
    original_communications = [
        (1, 2, "2023-01-01T10:00:00Z", 100),
        (2, 3, "2023-01-01T10:05:00Z", 200),
        (1, 4, "2023-01-01T10:10:00Z", 50),
        (1, 2, "2023-01-01T10:15:00Z", 60),
        (5, 1, "2023-01-01T11:00:00Z", 10),
        (6, 5, "2023-01-01T11:30:00Z", 20),
        (6, 4, "2023-01-01T12:00:00Z", 20),
    ]
    write_fixture(original_employees, original_communications)
    run_program()
    expected = derived_expectations(original_employees, original_communications)
    assert_report(expected[0])
    assert_cypher(expected[1], expected[2], expected[3])

    # Re-execute on unpredictable IDs and names. The tie at the highest score
    # distinguishes DENSE_RANK from RANK, and duplicate messages test DISTINCT.
    ids = secrets.SystemRandom().sample(range(1000, 9000), 7)
    suffix = secrets.token_hex(4)
    dynamic_employees = [
        (ids[0], "Root" + suffix, None),
        (ids[1], "Branch" + suffix, ids[0]),
        (ids[2], "Team" + suffix, ids[0]),
        (ids[3], "Delta" + suffix, ids[1]),
        (ids[4], "Echo" + suffix, ids[1]),
        (ids[5], "Foxtrot" + suffix, ids[2]),
        (ids[6], "Guest" + suffix, None),
    ]
    pairs = [
        (ids[0], ids[1]), (ids[0], ids[3]),
        (ids[1], ids[0]), (ids[1], ids[2]),
        (ids[2], ids[0]), (ids[2], ids[3]), (ids[2], ids[5]),
        (ids[3], ids[0]), (ids[3], ids[1]), (ids[3], ids[2]), (ids[3], ids[4]),
        (ids[4], ids[0]),
        (ids[5], ids[3]), (ids[5], ids[4]),
    ]
    dynamic_communications = [
        (sender, receiver, f"2026-02-{(i % 20) + 1:02d}T12:00:00Z", i + 10)
        for i, (sender, receiver) in enumerate(pairs)
    ]
    dynamic_communications.append(
        (ids[0], ids[1], "2026-03-01T13:00:00Z", 999)
    )

    write_fixture(dynamic_employees, dynamic_communications)
    run_program()
    expected = derived_expectations(dynamic_employees, dynamic_communications)
    assert_report(expected[0])
    assert_cypher(expected[1], expected[2], expected[3])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
