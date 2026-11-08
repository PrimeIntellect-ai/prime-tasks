#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import tempfile

DB_PATH = "/home/user/research.db"
SCRIPT_PATH = "/home/user/process_research.py"
JSON_PATH = "/home/user/results.json"

ORIGINAL_EXPECTED = [
    {"experiment_name": "Exp_10", "total_value": 737.58},
    {"experiment_name": "Exp_20", "total_value": 732.12},
    {"experiment_name": "Exp_18", "total_value": 718.59},
]


def expected_from_database():
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute("""
            SELECT e.name, ROUND(SUM(s.measurement), 2) AS total_value
            FROM samples AS s
            JOIN experiments AS e ON e.id = s.exp_id
            JOIN sensors AS se ON se.id = s.sensor_id
            WHERE se.sensor_type = 'TypeA' AND e.year = 2023
            GROUP BY e.id, e.name
            ORDER BY SUM(s.measurement) DESC
            LIMIT 3
        """).fetchall()
    return [
        {"experiment_name": name, "total_value": float(total)}
        for name, total in rows
    ]


def read_and_validate_json(expected):
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} is missing."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(data, list), f"JSON root must be an array, got {type(data)}."
    assert len(data) == 3, f"Expected exactly 3 objects in JSON array, got {len(data)}."
    assert len(expected) == 3, "The database query did not produce three expected groups."

    for i, wanted in enumerate(expected):
        actual = data[i]
        assert isinstance(actual, dict), f"Object at index {i} must be a JSON object."
        assert set(actual) == {"experiment_name", "total_value"}, \
            f"Object at index {i} must have exactly experiment_name and total_value keys."
        assert isinstance(actual["experiment_name"], str), \
            f"experiment_name at index {i} must be a string."
        assert type(actual["total_value"]) is float, \
            f"total_value at index {i} must be a float."
        assert actual["experiment_name"] == wanted["experiment_name"], \
            f"Expected experiment_name {wanted['experiment_name']!r} at index {i}, got {actual['experiment_name']!r}."
        assert round(actual["total_value"], 2) == wanted["total_value"], \
            f"Expected total_value {wanted['total_value']} at index {i}, got {actual['total_value']}."

    assert all(data[i]["total_value"] >= data[i + 1]["total_value"] for i in range(2)), \
        "Results are not ordered by total_value descending."


def assert_covering_index_exists():
    with sqlite3.connect(DB_PATH) as conn:
        indexes = conn.execute("PRAGMA index_list('samples')").fetchall()
        matching = [row for row in indexes if row[1] == "idx_opt_samples"]
        assert matching, "The required index 'idx_opt_samples' was not created on samples."
        assert matching[0][4] == 0, "idx_opt_samples must not be a partial index."
        columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_opt_samples')")]

    required = {"exp_id", "sensor_id", "measurement"}
    assert required.issubset(columns), \
        f"idx_opt_samples is not covering; expected columns {sorted(required)}, got {columns}."


def run_script_and_capture_sql():
    trace_file = tempfile.NamedTemporaryFile(prefix="research_sql_", delete=False)
    trace_path = trace_file.name
    trace_file.close()

    hook_dir = tempfile.mkdtemp(prefix="research_hook_")
    hook_path = os.path.join(hook_dir, "sitecustomize.py")
    with open(hook_path, "w") as f:
        f.write(r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("RESEARCH_TRACE_FILE")

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    if _trace_path:
        def _trace(statement):
            with open(_trace_path, "a") as out:
                out.write(json.dumps(statement) + "\n")
        conn.set_trace_callback(_trace)
    return conn

sqlite3.connect = _connect
''')

    env = os.environ.copy()
    env["RESEARCH_TRACE_FILE"] = trace_path
    env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"process_research.py failed with exit code {result.returncode}:\n{result.stderr}"

    statements = []
    with open(trace_path, "r") as f:
        for line in f:
            if line.strip():
                statements.append(json.loads(line))

    bare_reindex = re.compile(
        r"^\s*REINDEX\s*;?\s*(?:(?:--[^\n]*(?:\n|$)|/\*.*?\*/)\s*)*$",
        re.IGNORECASE | re.DOTALL,
    )
    assert any(bare_reindex.fullmatch(statement) for statement in statements), \
        "The executed script did not execute bare REINDEX to repair all database indices."


def reset_generated_artifacts():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DROP INDEX IF EXISTS idx_opt_samples")
        conn.commit()


def test_complete_workflow():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "REINDEX" in content.upper(), \
        "The Python script does not appear to contain the REINDEX command to fix the corruption."

    # Verify the required original result after executing the submitted artifact.
    reset_generated_artifacts()
    run_script_and_capture_sql()
    read_and_validate_json(ORIGINAL_EXPECTED)
    assert_covering_index_exists()

    # Exercise the script again on verifier-generated data so constants cannot pass.
    token = "Verifier_" + secrets.token_hex(8)
    measurement = float(1_000_000 + secrets.randbelow(500_000)) + 0.37
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("UPDATE experiments SET name = ? WHERE id = 2", (token,))
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM samples").fetchone()[0]
        conn.execute(
            "INSERT INTO samples(id, exp_id, sensor_id, measurement) VALUES (?, 2, 1, ?)",
            (next_id, measurement),
        )
        conn.commit()

    dynamic_expected = expected_from_database()
    assert dynamic_expected[0]["experiment_name"] == token, \
        "Verifier-generated test data did not affect the expected top result."

    reset_generated_artifacts()
    run_script_and_capture_sql()
    read_and_validate_json(dynamic_expected)
    assert_covering_index_exists()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
