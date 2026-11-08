#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import uuid
from pathlib import Path

import networkx as nx
import pytest

PY_SCRIPT = Path("/home/user/analyze_deadlocks.py")
BASH_SCRIPT = Path("/home/user/run_analysis.sh")
DB_PATH = Path("/home/user/transactions.db")
REPORT_PATH = Path("/home/user/deadlock_report.json")


def run_analysis():
    result = subprocess.run(
        [str(BASH_SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"run_analysis.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT_PATH.exists(), f"{REPORT_PATH} is missing after running the analysis."
    try:
        return json.loads(REPORT_PATH.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"{REPORT_PATH} does not contain valid JSON: {exc}")


def test_scripts_exist():
    assert PY_SCRIPT.exists(), f"{PY_SCRIPT} is missing."
    assert PY_SCRIPT.is_file(), f"{PY_SCRIPT} is not a file."

    assert BASH_SCRIPT.exists(), f"{BASH_SCRIPT} is missing."
    assert BASH_SCRIPT.is_file(), f"{BASH_SCRIPT} is not a file."
    assert os.access(BASH_SCRIPT, os.X_OK), f"{BASH_SCRIPT} is not executable."


def test_original_database_report():
    data = run_analysis()

    assert "bottleneck_tx" in data, "Key 'bottleneck_tx' is missing from the JSON report."
    assert data["bottleneck_tx"] == "T6", f"Expected bottleneck_tx to be 'T6', got '{data['bottleneck_tx']}'."

    assert "deadlocks" in data, "Key 'deadlocks' is missing from the JSON report."
    deadlocks = data["deadlocks"]
    assert isinstance(deadlocks, list), "'deadlocks' should be a list."
    assert len(deadlocks) == 2, f"Expected 2 deadlock cycles, found {len(deadlocks)}."

    cycle_sets = [set(cycle) for cycle in deadlocks]
    assert {"T1", "T2", "T3"} in cycle_sets, "Cycle involving T1, T2, T3 is missing from deadlocks."
    assert {"T4", "T5"} in cycle_sets, "Cycle involving T4, T5 is missing from deadlocks."

    assert "in_degree_centrality" in data, "Key 'in_degree_centrality' is missing from the JSON report."
    centrality = data["in_degree_centrality"]
    assert isinstance(centrality, dict), "'in_degree_centrality' should be an object (dictionary)."

    expected_centrality = {
        "T1": 0.125, "T2": 0.125, "T3": 0.125,
        "T4": 0.125, "T5": 0.125,
        "T6": 0.375,
        "T7": 0.0, "T8": 0.0, "T9": 0.0,
    }
    for node, expected_val in expected_centrality.items():
        assert node in centrality, f"Node '{node}' is missing from in_degree_centrality."
        actual_val = centrality[node]
        assert isinstance(actual_val, (int, float)), f"Centrality for '{node}' must be a number."
        assert abs(actual_val - expected_val) < 1e-6, (
            f"Centrality for '{node}' expected to be {expected_val}, got {actual_val}."
        )


def test_scripts_analyze_changed_database_and_bash_invokes_python():
    token = uuid.uuid4().hex
    names = [f"tx_{token}_{i}" for i in range(13)]
    cycle_four = names[0:4]
    cycle_three = names[4:7]
    hub = names[7]
    waiters = names[8:13]

    rows = []
    resource_number = 0

    def add_cycle(nodes):
        nonlocal resource_number
        for i, holder in enumerate(nodes):
            resource = f"res_{token}_{resource_number}"
            resource_number += 1
            rows.append((holder, resource, "GRANTED"))
            rows.append((nodes[(i + 1) % len(nodes)], resource, "WAITING"))

    add_cycle(cycle_four)
    add_cycle(cycle_three)
    hub_resource = f"res_{token}_hub"
    rows.append((hub, hub_resource, "GRANTED"))
    rows.extend((waiter, hub_resource, "WAITING") for waiter in waiters)

    graph = nx.DiGraph()
    granted = {}
    waiting = []
    for tx_id, resource, state in rows:
        if state == "GRANTED":
            granted.setdefault(resource, []).append(tx_id)
        elif state == "WAITING":
            waiting.append((tx_id, resource))
    for waiter, resource in waiting:
        for holder in granted.get(resource, []):
            graph.add_edge(waiter, holder)

    expected_centrality = nx.in_degree_centrality(graph)
    expected_cycle_sets = {frozenset(cycle) for cycle in nx.simple_cycles(graph)}
    expected_bottleneck = max(expected_centrality, key=expected_centrality.get)

    original_db = DB_PATH.read_bytes()
    original_script = PY_SCRIPT.read_bytes()
    original_mode = PY_SCRIPT.stat().st_mode
    original_report = REPORT_PATH.read_bytes() if REPORT_PATH.exists() else None
    saved_script = Path(f"/tmp/submitted_analyze_{token}.py")
    marker = Path(f"/tmp/analyze_invoked_{token}")

    try:
        conn = sqlite3.connect(str(DB_PATH))
        try:
            conn.execute("DELETE FROM locks")
            conn.executemany("INSERT INTO locks (tx_id, resource, state) VALUES (?, ?, ?)", rows)
            conn.commit()
        finally:
            conn.close()

        saved_script.write_bytes(original_script)
        wrapper = (
            "#!/usr/bin/env python3\n"
            "from pathlib import Path\n"
            "import runpy\n"
            f"Path({str(marker)!r}).write_text('invoked')\n"
            f"runpy.run_path({str(saved_script)!r}, run_name='__main__')\n"
        )
        PY_SCRIPT.write_text(wrapper)
        PY_SCRIPT.chmod(0o755)
        if REPORT_PATH.exists():
            REPORT_PATH.unlink()

        data = run_analysis()
        assert marker.exists(), "run_analysis.sh did not execute /home/user/analyze_deadlocks.py."

        assert set(data.keys()) == {"deadlocks", "in_degree_centrality", "bottleneck_tx"}
        assert isinstance(data["deadlocks"], list)
        actual_cycle_sets = {frozenset(cycle) for cycle in data["deadlocks"]}
        assert len(data["deadlocks"]) == len(expected_cycle_sets)
        assert actual_cycle_sets == expected_cycle_sets, (
            f"Deadlocks do not match the changed database: {data['deadlocks']}"
        )

        centrality = data["in_degree_centrality"]
        assert isinstance(centrality, dict)
        assert set(centrality) == set(expected_centrality)
        for node, expected in expected_centrality.items():
            actual = centrality[node]
            assert isinstance(actual, (int, float))
            assert abs(actual - expected) < 1e-9, (
                f"Centrality for {node} expected {expected}, got {actual}."
            )
        assert data["bottleneck_tx"] == expected_bottleneck
    finally:
        DB_PATH.write_bytes(original_db)
        PY_SCRIPT.write_bytes(original_script)
        PY_SCRIPT.chmod(original_mode)
        if original_report is None:
            if REPORT_PATH.exists():
                REPORT_PATH.unlink()
        else:
            REPORT_PATH.write_bytes(original_report)
        saved_script.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
