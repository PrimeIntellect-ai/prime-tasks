#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

HOME = "/home/user"
GO_FILE = os.path.join(HOME, "analyzer.go")
JSON_FILE = os.path.join(HOME, "critical_path.json")
DB_FILE = os.path.join(HOME, "tracing.db")


def run_analyzer(start_service):
    result = subprocess.run(
        ["go", "run", "analyzer.go", start_service],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"analyzer.go failed for {start_service!r}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_FILE), f"Output file {JSON_FILE} does not exist."
    with open(JSON_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {JSON_FILE} does not contain valid JSON: {exc}")
    return data


def expected_critical_path(start_service):
    with sqlite3.connect(DB_FILE) as conn:
        rows = conn.execute("SELECT id, name FROM services").fetchall()
        calls = conn.execute(
            "SELECT caller_id, callee_id, latency_ms FROM calls"
        ).fetchall()

    id_to_name = {service_id: name for service_id, name in rows}
    name_to_id = {name: service_id for service_id, name in rows}
    assert start_service in name_to_id

    adjacency = {}
    for caller, callee, latency in calls:
        adjacency.setdefault(caller, []).append((callee, latency))

    def visit(node, seen):
        best_latency = 0
        best_path = [id_to_name[node]]
        for callee, latency in adjacency.get(node, []):
            if callee in seen:
                continue
            child_latency, child_path = visit(callee, seen | {callee})
            candidate = latency + child_latency
            if candidate > best_latency:
                best_latency = candidate
                best_path = [id_to_name[node]] + child_path
        return best_latency, best_path

    total, path = visit(name_to_id[start_service], {name_to_id[start_service]})
    return {
        "start_service": start_service,
        "total_latency_ms": total,
        "path": path,
    }


def assert_exact_output(data, expected):
    assert set(data.keys()) == {"start_service", "total_latency_ms", "path"}, (
        f"JSON must contain exactly start_service, total_latency_ms, and path; got {data.keys()}"
    )
    assert data["start_service"] == expected["start_service"]
    assert type(data["total_latency_ms"]) is int
    assert data["total_latency_ms"] == expected["total_latency_ms"]
    assert isinstance(data["path"], list)
    assert all(isinstance(item, str) for item in data["path"])
    assert data["path"] == expected["path"]


def test_analyzer_go_exists():
    """Verify that the Go program was created."""
    assert os.path.isfile(GO_FILE), f"Go program {GO_FILE} does not exist."


def test_source_uses_parameterized_recursive_cte():
    with open(GO_FILE, "r", encoding="utf-8") as f:
        source = f.read()

    # Ignore ordinary Go comments so merely mentioning the required SQL there is insufficient.
    uncommented = re.sub(r"/\\*.*?\\*/", "", source, flags=re.DOTALL)
    uncommented = re.sub(r"(?m)//.*$", "", uncommented)

    assert re.search(r"(?is)\\bWITH\\s+RECURSIVE\\b", uncommented), (
        "analyzer.go must execute a WITH RECURSIVE query"
    )
    assert re.search(r"(?is)\\bUNION(?:\\s+ALL)?\\b", uncommented), (
        "The recursive CTE must include a recursive UNION term"
    )
    assert re.search(r"\\?|\\$[0-9]+|[:@$][A-Za-z_][A-Za-z0-9_]*", uncommented), (
        "The recursive query must contain a SQLite bind placeholder"
    )
    assert re.search(r"\\.(?:Query|QueryRow|Exec)(?:Context)?\\s*\\(", uncommented), (
        "The program must execute its SQL through database/sql"
    )

    direct_bound_call = re.search(
        r"(?s)\\.(?:Query|QueryRow|Exec)(?:Context)?\\s*\\(.{0,1200}?,",
        uncommented,
    )
    prepared_bound_call = (
        re.search(r"\\.Prepare(?:Context)?\\s*\\(", uncommented)
        and re.search(r"\\.(?:Query|QueryRow|Exec)(?:Context)?\\s*\\(", uncommented)
    )
    assert direct_bound_call or prepared_bound_call, (
        "The SQL placeholder must be supplied through a bound database/sql argument"
    )


def test_program_runs_for_api_gateway():
    data = run_analyzer("API-Gateway")
    assert_exact_output(data, expected_critical_path("API-Gateway"))


def test_critical_path_json_exists():
    """Verify that the JSON output file was generated."""
    assert os.path.isfile(JSON_FILE), f"Output file {JSON_FILE} does not exist."


def test_critical_path_json_content():
    """Verify the content of the critical_path.json file."""
    with open(JSON_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_FILE} does not contain valid JSON.")

    assert "start_service" in data, "Missing 'start_service' key in JSON."
    assert data["start_service"] == "API-Gateway", f"Expected start_service 'API-Gateway', got '{data['start_service']}'."

    assert "total_latency_ms" in data, "Missing 'total_latency_ms' key in JSON."
    assert data["total_latency_ms"] == 190, f"Expected total_latency_ms 190, got {data['total_latency_ms']}."

    assert "path" in data, "Missing 'path' key in JSON."
    expected_path = ["API-Gateway", "User-Profile", "Billing", "Payment-Gateway"]
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}."


def test_program_handles_unseen_database_graph():
    suffix = uuid.uuid4().hex
    names = {
        "start": "Verifier-Start-" + suffix,
        "short": "Verifier-Short-" + suffix,
        "long": "Verifier-Long-" + suffix,
        "end": "Verifier-End-" + suffix,
    }
    inserted_ids = []

    try:
        with sqlite3.connect(DB_FILE) as conn:
            for name in names.values():
                cursor = conn.execute("INSERT INTO services(name) VALUES (?)", (name,))
                inserted_ids.append(cursor.lastrowid)

            ids = {
                key: conn.execute(
                    "SELECT id FROM services WHERE name = ?", (name,)
                ).fetchone()[0]
                for key, name in names.items()
            }
            conn.executemany(
                "INSERT INTO calls(caller_id, callee_id, latency_ms) VALUES (?, ?, ?)",
                [
                    (ids["start"], ids["short"], 11),
                    (ids["short"], ids["end"], 17),
                    (ids["start"], ids["long"], 23),
                    (ids["long"], ids["end"], 71),
                ],
            )

        expected = expected_critical_path(names["start"])
        data = run_analyzer(names["start"])
        assert_exact_output(data, expected)
    finally:
        if inserted_ids:
            placeholders = ",".join("?" for _ in inserted_ids)
            with sqlite3.connect(DB_FILE) as conn:
                conn.execute(
                    f"DELETE FROM calls WHERE caller_id IN ({placeholders}) OR callee_id IN ({placeholders})",
                    inserted_ids + inserted_ids,
                )
                conn.execute(
                    f"DELETE FROM services WHERE id IN ({placeholders})", inserted_ids
                )
        # Leave the required API-Gateway artifact in its requested final state.
        run_analyzer("API-Gateway")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
