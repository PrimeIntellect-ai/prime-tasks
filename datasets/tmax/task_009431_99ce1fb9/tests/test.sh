#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile


def test_db_updated_correctly():
    db_path = "/home/user/graph.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    rows = conn.execute("SELECT id, weight FROM nodes ORDER BY id").fetchall()
    conn.close()
    weights = {row[0]: row[1] for row in rows}

    expected_weights = {
        'ROOT': 10,
        'A': 35,
        'B': 45,
        'C': 55,
        'D': 65,
        'E': 60
    }
    for node, expected in expected_weights.items():
        assert weights.get(node) == expected, \
            f"Node {node} expected weight {expected}, got {weights.get(node)}"


def _resolved_string(node, string_assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return string_assignments.get(node.id)
    return None


def test_python_script_fixed():
    script_path = "/home/user/concurrent_update.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "?" in content, "The script should use parameterized queries (e.g., '?') instead of string formatting."
    assert "f\"UPDATE" not in content and "f'UPDATE" not in content, \
        "The script should not use f-strings for the UPDATE query."
    assert "sort" in content, \
        "The script should sort the nodes_to_update list before iterating to prevent deadlocks."

    tree = ast.parse(content, filename=script_path)
    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "update_nodes"]
    assert funcs, "The update_nodes function is missing."
    fn = funcs[0]

    string_assignments = {}
    sorted_names = set()
    sorted_in_place = set()
    for node in ast.walk(fn):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                for target in targets:
                    if isinstance(target, ast.Name):
                        string_assignments[target.id] = value.value
            if (isinstance(value, ast.Call) and isinstance(value.func, ast.Name)
                    and value.func.id == "sorted" and value.args):
                for target in targets:
                    if isinstance(target, ast.Name):
                        sorted_names.add(target.id)
        if (isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                and isinstance(node.value.func, ast.Attribute)
                and node.value.func.attr == "sort"
                and isinstance(node.value.func.value, ast.Name)):
            sorted_in_place.add(node.value.func.value.id)

    sorted_loops = []
    for node in ast.walk(fn):
        if not isinstance(node, ast.For):
            continue
        iterator = node.iter
        is_sorted = (
            isinstance(iterator, ast.Call)
            and isinstance(iterator.func, ast.Name)
            and iterator.func.id == "sorted"
        ) or (
            isinstance(iterator, ast.Name)
            and (iterator.id in sorted_names or iterator.id in sorted_in_place)
        )
        if is_sorted:
            sorted_loops.append(node)
    assert sorted_loops, "Updates must iterate over a lexicographically sorted node list."

    parameterized_update_in_sorted_loop = False
    for loop in sorted_loops:
        for node in ast.walk(loop):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr in ("execute", "executemany") and node.args):
                continue
            sql = _resolved_string(node.args[0], string_assignments)
            if sql and "UPDATE" in sql.upper() and "?" in sql and len(node.args) >= 2:
                parameterized_update_in_sorted_loop = True
    assert parameterized_update_in_sorted_loop, \
        "The sorted update loop must execute an UPDATE using placeholders and a separate parameter sequence."

    thread_calls = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
        and n.func.attr == "Thread"
    ]
    assert len(thread_calls) >= 2, "The script must retain the concurrent threaded updates."


def test_python_script_executes_updates_in_sorted_order():
    source = "/home/user/concurrent_update.py"
    with tempfile.TemporaryDirectory() as td:
        copied_script = os.path.join(td, "concurrent_update.py")
        shutil.copyfile(source, copied_script)
        db_path = os.path.join(td, "graph.db")

        conn = sqlite3.connect(db_path)
        conn.executescript("""
            CREATE TABLE nodes (id TEXT PRIMARY KEY, weight INTEGER);
            CREATE TABLE edges (source TEXT, target TEXT);
            INSERT INTO nodes VALUES
                ('ROOT',10),('A',20),('B',30),('C',40),('D',50),('E',60);
            CREATE TABLE update_log (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT,
                delta INTEGER
            );
            CREATE TRIGGER log_node_update AFTER UPDATE OF weight ON nodes
            BEGIN
                INSERT INTO update_log(id, delta) VALUES (NEW.id, NEW.weight - OLD.weight);
            END;
        """)
        conn.commit()
        conn.close()

        completed = subprocess.run(
            ["python3", copied_script], cwd=td, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert completed.returncode == 0, \
            f"concurrent_update.py failed:\n{completed.stdout}\n{completed.stderr}"

        conn = sqlite3.connect(db_path)
        weights = dict(conn.execute("SELECT id, weight FROM nodes").fetchall())
        log = conn.execute("SELECT id, delta FROM update_log ORDER BY seq").fetchall()
        conn.close()

        assert weights == {
            'ROOT': 10, 'A': 35, 'B': 45, 'C': 55, 'D': 65, 'E': 60
        }, f"Executing the script on a fresh database produced incorrect weights: {weights}"
        assert len(log) == 8, f"Expected exactly eight individual updates, got {log}"

        chunks = [log[:4], log[4:]]
        assert all([row[0] for row in chunk] == ['A', 'B', 'C', 'D'] for chunk in chunks), \
            f"Each transaction must update IDs in sorted order; observed {log}"
        assert {tuple(row[1] for row in chunk) for chunk in chunks} == {(5, 5, 5, 5), (10, 10, 10, 10)}, \
            f"Expected one +5 and one +10 transaction; observed {log}"


def _execute_single_integer_query(sql, db_path):
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA query_only = ON")
    try:
        cursor = conn.execute(sql)
        rows = cursor.fetchall()
    finally:
        conn.close()
    assert len(rows) == 1 and len(rows[0]) == 1, \
        f"analyze.sql must return exactly one row and one column, got {rows}"
    assert isinstance(rows[0][0], int) and not isinstance(rows[0][0], bool), \
        f"analyze.sql must return a single integer, got {rows[0][0]!r}"
    return rows[0][0]


def _reachable_total(db_path):
    conn = sqlite3.connect(db_path)
    weights = dict(conn.execute("SELECT id, weight FROM nodes").fetchall())
    edges = conn.execute("SELECT source, target FROM edges").fetchall()
    conn.close()
    children = {}
    for source, target in edges:
        children.setdefault(source, []).append(target)
    seen = set()
    pending = ['ROOT']
    while pending:
        node = pending.pop()
        if node in seen:
            continue
        seen.add(node)
        pending.extend(children.get(node, []))
    return sum(weights[node] for node in seen)


def test_sql_script_exists_recursive_and_executes():
    sql_path = "/home/user/analyze.sql"
    assert os.path.isfile(sql_path), f"SQL script {sql_path} is missing."

    with open(sql_path, 'r') as f:
        sql = f.read()
    upper = sql.upper()

    # Preserve the original source assertions.
    assert "WITH RECURSIVE" in upper or "WITH " in upper, \
        "The SQL script should use a Recursive Common Table Expression (CTE)."
    assert "ROOT" in upper, "The SQL script should start from the 'ROOT' node."
    assert "WITH RECURSIVE" in upper, "The SQL script must declare a recursive CTE."

    actual_db = "/home/user/graph.db"
    expected_actual = _reachable_total(actual_db)
    assert _execute_single_integer_query(sql, actual_db) == expected_actual

    # Exercise the submitted query on a different, deeper graph so a hardcoded
    # result or fixed list of the original node IDs cannot pass.
    with tempfile.TemporaryDirectory() as td:
        db_path = os.path.join(td, "alternate.db")
        conn = sqlite3.connect(db_path)
        conn.executescript("""
            CREATE TABLE nodes (id TEXT PRIMARY KEY, weight INTEGER);
            CREATE TABLE edges (source TEXT, target TEXT);
            INSERT INTO nodes VALUES
              ('ROOT',3),('N1',5),('N2',7),('N3',11),('N4',13),
              ('N5',17),('BRANCH',19),('ISOLATED',1000);
            INSERT INTO edges VALUES
              ('ROOT','N1'),('N1','N2'),('N2','N3'),('N3','N4'),
              ('N4','N5'),('N2','BRANCH');
        """)
        conn.commit()
        conn.close()
        expected = _reachable_total(db_path)
        assert _execute_single_integer_query(sql, db_path) == expected


def test_result_file():
    result_path = "/home/user/root_total_weight.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} is missing."

    with open(result_path, 'r') as f:
        content = f.read().strip()
    assert content == "270", f"Expected the total weight to be 270, but got '{content}'."

    with open(result_path, 'rb') as f:
        raw = f.read()
    assert re.fullmatch(rb"270(?:\n)?", raw), \
        "The result file must contain only the single integer result."

    expected = _reachable_total("/home/user/graph.db")
    with open("/home/user/analyze.sql", "r") as f:
        query_result = _execute_single_integer_query(f.read(), "/home/user/graph.db")
    assert int(content) == expected == query_result, \
        "The saved result must match the independently derived graph total and analyze.sql output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
