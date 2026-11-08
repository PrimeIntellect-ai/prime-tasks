#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pwd
import random
import re
import sqlite3
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/audit_pipeline.py"
DB_PATH = "/home/user/finances.db"
REPORT_PATH = "/home/user/compliance_report.json"


def _resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in assignments:
        return _resolve_string(assignments[node.id], assignments)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _resolve_string(node.left, assignments)
        right = _resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    return None


def _call_tail(call):
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def _create_database(rows):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "CREATE TABLE transactions ("
        "id INTEGER PRIMARY KEY, sender TEXT, receiver TEXT, "
        "amount REAL, tx_date DATETIME)"
    )
    conn.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", rows)
    conn.execute("CREATE INDEX idx_sender ON transactions(sender)")
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o666)


def _run_pipeline(rows):
    _create_database(rows)
    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass

    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        "audit_pipeline.py did not execute successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "The executed pipeline did not create compliance_report.json."
    with open(REPORT_PATH, "r", encoding="utf-8") as report:
        return json.load(report)


def _expected_report(rows):
    by_sender = {}
    adjacency = {}
    nodes = set()
    for tx_id, sender, receiver, amount, tx_date in rows:
        by_sender.setdefault(sender, []).append((tx_date, tx_id, float(amount)))
        adjacency.setdefault(sender, set()).add(receiver)
        nodes.update((sender, receiver))

    high_risk = set()
    for sender, transactions in by_sender.items():
        transactions.sort(key=lambda item: (item[0], item[1]))
        amounts = [item[2] for item in transactions]
        for index in range(len(amounts)):
            window = amounts[max(0, index - 2):index + 1]
            if sum(window) / len(window) > 50000:
                high_risk.add(sender)
                break

    cycles = set()
    for first in nodes:
        for second in adjacency.get(first, set()):
            if second == first:
                continue
            for third in adjacency.get(second, set()):
                if third in (first, second):
                    continue
                if first in adjacency.get(third, set()):
                    cycle = tuple(sorted((first, second, third)))
                    if set(cycle) & high_risk:
                        cycles.add(cycle)
    return [list(cycle) for cycle in sorted(cycles)]


def _canonical_rows():
    return [
        (1, 'Alice', 'David', 10000, '2023-01-01 10:00:00'),
        (2, 'Alice', 'Eve', 60000, '2023-01-02 10:00:00'),
        (3, 'Alice', 'Bob', 90000, '2023-01-03 10:00:00'),
        (4, 'Bob', 'Charlie', 5000, '2023-01-04 10:00:00'),
        (5, 'Charlie', 'Alice', 5000, '2023-01-05 10:00:00'),
        (6, 'Xander', 'Yasmine', 20000, '2023-01-06 10:00:00'),
        (7, 'Yasmine', 'Zane', 20000, '2023-01-07 10:00:00'),
        (8, 'Zane', 'Xander', 20000, '2023-01-08 10:00:00'),
        (9, 'Frank', 'Grace', 100000, '2023-01-09 10:00:00'),
        (10, 'Frank', 'Grace', 100000, '2023-01-10 10:00:00'),
        (11, 'Frank', 'Grace', 100000, '2023-01-11 10:00:00'),
    ]


@pytest.fixture(scope="module", autouse=True)
def canonical_run():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    _run_pipeline(_canonical_rows())


def test_audit_pipeline_script_exists():
    script_path = "/home/user/audit_pipeline.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_pipeline_contains_required_operations():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as script_file:
        source = script_file.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as error:
        pytest.fail(f"audit_pipeline.py is not valid Python: {error}")

    assignments = {}
    imported_networkx = False
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value
        elif isinstance(node, ast.Import):
            if any(alias.name == "networkx" for alias in node.names):
                imported_networkx = True
        elif isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("networkx"):
            imported_networkx = True
        elif isinstance(node, ast.Call):
            calls.append(node)

    sql_calls = []
    for call in calls:
        if not call.args:
            continue
        sql = _resolve_string(call.args[0], assignments)
        if sql is not None:
            sql_calls.append((call, sql))

    reindex_calls = [
        (call, sql) for call, sql in sql_calls
        if _call_tail(call) in {"execute", "executescript"}
        and re.search(r"\bREINDEX\b", sql, re.IGNORECASE)
    ]
    assert reindex_calls, "The script must execute SQLite's REINDEX command before querying."

    window_calls = []
    for call, sql in sql_calls:
        normalized = re.sub(r"\s+", " ", sql.replace('"', '').replace('`', '').replace('[', '').replace(']', '')).lower()
        required = (
            "avg(" in normalized,
            " over" in normalized,
            "partition by sender" in normalized,
            "order by tx_date" in normalized,
            "rows between 2 preceding and current row" in normalized,
        )
        if all(required):
            window_calls.append((call, sql, normalized))

    assert window_calls, (
        "The analytical SQL must use AVG as a window function partitioned by sender, "
        "ordered by tx_date, with ROWS BETWEEN 2 PRECEDING AND CURRENT ROW."
    )

    parameterized_window_calls = []
    for call, sql, normalized in window_calls:
        has_placeholder = "?" in sql or bool(re.search(r"(?<!:):[A-Za-z_]\w*", sql))
        has_parameters = len(call.args) >= 2 or any(keyword.arg == "params" for keyword in call.keywords)
        if has_placeholder and has_parameters and ">" in sql:
            parameterized_window_calls.append((call, sql))
    assert parameterized_window_calls, (
        "The window-function query must apply the strict threshold using bound SQL parameters, "
        "not a hardcoded or interpolated value."
    )

    first_reindex_line = min(call.lineno for call, _ in reindex_calls)
    first_window_line = min(call.lineno for call, _ in parameterized_window_calls)
    assert first_reindex_line < first_window_line, "REINDEX must be executed before the analytical query."

    call_names = {_call_tail(call) for call in calls}
    assert imported_networkx, "The script must use networkx to materialize and analyze the graph."
    assert "DiGraph" in call_names, "The script must materialize transactions in a networkx.DiGraph."
    assert "simple_cycles" in call_names, "The script must use networkx graph cycle analysis."


def test_compliance_report_exists():
    report_path = "/home/user/compliance_report.json"
    assert os.path.exists(report_path), f"The output file {report_path} does not exist."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."


def test_compliance_report_contents():
    report_path = "/home/user/compliance_report.json"
    assert os.path.exists(report_path), f"The output file {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_data = [["Alice", "Bob", "Charlie"]]

    assert isinstance(data, list), "The JSON root must be a list."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} flagged cycle(s), found {len(data)}."

    assert data == expected_data, (
        f"Expected {expected_data}, but got {data}. "
        "Ensure inner lists are sorted alphabetically and the outer list is sorted lexicographically."
    )


def test_pipeline_on_unseen_data():
    token = uuid.uuid4().hex
    names = {key: f"{key}_{token}" for key in (
        "HIGH", "B", "C", "J1", "J2", "EQ", "R", "S",
        "LOW", "L2", "L3", "N", "O", "F1", "F2", "F3", "F4"
    )}
    raw = [
        (names["HIGH"], names["J1"], 10000, "2042-01-01 09:00:00"),
        (names["HIGH"], names["J2"], 60000, "2042-01-02 09:00:00"),
        (names["HIGH"], names["B"], 90000, "2042-01-03 09:00:00"),
        (names["B"], names["C"], 1000, "2042-01-04 09:00:00"),
        (names["C"], names["HIGH"], 1000, "2042-01-05 09:00:00"),
        # Exactly 50,000 is not high risk, so this 3-cycle must not be reported.
        (names["EQ"], names["R"], 50000, "2042-02-01 09:00:00"),
        (names["R"], names["S"], 1000, "2042-02-02 09:00:00"),
        (names["S"], names["EQ"], 1000, "2042-02-03 09:00:00"),
        # A low-risk 3-cycle.
        (names["LOW"], names["L2"], 1000, "2042-03-01 09:00:00"),
        (names["L2"], names["L3"], 1000, "2042-03-02 09:00:00"),
        (names["L3"], names["LOW"], 1000, "2042-03-03 09:00:00"),
        # High-risk noise without a cycle.
        (names["N"], names["O"], 100000, "2042-04-01 09:00:00"),
        # A four-cycle must not be treated as a cycle of exactly length three.
        (names["F1"], names["F2"], 100000, "2042-05-01 09:00:00"),
        (names["F2"], names["F3"], 1000, "2042-05-02 09:00:00"),
        (names["F3"], names["F4"], 1000, "2042-05-03 09:00:00"),
        (names["F4"], names["F1"], 1000, "2042-05-04 09:00:00"),
    ]
    random.SystemRandom().shuffle(raw)
    rows = [
        (index, sender, receiver, amount, tx_date)
        for index, (sender, receiver, amount, tx_date) in enumerate(raw, 1)
    ]

    expected = _expected_report(rows)
    actual = _run_pipeline(rows)
    assert actual == expected, (
        f"Pipeline output on unseen transaction data was {actual}, expected {expected}. "
        "The report must be derived by the required window and graph analysis."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
