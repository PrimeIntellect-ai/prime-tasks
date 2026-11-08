#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/analyze_instrument

cat << 'PY_EOF' > /tmp/analyze_instrument/sitecustomize.py
import os
import sqlite3

_real_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    trace_path = os.environ.get("ANALYZE_SQL_TRACE")
    if trace_path:
        def record(sql):
            try:
                with open(trace_path, "a", encoding="utf-8") as f:
                    f.write(sql.replace("\x00", " "))
                    f.write("\n--TRACE-END--\n")
            except Exception:
                pass
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = traced_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
from collections import Counter, defaultdict
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/analyze.py"
DB_PATH = "/home/user/network.db"
JSON_PATH = "/home/user/top_influencers.json"
EMPLOYEES_CSV = "/home/user/data/employees.csv"
INTERACTIONS_CSV = "/home/user/data/interactions.csv"
TRACE_PATH = "/tmp/analyze_sql_trace.log"
INSTRUMENT_DIR = "/tmp/analyze_instrument"


def run_script():
    for path in (DB_PATH, JSON_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    env = os.environ.copy()
    env["ANALYZE_SQL_TRACE"] = TRACE_PATH
    env["PYTHONPATH"] = INSTRUMENT_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        check=True,
        timeout=30,
    )


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def tables_with_columns(conn, required):
    result = []
    for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table'"):
        columns = {row[1] for row in conn.execute("PRAGMA table_info(%s)" % quote_ident(name))}
        if required.issubset(columns):
            result.append(name)
    return result


def read_csv_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def expected_graph(path):
    factors = {"email": Decimal(1), "meeting": Decimal(2), "code_review": Decimal(5)}
    graph = defaultdict(Decimal)
    for row in read_csv_rows(path):
        graph[(row["actor_email"], row["target_email"])] += factors[row["interaction_type"]] * Decimal(row["metric_value"])
    return dict(graph)


def expected_influencers(employees_path, interactions_path):
    departments = {r["email"]: r["department"] for r in read_csv_rows(employees_path)}
    incoming = defaultdict(Decimal)
    for (source, target), weight in expected_graph(interactions_path).items():
        if target in departments:
            incoming[target] += weight

    grouped = defaultdict(list)
    for email, weight in incoming.items():
        grouped[departments[email]].append((email, weight))

    answer = []
    for department, people in grouped.items():
        people.sort(key=lambda item: (-item[1], item[0]))
        for rank, (email, weight) in enumerate(people[:2], 1):
            value = int(weight) if weight == int(weight) else float(weight)
            answer.append({
                "department": department,
                "email": email,
                "incoming_weight": value,
                "rank": rank,
            })
    return sorted(answer, key=lambda x: (x["department"], x["rank"], x["email"]))


def assert_loaded_csv_tables(conn, employees_path, interactions_path):
    employee_tables = tables_with_columns(conn, {"email", "department"})
    assert employee_tables, "No loaded employee table with email and department columns was found."
    expected_employees = Counter((r["email"], r["department"]) for r in read_csv_rows(employees_path))
    assert any(
        Counter(conn.execute(
            "SELECT email, department FROM %s" % quote_ident(table)
        ).fetchall()) == expected_employees
        for table in employee_tables
    ), "No employee table contains exactly all rows from employees.csv."

    interaction_tables = tables_with_columns(
        conn,
        {"timestamp", "actor_email", "target_email", "interaction_type", "metric_value"},
    )
    assert interaction_tables, "No loaded interaction table with all CSV columns was found."
    expected_interactions = Counter(
        (r["timestamp"], r["actor_email"], r["target_email"], r["interaction_type"], Decimal(r["metric_value"]))
        for r in read_csv_rows(interactions_path)
    )
    found = False
    for table in interaction_tables:
        rows = conn.execute(
            "SELECT timestamp, actor_email, target_email, interaction_type, metric_value FROM %s" % quote_ident(table)
        ).fetchall()
        normalized = Counter((str(a), str(b), str(c), str(d), Decimal(str(e))) for a, b, c, d, e in rows)
        if normalized == expected_interactions:
            found = True
            break
    assert found, "No interaction table contains exactly all rows from interactions.csv."


def assert_complete_graph(conn, interactions_path):
    expected = expected_graph(interactions_path)
    rows = conn.execute(
        "SELECT source_email, target_email, total_weight FROM interaction_graph"
    ).fetchall()
    actual = Counter((str(s), str(t), Decimal(str(w))) for s, t, w in rows)
    wanted = Counter((s, t, w) for (s, t), w in expected.items())
    assert actual == wanted, "interaction_graph does not exactly match the weighted projection of all interaction rows."


def assert_json_matches(employees_path, interactions_path):
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    with open(JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, list), "JSON output must be a list of objects."
    required_keys = {"department", "email", "incoming_weight", "rank"}
    assert all(isinstance(item, dict) and set(item) == required_keys for item in data), \
        "Every JSON object must have exactly department, email, incoming_weight, and rank keys."
    actual = sorted(data, key=lambda x: (x["department"], x["rank"], x["email"]))
    assert actual == expected_influencers(employees_path, interactions_path)


def test_00_script_exists_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."
    run_script()
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist after executing analyze.py."
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist after executing analyze.py."


def test_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."


def test_interaction_graph_table():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='interaction_graph'")
    assert cursor.fetchone() is not None, "Table 'interaction_graph' does not exist."

    cursor.execute("PRAGMA table_info(interaction_graph)")
    columns = {row[1] for row in cursor.fetchall()}
    expected_columns = {"source_email", "target_email", "total_weight"}
    assert expected_columns.issubset(columns), f"Table 'interaction_graph' is missing required columns. Found: {columns}"

    cursor.execute("SELECT total_weight FROM interaction_graph WHERE source_email='alice@company.com' AND target_email='bob@company.com'")
    row = cursor.fetchone()
    assert row is not None, "Missing edge from alice to bob in interaction_graph."
    assert row[0] == 10, f"Expected total_weight 10 for alice->bob, got {row[0]}"

    cursor.execute("SELECT total_weight FROM interaction_graph WHERE source_email='grace@company.com' AND target_email='alice@company.com'")
    row = cursor.fetchone()
    assert row is not None, "Missing edge from grace to alice in interaction_graph."
    assert row[0] == 15, f"Expected total_weight 15 for grace->alice, got {row[0]}"

    assert_loaded_csv_tables(conn, EMPLOYEES_CSV, INTERACTIONS_CSV)
    assert_complete_graph(conn, INTERACTIONS_CSV)
    conn.close()


def test_indexes_exist():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='interaction_graph'")
    indexes_graph = cursor.fetchall()
    assert len(indexes_graph) > 0, "No indexes found on 'interaction_graph' table."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name IN (SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%employee%')")
    indexes_emp = cursor.fetchall()
    assert len(indexes_emp) > 0, "No indexes found on the employee table."

    graph_index_columns = []
    for (name,) in indexes_graph:
        graph_index_columns.extend(row[2] for row in conn.execute("PRAGMA index_info(%s)" % quote_ident(name)))
    assert "target_email" in graph_index_columns, "interaction_graph must have an index covering target_email."

    employee_index_has_email = False
    for table in tables_with_columns(conn, {"email", "department"}):
        for row in conn.execute("PRAGMA index_list(%s)" % quote_ident(table)):
            index_name = row[1]
            columns = [r[2] for r in conn.execute("PRAGMA index_info(%s)" % quote_ident(index_name))]
            if "email" in columns:
                employee_index_has_email = True
    assert employee_index_has_email, "The employee table must have an index covering email."
    conn.close()


def test_required_cte_window_query_was_executed():
    assert os.path.isfile(TRACE_PATH), "No SQLite statements were observed while analyze.py executed."
    with open(TRACE_PATH, encoding="utf-8") as f:
        statements = f.read().split("--TRACE-END--")
    pattern = re.compile(
        r"\bWITH\b[\s\S]*\bRANK\s*\(\s*\)\s*OVER\s*\([\s\S]*\bPARTITION\s+BY\b",
        re.IGNORECASE,
    )
    assert any(pattern.search(statement) for statement in statements), \
        "analyze.py did not execute a single SQL statement using both a CTE and RANK() OVER (PARTITION BY ...)."


def test_json_output():
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not valid JSON.")

    assert isinstance(data, list), "JSON output must be a list of objects."

    expected_data = [
        {"department": "Engineering", "email": "grace@company.com", "incoming_weight": 60, "rank": 1},
        {"department": "Engineering", "email": "bob@company.com", "incoming_weight": 45, "rank": 2},
        {"department": "Marketing", "email": "frank@company.com", "incoming_weight": 20, "rank": 1},
        {"department": "Marketing", "email": "eve@company.com", "incoming_weight": 10, "rank": 2},
        {"department": "Sales", "email": "charlie@company.com", "incoming_weight": 40, "rank": 1},
        {"department": "Sales", "email": "diana@company.com", "incoming_weight": 2, "rank": 2}
    ]

    def sort_key(item):
        return (item.get("department", ""), item.get("rank", 0))

    data_sorted = sorted(data, key=sort_key)
    expected_sorted = sorted(expected_data, key=sort_key)
    assert len(data_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} results, got {len(data_sorted)}."
    for actual, expected in zip(data_sorted, expected_sorted):
        assert actual == expected, f"Mismatch in JSON output.\nExpected: {expected}\nGot: {actual}"


def test_zz_dynamic_dataset():
    employee_backup = open(EMPLOYEES_CSV, "rb").read()
    interaction_backup = open(INTERACTIONS_CSV, "rb").read()
    token = secrets.token_hex(6)
    domain = token + ".example"
    emails = [f"{prefix}@{domain}" for prefix in ("aa", "bb", "cc", "dd", "ee", "ff", "gg")]
    departments = [f"Alpha-{token}", f"Beta-{token}", f"Gamma-{token}"]

    employee_rows = [
        (emails[0], departments[0]), (emails[1], departments[0]), (emails[2], departments[0]),
        (emails[3], departments[1]), (emails[4], departments[1]),
        (emails[5], departments[2]), (emails[6], departments[2]),
    ]
    interaction_rows = [
        ("2042-01-01", emails[6], emails[0], "email", 2),
        ("2042-01-02", emails[6], emails[0], "meeting", 3),
        ("2042-01-03", emails[1], emails[0], "code_review", 1),
        ("2042-01-04", emails[0], emails[1], "meeting", 5),
        ("2042-01-05", emails[3], emails[1], "email", 3),
        ("2042-01-06", emails[4], emails[2], "email", 1),
        ("2042-01-07", emails[0], emails[3], "code_review", 4),
        ("2042-01-08", emails[1], emails[4], "meeting", 10),
        ("2042-01-09", emails[2], emails[5], "email", 7),
    ]

    try:
        with open(EMPLOYEES_CSV, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["email", "department"])
            writer.writerows(employee_rows)
        with open(INTERACTIONS_CSV, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "actor_email", "target_email", "interaction_type", "metric_value"])
            writer.writerows(interaction_rows)

        run_script()
        conn = sqlite3.connect(DB_PATH)
        assert_loaded_csv_tables(conn, EMPLOYEES_CSV, INTERACTIONS_CSV)
        assert_complete_graph(conn, INTERACTIONS_CSV)
        conn.close()
        assert_json_matches(EMPLOYEES_CSV, INTERACTIONS_CSV)

        with open(TRACE_PATH, encoding="utf-8") as f:
            trace = f.read()
        assert re.search(r"\bWITH\b[\s\S]*\bRANK\s*\(\s*\)\s*OVER\s*\([\s\S]*\bPARTITION\s+BY\b", trace, re.I), \
            "The required CTE/window query was not executed for the dynamic dataset."
    finally:
        with open(EMPLOYEES_CSV, "wb") as f:
            f.write(employee_backup)
        with open(INTERACTIONS_CSV, "wb") as f:
            f.write(interaction_backup)
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
