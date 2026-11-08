#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import math
import os
import random
import sqlite3
import subprocess
import tempfile

APP_PATH = "/home/user/uptime_monitor/app.py"
OUTPUT_PATH = "/home/user/uptime_monitor/fixed_output.txt"


def load_app():
    spec = importlib.util.spec_from_file_location("uptime_monitor_app", APP_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reference_uptime(rows):
    if not rows:
        return {"uptime": 0.0}
    previous_timestamp = rows[0][0]
    ema = 1.0 if rows[0][1] == "UP" else 0.0
    for timestamp, status in rows[1:]:
        value = 1.0 if status == "UP" else 0.0
        difference = timestamp - previous_timestamp
        weight = 1.0 / difference
        alpha = min(weight * 0.1, 1.0)
        ema = value * alpha + ema * (1.0 - alpha)
        previous_timestamp = timestamp
    return {"final_uptime_score": round(ema, 4)}


def test_fixed_output_file_exists():
    """Check that the fixed_output.txt file exists."""
    assert os.path.isfile(OUTPUT_PATH), f"File {OUTPUT_PATH} does not exist. Did you save the output?"


def test_fixed_output_content():
    """Check that the fixed_output.txt contains the correct final_uptime_score."""
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert "0.9902" in content, f"Expected to find '0.9902' in {OUTPUT_PATH}, but found: {content}"

    # Retain the original parsing assertions.
    try:
        parsed = ast.literal_eval(content)
        assert isinstance(parsed, dict), "Output should be a dictionary"
        assert "final_uptime_score" in parsed, "Dictionary must contain 'final_uptime_score'"
        assert parsed["final_uptime_score"] == 0.9902, f"Expected score 0.9902, got {parsed['final_uptime_score']}"
    except (SyntaxError, ValueError):
        pass


def test_app_py_runs_successfully():
    """Check that the modified app.py runs without errors and outputs the correct result."""
    assert os.path.isfile(APP_PATH), f"File {APP_PATH} does not exist."

    result = subprocess.run(["python3", APP_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"app.py crashed with error:\n{result.stderr}"

    output = result.stdout.strip()
    assert "0.9902" in output, f"app.py did not output the expected value '0.9902'. Output was: {output}"


def test_output_is_exact_single_dictionary_and_matches_saved_file():
    result = subprocess.run(["python3", APP_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"app.py crashed with error:\n{result.stderr}"
    output = result.stdout.strip()
    parsed = ast.literal_eval(output)
    assert parsed == {"final_uptime_score": 0.9902}, f"Unexpected final dictionary: {parsed!r}"
    assert len([line for line in output.splitlines() if line.strip()]) == 1, "app.py must print one dictionary"

    with open(OUTPUT_PATH, "r") as handle:
        saved = handle.read().strip()
    saved_parsed = ast.literal_eval(saved)
    assert saved_parsed == {"final_uptime_score": 0.9902}, f"Unexpected saved dictionary: {saved_parsed!r}"
    assert saved == output, "fixed_output.txt must contain the exact dictionary printed by app.py"


def test_get_metrics_executes_a_correct_nonduplicating_join():
    app = load_app()
    assert callable(getattr(app, "get_metrics", None)), "get_metrics must remain callable"

    rng = random.SystemRandom()
    server_a = rng.randrange(1000, 1000000)
    server_b = server_a + rng.randrange(1, 1000)
    orphan = server_b + rng.randrange(1, 1000)
    base = float(rng.randrange(2000000000, 3000000000))

    fd, database_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    connection = sqlite3.connect(database_path)
    connection.executescript("""
        CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE heartbeats (
            id INTEGER PRIMARY KEY,
            server_id INTEGER,
            timestamp REAL,
            status TEXT
        );
    """)
    connection.executemany(
        "INSERT INTO servers (id, name) VALUES (?, ?)",
        [(server_a, "a"), (server_b, "b")],
    )
    inserted = [
        (server_b, base + 30.0, "DOWN"),
        (server_a, base + 10.0, "UP"),
        (server_b, base + 20.0, "UP"),
        (orphan, base + 15.0, "DOWN"),
    ]
    connection.executemany(
        "INSERT INTO heartbeats (server_id, timestamp, status) VALUES (?, ?, ?)", inserted
    )
    connection.commit()
    connection.close()

    real_connect = app.sqlite3.connect
    traced_sql = []

    def test_connect(_path):
        conn = real_connect(database_path)
        conn.set_trace_callback(traced_sql.append)
        return conn

    app.sqlite3.connect = test_connect
    try:
        rows = list(app.get_metrics())
    finally:
        app.sqlite3.connect = real_connect
        os.unlink(database_path)

    expected = [
        (base + 10.0, "UP"),
        (base + 20.0, "UP"),
        (base + 30.0, "DOWN"),
    ]
    assert rows == expected, f"get_metrics must return each valid heartbeat exactly once; got {rows!r}"

    selects = [" ".join(statement.lower().split()) for statement in traced_sql if statement.lstrip().lower().startswith("select")]
    assert selects, "get_metrics did not execute a SELECT query"
    query = selects[-1]
    assert " join " in query, f"Expected a server join, but executed: {query}"
    assert "on 1=1" not in query.replace(" ", ""), f"Cartesian join remains in query: {query}"


def test_calculate_uptime_on_derived_varied_inputs():
    app = load_app()
    calculate = getattr(app, "calculate_uptime", None)
    assert callable(calculate), "calculate_uptime must remain callable"
    assert calculate([]) == {"uptime": 0.0}

    rng = random.SystemRandom()
    for _ in range(30):
        timestamp = float(rng.randrange(100000, 1000000))
        rows = [(timestamp, rng.choice(["UP", "DOWN"]))]
        for _ in range(rng.randrange(2, 12)):
            timestamp += rng.choice([0.05, 0.2, 1.0, 3.0, 10.0, 25.0])
            rows.append((timestamp, rng.choice(["UP", "DOWN"])))
        assert calculate(rows) == reference_uptime(rows), f"Incorrect uptime for rows {rows!r}"


def test_duplicate_timestamps_are_handled_gracefully():
    app = load_app()
    calculate = getattr(app, "calculate_uptime", None)
    rows = [
        (1000.0, "UP"),
        (1000.0, "DOWN"),
        (1005.0, "DOWN"),
        (1005.0, "UP"),
        (1010.0, "UP"),
    ]
    result = calculate(rows)
    assert isinstance(result, dict) and "final_uptime_score" in result, f"Malformed result: {result!r}"
    score = result["final_uptime_score"]
    assert isinstance(score, (int, float)) and math.isfinite(score), f"Non-finite score: {score!r}"
    assert 0.0 <= score <= 1.0, f"Uptime score is outside its valid range: {score!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
