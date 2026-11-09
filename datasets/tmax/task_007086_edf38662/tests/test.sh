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
import uuid
import pytest

SCRIPT_PATH = "/home/user/etl_export.py"
GRAPH_IMPORT_PATH = "/home/user/graph_import.cypher"
INDEX_STRATEGY_PATH = "/home/user/index_strategy.cypher"
DB_PATH = "/home/user/company.db"


def run_export():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed when executed.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def setup_module(module):
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} was not created as a regular file."
    run_export()


def get_expected_hierarchy():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database {DB_PATH} missing.")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        WITH RECURSIVE hierarchy AS (
            SELECT emp_id, name, manager_id, 0 as level
            FROM employees WHERE manager_id IS NULL
            UNION ALL
            SELECT e.emp_id, e.name, e.manager_id, h.level + 1
            FROM employees e
            JOIN hierarchy h ON e.manager_id = h.emp_id
        )
        SELECT emp_id, name, manager_id, level FROM hierarchy
    """)
    rows = c.fetchall()
    conn.close()
    return rows


def test_graph_import_exists_and_ordered():
    assert os.path.exists(GRAPH_IMPORT_PATH), f"{GRAPH_IMPORT_PATH} was not created."

    with open(GRAPH_IMPORT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{GRAPH_IMPORT_PATH} is empty."

    seen_rel = False
    for i, line in enumerate(lines):
        if "MANAGES" in line or "MATCH" in line:
            seen_rel = True
        else:
            if seen_rel:
                pytest.fail(f"Line {i+1} ('{line}') appears to be a node creation, but occurs after a relationship creation.")


def test_graph_import_nodes():
    expected_data = get_expected_hierarchy()

    with open(GRAPH_IMPORT_PATH, "r") as f:
        content = f.read()

    for emp_id, name, manager_id, level in expected_data:
        pattern = rf"CREATE\s*\(\s*:\s*Employee\s*{{[^}}]*emp_id\s*:\s*['\"]{emp_id}['\"][^}}]*}}\s*\)"
        match = re.search(pattern, content)
        assert match is not None, f"Could not find node creation for emp_id '{emp_id}' in {GRAPH_IMPORT_PATH}"

        lines_with_emp = [line for line in content.split('\n') if re.search(pattern, line)]
        assert len(lines_with_emp) == 1, f"Expected exactly one node creation line for '{emp_id}'"
        line = lines_with_emp[0]

        assert re.search(rf"name\s*:\s*['\"]{re.escape(name)}['\"]", line), f"Node creation for '{emp_id}' missing correct name '{name}'"
        assert re.search(rf"level\s*:\s*{level}\b", line), f"Node creation for '{emp_id}' missing correct level {level}"


def test_graph_import_relationships():
    expected_data = get_expected_hierarchy()

    with open(GRAPH_IMPORT_PATH, "r") as f:
        content = f.read()

    for emp_id, name, manager_id, level in expected_data:
        if manager_id is None:
            continue
        lines = [line for line in content.split('\n') if "MANAGES" in line and manager_id in line and emp_id in line]
        assert len(lines) >= 1, f"Could not find relationship creation from manager '{manager_id}' to employee '{emp_id}'"


def test_index_strategy_cypher():
    assert os.path.exists(INDEX_STRATEGY_PATH), f"{INDEX_STRATEGY_PATH} was not created."

    with open(INDEX_STRATEGY_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"{INDEX_STRATEGY_PATH} must contain exactly two commands (one per line)."

    content = " ".join(lines).upper()
    assert "CONSTRAINT" in content, "Missing CONSTRAINT keyword in index strategy."
    assert "UNIQUE" in content, "Missing UNIQUE keyword in index strategy."
    assert "EMP_ID" in content, "Missing emp_id property in index strategy."
    assert "INDEX" in content, "Missing INDEX keyword in index strategy."
    assert "LEVEL" in content, "Missing level property in index strategy."
    assert "EMPLOYEE" in content, "Missing Employee label in index strategy."


def _constant_string(node, values):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return values.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _constant_string(node.left, values)
        right = _constant_string(node.right, values)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
                return None
            parts.append(value.value)
        return "".join(parts)
    return None


def test_script_executes_a_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    values = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            value = _constant_string(value_node, values)
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if value is not None:
                for target in targets:
                    if isinstance(target, ast.Name):
                        values[target.id] = value

    executed_sql = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr.lower() in {"execute", "executescript"} and node.args):
            sql = _constant_string(node.args[0], values)
            if sql is not None:
                executed_sql.append(sql)

    recursive_queries = [
        sql for sql in executed_sql
        if re.search(r"\bWITH\s+RECURSIVE\b", sql, re.I)
        and re.search(r"\bFROM\s+employees\b", sql, re.I)
        and re.search(r"\bUNION\s+ALL\b", sql, re.I)
        and re.search(r"\bmanager_id\b", sql, re.I)
    ]
    assert recursive_queries, (
        "The script must pass a recursive CTE over employees to sqlite3 execute()/executescript()."
    )


_QUOTED = r'(?:"((?:\\.|[^"\\])*)"|\'((?:\\.|[^\'\\])*)\')'
_PROP_RE = re.compile(r'([A-Za-z_]\w*)\s*:\s*(?:"((?:\\.|[^"\\])*)"|\'((?:\\.|[^\'\\])*)\'|(-?\d+))')
_NODE_RE = re.compile(r'^CREATE\s*\(\s*:\s*Employee\s*\{(.*)\}\s*\)\s*;$', re.I)
_REL_RE = re.compile(
    r'^MATCH\s*\(\s*([A-Za-z_]\w*)\s*:\s*Employee\s*\{\s*emp_id\s*:\s*' + _QUOTED +
    r'\s*\}\s*\)\s*,\s*\(\s*([A-Za-z_]\w*)\s*:\s*Employee\s*\{\s*emp_id\s*:\s*' + _QUOTED +
    r'\s*\}\s*\)\s*CREATE\s*\(\s*\1\s*\)\s*-\s*\[\s*:\s*MANAGES\s*\]\s*->\s*\(\s*\4\s*\)\s*;$', re.I)


def _parse_properties(body):
    matches = list(_PROP_RE.finditer(body))
    remainder = _PROP_RE.sub("", body)
    assert re.fullmatch(r"\s*(?:,\s*)*", remainder), f"Invalid Cypher property map: {{{body}}}"
    assert len(matches) == 3, f"Employee node must have exactly three properties: {{{body}}}"
    result = {}
    for match in matches:
        key = match.group(1).lower()
        assert key not in result, f"Duplicate property {key}"
        if match.group(4) is not None:
            result[key] = int(match.group(4))
        else:
            result[key] = match.group(2) if match.group(2) is not None else match.group(3)
    return result


def _parse_graph(expected_rows):
    assert os.path.isfile(GRAPH_IMPORT_PATH), f"{GRAPH_IMPORT_PATH} is not a regular file."
    with open(GRAPH_IMPORT_PATH, encoding="utf-8") as f:
        raw_lines = f.readlines()
    assert all(line.strip() for line in raw_lines), "graph_import.cypher must have exactly one nonblank statement per line."
    lines = [line.strip() for line in raw_lines]

    nodes = {}
    relationships = []
    relationship_phase = False
    for line in lines:
        node_match = _NODE_RE.fullmatch(line)
        if node_match:
            assert not relationship_phase, "Node creation statements must precede relationships."
            props = _parse_properties(node_match.group(1))
            assert set(props) == {"emp_id", "name", "level"}, "Employee nodes need exactly emp_id, name, and level."
            assert isinstance(props["emp_id"], str) and isinstance(props["name"], str)
            assert isinstance(props["level"], int), "level must be an unquoted integer."
            assert props["emp_id"] not in nodes, f"Duplicate node for {props['emp_id']}"
            nodes[props["emp_id"]] = (props["name"], props["level"])
            continue

        relationship_phase = True
        rel_match = _REL_RE.fullmatch(line)
        assert rel_match, f"Invalid relationship Cypher statement: {line}"
        manager = rel_match.group(2) if rel_match.group(2) is not None else rel_match.group(3)
        employee = rel_match.group(5) if rel_match.group(5) is not None else rel_match.group(6)
        relationships.append((manager, employee))

    expected_nodes = {emp: (name, level) for emp, name, manager, level in expected_rows}
    expected_relationships = {(manager, emp) for emp, name, manager, level in expected_rows if manager is not None}
    assert nodes == expected_nodes, f"Node statements differ from database hierarchy: {nodes!r}"
    assert len(relationships) == len(set(relationships)), "Duplicate MANAGES relationship statements found."
    assert set(relationships) == expected_relationships, (
        f"MANAGES relationships have wrong endpoints or direction: {relationships!r}"
    )


def _validate_index_file():
    assert os.path.isfile(INDEX_STRATEGY_PATH), f"{INDEX_STRATEGY_PATH} is not a regular file."
    with open(INDEX_STRATEGY_PATH, encoding="utf-8") as f:
        raw_lines = f.readlines()
    assert len(raw_lines) == 2 and all(line.strip() for line in raw_lines), (
        "index_strategy.cypher must contain exactly two nonblank lines."
    )
    lines = [line.strip() for line in raw_lines]

    constraint_patterns = [
        r'^CREATE\s+CONSTRAINT(?:\s+[A-Za-z_]\w*)?(?:\s+IF\s+NOT\s+EXISTS)?\s+FOR\s*\(\s*([A-Za-z_]\w*)\s*:\s*Employee\s*\)\s+REQUIRE\s+\1\.emp_id\s+IS\s+UNIQUE\s*;$',
        r'^CREATE\s+CONSTRAINT\s+ON\s*\(\s*([A-Za-z_]\w*)\s*:\s*Employee\s*\)\s+ASSERT\s+\1\.emp_id\s+IS\s+UNIQUE\s*;$',
    ]
    index_patterns = [
        r'^CREATE\s+INDEX(?:\s+[A-Za-z_]\w*)?(?:\s+IF\s+NOT\s+EXISTS)?\s+FOR\s*\(\s*([A-Za-z_]\w*)\s*:\s*Employee\s*\)\s+ON\s*\(\s*\1\.level\s*\)\s*;$',
        r'^CREATE\s+INDEX\s+ON\s*:\s*Employee\s*\(\s*level\s*\)\s*;$',
    ]
    assert any(re.fullmatch(p, lines[0], re.I) for p in constraint_patterns), (
        "First line must be valid Cypher creating a unique Employee.emp_id constraint."
    )
    assert any(re.fullmatch(p, lines[1], re.I) for p in index_patterns), (
        "Second line must be valid Cypher creating a standard Employee.level index."
    )


def test_strict_cypher_for_original_database():
    _parse_graph(get_expected_hierarchy())
    _validate_index_file()


def test_export_is_derived_from_database_when_executed():
    token = uuid.uuid4().hex[:10]
    rows = [
        (f"ROOT_{token}", f"Root {token}", None, 0),
        (f"LEFT_{token}", f"Left {token}", f"ROOT_{token}", 1),
        (f"RIGHT_{token}", f"Right {token}", f"ROOT_{token}", 1),
        (f"DEEP_{token}", f"Deep {token}", f"LEFT_{token}", 2),
    ]
    fd, backup = tempfile.mkstemp(prefix="company-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup)
    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        conn.execute("CREATE TABLE employees (emp_id TEXT PRIMARY KEY, name TEXT, manager_id TEXT)")
        conn.executemany(
            "INSERT INTO employees(emp_id, name, manager_id) VALUES (?, ?, ?)",
            [(emp, name, manager) for emp, name, manager, level in rows],
        )
        conn.commit()
        conn.close()
        run_export()
        _parse_graph(rows)
        _validate_index_file()
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.move(backup, DB_PATH)
        run_export()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
