#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import networkx as nx

SCRIPT = "/home/user/audit_pipeline.py"
DB = "/home/user/audit.db"
CSV_PATH = "/home/user/top_communicators.csv"
CENTRALITY_PATH = "/home/user/highest_centrality.json"
PATH_PATH = "/home/user/shortest_path.json"
OUTPUTS = (CSV_PATH, CENTRALITY_PATH, PATH_PATH)


def database_state():
    conn = sqlite3.connect(DB)
    try:
        employees = conn.execute(
            "SELECT id, name, department FROM employees ORDER BY id"
        ).fetchall()
        communications = conn.execute(
            "SELECT sender_id, receiver_id, timestamp FROM communications ORDER BY rowid"
        ).fetchall()
        return employees, communications
    finally:
        conn.close()


def expected_results():
    conn = sqlite3.connect(DB)
    try:
        counts = conn.execute("""
            SELECT e.department, e.id, COUNT(c.sender_id)
            FROM employees e
            JOIN communications c ON e.id = c.sender_id
            GROUP BY e.department, e.id
        """).fetchall()
        employee_ids = [row[0] for row in conn.execute("SELECT id FROM employees")]
        edges = conn.execute(
            "SELECT DISTINCT sender_id, receiver_id FROM communications"
        ).fetchall()
    finally:
        conn.close()

    maxima = {}
    for department, employee_id, count in counts:
        current = maxima.get(department)
        if current is None or count > current[0]:
            maxima[department] = (count, {employee_id})
        elif count == current[0]:
            current[1].add(employee_id)

    graph = nx.DiGraph()
    graph.add_nodes_from(employee_ids)
    graph.add_edges_from(edges)
    centralities = nx.betweenness_centrality(graph)
    maximum = max(centralities.values())
    highest_ids = {
        employee_id for employee_id, value in centralities.items()
        if abs(value - maximum) < 1e-12
    }
    return maxima, graph, centralities, highest_ids


def run_pipeline():
    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for path in OUTPUTS:
        assert os.path.isfile(path), f"Pipeline did not create {path}."


def validate_outputs(require_original_answers=False):
    maxima, graph, centralities, highest_ids = expected_results()

    with open(CSV_PATH, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader, None)
        assert header == ["department", "employee_id", "message_count"], "CSV header is incorrect."
        rows = list(reader)

    assert len(rows) == len(maxima), "CSV does not have the correct number of rows."
    seen_departments = set()
    for row in rows:
        assert len(row) == 3, "Each CSV row must contain exactly three fields."
        department, employee_text, count_text = row
        assert department in maxima, f"Unexpected department {department} in CSV."
        assert department not in seen_departments, f"Department {department} is duplicated."
        seen_departments.add(department)
        employee_id = int(employee_text)
        count = int(count_text)
        expected_count, tied_ids = maxima[department]
        assert count == expected_count, f"Incorrect message count for department {department}."
        assert employee_id in tied_ids, f"Employee {employee_id} is not a top sender in {department}."
    assert seen_departments == set(maxima), "CSV is missing one or more departments."

    with open(CENTRALITY_PATH) as handle:
        centrality_data = json.load(handle)
    assert set(centrality_data) == {"employee_id", "centrality"}, "Centrality JSON has incorrect keys."
    employee_id = centrality_data["employee_id"]
    value = centrality_data["centrality"]
    assert isinstance(employee_id, int) and not isinstance(employee_id, bool), "employee_id must be an integer."
    assert isinstance(value, (int, float)) and not isinstance(value, bool), "Centrality must be a number."
    assert employee_id in highest_ids, f"Employee {employee_id} does not have maximum betweenness centrality."
    assert value == round(centralities[employee_id], 4), "Centrality value is incorrect or not rounded to 4 places."

    with open(PATH_PATH) as handle:
        path_data = json.load(handle)
    assert set(path_data) == {"path"}, "Shortest-path JSON has incorrect keys."
    path = path_data["path"]
    assert isinstance(path, list) and all(isinstance(node, int) and not isinstance(node, bool) for node in path)
    assert path and path[0] == 3 and path[-1] == 18, "Path must run from employee 3 to employee 18."
    assert all(graph.has_edge(a, b) for a, b in zip(path, path[1:])), "Path contains a nonexistent directed edge."
    assert len(path) - 1 == nx.shortest_path_length(graph, 3, 18), "Reported path is not shortest."

    if require_original_answers:
        assert employee_id == 8, f"Expected employee_id 8, got {employee_id}."
        expected_path = [3, 8, 15, 18]
        assert path == expected_path, f"Expected path {expected_path}, got {path}."


def test_pipeline_source_and_end_to_end_behavior():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    with open(SCRIPT, encoding="utf-8") as handle:
        source = handle.read()

    assert re.search(r"\b(?:RANK|ROW_NUMBER)\s*\(\s*\)\s*OVER\s*\(", source, re.I | re.S), (
        "The pipeline must use RANK() or ROW_NUMBER() as a SQL window function."
    )
    assert re.search(r"\bJOIN\b", source, re.I) and re.search(r"\bON\b", source, re.I), (
        "The SQL must use an explicit join with an ON condition."
    )

    original_state = database_state()
    run_pipeline()
    assert database_state() == original_state, "The pipeline must not modify the audit database."
    validate_outputs(require_original_answers=True)

    fd, backup = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    shutil.copy2(DB, backup)
    try:
        conn = sqlite3.connect(DB)
        try:
            conn.execute("DELETE FROM communications")
            rows = []
            for employee_id in range(1, 21):
                if employee_id != 12:
                    rows.append((employee_id, 12, "2024-01-01 00:00:00"))
                    rows.append((12, employee_id, "2024-01-01 00:00:00"))
            for employee_id, extra_count in ((3, 5), (8, 6), (15, 7), (18, 8)):
                rows.extend([(employee_id, 12, "2024-01-02 00:00:00")] * extra_count)
            conn.executemany(
                "INSERT INTO communications(sender_id, receiver_id, timestamp) VALUES (?, ?, ?)",
                rows,
            )
            conn.commit()
        finally:
            conn.close()

        mutated_state = database_state()
        run_pipeline()
        assert database_state() == mutated_state, "The pipeline must not modify the audit database."
        validate_outputs(require_original_answers=False)

        with open(CENTRALITY_PATH) as handle:
            assert json.load(handle)["employee_id"] == 12, "Pipeline did not adapt to the changed graph."
        with open(PATH_PATH) as handle:
            assert json.load(handle)["path"] == [3, 12, 18], "Pipeline did not recompute the changed shortest path."
    finally:
        shutil.copy2(backup, DB)
        try:
            subprocess.run(
                [sys.executable, SCRIPT], cwd="/home/user",
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30
            )
        finally:
            shutil.copy2(backup, DB)
            os.remove(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
