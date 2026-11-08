#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import inspect
import os
import re
import sqlite3
import tempfile

SCRIPT_PATH = '/home/user/process_results.py'
DB_PATH = '/home/user/sensor_data.db'
PLANS_PATH = '/home/user/query_plans.txt'


def load_process_results():
    spec = importlib.util.spec_from_file_location('submitted_process_results', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_process_results_parameterized(monkeypatch):
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    # Preserve the original static assertions.
    assert ".format(" not in source, "The script still contains .format(), which is not allowed for SQL queries."

    tree = ast.parse(source)
    execute_calls = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == 'execute':
                execute_calls += 1
                assert len(node.args) == 2, "cursor.execute() must be called with exactly two arguments: the query and the parameters."
                assert not isinstance(node.args[0], ast.JoinedStr), "f-strings must not be used in cursor.execute()."

    assert execute_calls >= 2, "Expected at least two cursor.execute() calls in the script."

    module = load_process_results()
    assert list(inspect.signature(module.get_sensor_history).parameters) == [
        'db_path', 'sensor_id', 'start_time', 'end_time'
    ], "get_sensor_history() signature was changed."
    assert list(inspect.signature(module.get_batch_stats).parameters) == [
        'db_path', 'batch_id'
    ], "get_batch_stats() signature was changed."

    calls = []
    connections = []

    class FakeCursor:
        def execute(self, sql, params):
            calls.append((sql, params))
            return self

        def fetchall(self):
            return [('history-result', 12.5)]

        def fetchone(self):
            return (7, 3.25)

    class FakeConnection:
        def __init__(self):
            self.closed = False

        def cursor(self):
            return FakeCursor()

        def close(self):
            self.closed = True

    def fake_connect(path):
        connection = FakeConnection()
        connections.append(connection)
        return connection

    monkeypatch.setattr(module.sqlite3, 'connect', fake_connect)

    sensor = "S-'quoted-value"
    start = "2023-01-01 00:00:00"
    end = "2023-01-31 23:59:59"
    batch = "B-'quoted-value"

    assert module.get_sensor_history('/unused.db', sensor, start, end) == [('history-result', 12.5)]
    assert module.get_batch_stats('/unused.db', batch) == (7, 3.25)
    assert len(calls) == 2, "Each processing function must execute its query once."

    history_sql, history_params = calls[0]
    batch_sql, batch_params = calls[1]
    assert isinstance(history_sql, str) and history_sql.count('?') == 3, \
        "The sensor history query must contain three SQLite ? placeholders."
    assert isinstance(batch_sql, str) and batch_sql.count('?') == 1, \
        "The batch stats query must contain one SQLite ? placeholder."
    assert isinstance(history_params, tuple) and history_params == (sensor, start, end), \
        "The sensor history parameters must be the tuple (sensor_id, start_time, end_time)."
    assert isinstance(batch_params, tuple) and batch_params == (batch,), \
        "The batch stats parameters must be the one-element tuple (batch_id,)."
    assert sensor not in history_sql and start not in history_sql and end not in history_sql, \
        "Sensor history values were interpolated into SQL instead of being bound."
    assert batch not in batch_sql, "The batch value was interpolated into SQL instead of being bound."
    assert all(connection.closed for connection in connections), "Database connections must still be closed."


def test_process_results_behavior():
    module = load_process_results()
    fd, db_path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    try:
        conn = sqlite3.connect(db_path)
        conn.execute('CREATE TABLE readings (id INTEGER PRIMARY KEY, sensor_id TEXT, timestamp DATETIME, value REAL, batch TEXT)')
        conn.executemany(
            'INSERT INTO readings (sensor_id, timestamp, value, batch) VALUES (?, ?, ?, ?)',
            [
                ('S-100', '2023-01-20 10:00:00', 20.0, 'B-52'),
                ('S-100', '2023-01-01 00:00:00', 10.0, 'B-52'),
                ('S-100', '2023-02-01 00:00:00', 99.0, 'B-53'),
                ("S-100' OR 1=1 --", '2023-01-15 12:00:00', 77.0, "B-52' OR 1=1 --"),
                ('S-200', '2023-01-10 00:00:00', 30.0, 'B-52'),
            ],
        )
        conn.commit()
        conn.close()

        history = module.get_sensor_history(db_path, 'S-100', '2023-01-01 00:00:00', '2023-01-31 23:59:59')
        assert history == [
            ('2023-01-01 00:00:00', 10.0),
            ('2023-01-20 10:00:00', 20.0),
        ], "get_sensor_history() no longer returns the correct ordered rows."

        injected_history = module.get_sensor_history(
            db_path, "S-100' OR 1=1 --", '2023-01-01 00:00:00', '2023-01-31 23:59:59'
        )
        assert injected_history == [('2023-01-15 12:00:00', 77.0)], \
            "The sensor ID is not being handled as a bound value."

        stats = module.get_batch_stats(db_path, 'B-52')
        assert stats == (3, 20.0), "get_batch_stats() no longer returns the correct count and average."
        injected_stats = module.get_batch_stats(db_path, "B-52' OR 1=1 --")
        assert injected_stats == (1, 77.0), "The batch ID is not being handled as a bound value."
    finally:
        if os.path.exists(db_path):
            os.unlink(db_path)


def test_database_indexes():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_sensor_time', 'idx_batch');")
    indexes = {row[0] for row in c.fetchall()}

    # Preserve the original name assertions.
    assert 'idx_sensor_time' in indexes, "Index 'idx_sensor_time' is missing from the database."
    assert 'idx_batch' in indexes, "Index 'idx_batch' is missing from the database."

    sensor_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_sensor_time')")]
    batch_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_batch')")]
    assert sensor_columns == ['sensor_id', 'timestamp'], \
        "idx_sensor_time must index readings(sensor_id, timestamp), in that order."
    assert batch_columns == ['batch'], "idx_batch must index readings(batch)."

    sensor_plan = conn.execute(
        "EXPLAIN QUERY PLAN SELECT timestamp, value FROM readings "
        "WHERE sensor_id = ? AND timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC",
        ('S-100', '2023-01-01', '2023-01-31'),
    ).fetchall()
    batch_plan = conn.execute(
        "EXPLAIN QUERY PLAN SELECT COUNT(*), AVG(value) FROM readings WHERE batch = ?",
        ('B-52',),
    ).fetchall()
    conn.close()

    assert any('idx_sensor_time' in row[3] for row in sensor_plan), \
        "SQLite does not use idx_sensor_time for the sensor history query."
    assert any('idx_batch' in row[3] for row in batch_plan), \
        "SQLite does not use idx_batch for the batch stats query."


def test_query_plans_file():
    assert os.path.isfile(PLANS_PATH), f"Query plans file {PLANS_PATH} does not exist."

    with open(PLANS_PATH, 'r') as f:
        content = f.read()

    # Preserve the original index-usage assertions.
    assert "USING INDEX idx_sensor_time" in content or "USING INDEX 'idx_sensor_time'" in content or "USING INDEX `idx_sensor_time`" in content or "USING INDEX \"idx_sensor_time\"" in content or "USING COVERING INDEX idx_sensor_time" in content, "The query_plans.txt does not show usage of 'idx_sensor_time'."
    assert "USING INDEX idx_batch" in content or "USING INDEX 'idx_batch'" in content or "USING INDEX `idx_batch`" in content or "USING INDEX \"idx_batch\"" in content or "USING COVERING INDEX idx_batch" in content, "The query_plans.txt does not show usage of 'idx_batch'."

    sections = re.split(r'\n[ \t]*\n', content.strip())
    assert len(sections) == 2 and all(section.strip() for section in sections), \
        "query_plans.txt must contain the first plan, one blank line, and then the second plan."

    conn = sqlite3.connect(DB_PATH)
    expected_sensor = [row[3] for row in conn.execute(
        "EXPLAIN QUERY PLAN SELECT timestamp, value FROM readings "
        "WHERE sensor_id = ? AND timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC",
        ('S-100', '2023-01-01', '2023-01-31'),
    )]
    expected_batch = [row[3] for row in conn.execute(
        "EXPLAIN QUERY PLAN SELECT COUNT(*), AVG(value) FROM readings WHERE batch = ?",
        ('B-52',),
    )]
    conn.close()

    assert all(detail in sections[0] for detail in expected_sensor), \
        "The first saved plan does not match SQLite's actual sensor history EXPLAIN output."
    assert all(detail in sections[1] for detail in expected_batch), \
        "The second saved plan does not match SQLite's actual batch stats EXPLAIN output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
