#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPT = Path('/home/user/query_graph.py')
DATA = Path('/home/user/graph_data.csv')
RESULTS = Path('/home/user/pattern_results.txt')


def read_results():
    assert RESULTS.is_file(), f'The output file {RESULTS} is missing.'
    with RESULTS.open() as f:
        return [line.strip() for line in f if line.strip()]


def expected_for(csv_path, first_person, second_person):
    with open(csv_path, newline='') as f:
        rows = list(csv.DictReader(f))
    employers = {
        row['object'] for row in rows
        if row['subject'] == first_person and row['predicate'] == 'works_for'
    }
    purchased_products = {
        row['object'] for row in rows
        if row['subject'] == second_person and row['predicate'] == 'purchased'
    }
    producers = {
        row['object'] for row in rows
        if row['subject'] in purchased_products and row['predicate'] == 'produced_by'
    }
    return sorted(employers & producers)


def run_query(first_person, second_person, csv_path=DATA):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), first_person, second_person],
        cwd='/home/user', text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, (
        f'query_graph.py failed for {first_person!r}, {second_person!r}: '
        f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    )
    assert proc.stdout.strip() == '', 'Results must be written strictly to pattern_results.txt, not stdout.'
    assert read_results() == expected_for(csv_path, first_person, second_person)


def test_query_graph_script_exists():
    """Test that the query_graph.py script was created."""
    assert os.path.isfile(SCRIPT), f'The script {SCRIPT} is missing.'


def test_pattern_results_content():
    """Test that pattern_results.txt contains the correct output."""
    assert os.path.isfile(RESULTS), f'The output file {RESULTS} is missing.'
    lines = read_results()
    expected_lines = ['Initech', 'TechCorp']
    assert lines == expected_lines, (
        f'The contents of {RESULTS} are incorrect.\n'
        f'Expected: {expected_lines}\nGot: {lines}'
    )


def test_uses_temporary_sqlite_and_parameterized_query():
    source = SCRIPT.read_text()
    tree = ast.parse(source, filename=str(SCRIPT))

    imports_sqlite = any(
        (isinstance(node, ast.Import) and any(a.name == 'sqlite3' for a in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == 'sqlite3')
        for node in ast.walk(tree)
    )
    assert imports_sqlite, 'The script must use SQLite.'

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value

    connect_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'connect'
    ]
    assert connect_calls, 'The script must create an SQLite connection.'

    def literal_text(node):
        if isinstance(node, ast.Name) and node.id in assignments:
            return literal_text(assignments[node.id])
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.JoinedStr):
            return ''.join(
                part.value if isinstance(part, ast.Constant) and isinstance(part.value, str) else ''
                for part in node.values
            )
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = literal_text(node.left), literal_text(node.right)
            return None if left is None or right is None else left + right
        return None

    temporary_connection = False
    for call in connect_calls:
        arg = call.args[0] if call.args else None
        text = literal_text(arg) if arg is not None else None
        if text in (':memory:', ''):
            temporary_connection = True
        elif arg is not None and any(
            token in ast.unparse(arg).lower() for token in ('temp', 'namedtemporaryfile')
        ):
            temporary_connection = True
    assert temporary_connection, 'SQLite must be temporary or in-memory.'

    parameterized = False
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
            continue
        if node.func.attr not in ('execute', 'executemany') or not node.args:
            continue
        sql = literal_text(node.args[0])
        has_parameters = len(node.args) >= 2 or any(
            kw.arg in ('parameters', 'params') for kw in node.keywords
        )
        has_placeholder = bool(sql and ('?' in sql or re.search(r'(?<!:):[A-Za-z_]\w*', sql)))
        if has_parameters and has_placeholder and sql and 'select' in sql.lower():
            parameterized = True
            break
    assert parameterized, 'The graph SELECT must be executed with SQL placeholders and separate parameters.'


def test_cli_and_multiple_queries():
    original = DATA.read_bytes()
    try:
        for args in ([], ['Alice'], ['Alice', 'Bob', 'extra']):
            proc = subprocess.run(
                [sys.executable, str(SCRIPT), *args], cwd='/home/user',
                text=True, capture_output=True, timeout=10
            )
            assert proc.returncode != 0, f'The script must reject {len(args)} command-line arguments.'

        for first, second in [
            ('Alice', 'Bob'), ('Eve', 'Bob'), ('Alice', 'Dave'),
            ('Bob', 'Alice'), ('Charlie', 'Alice'), ('Nobody', 'Bob'),
            ('Alice', 'Nobody')
        ]:
            run_query(first, second)

        with DATA.open('a', newline='') as f:
            writer = csv.writer(f)
            writer.writerows([
                ["O'Brien", 'works_for', 'QuoteCo'],
                ['QuotedProduct', 'produced_by', 'QuoteCo'],
                ["Mallory' OR '1'='1", 'purchased', 'QuotedProduct'],
                ['OtherPerson', 'works_for', 'DecoyCo'],
                ['DecoyProduct', 'produced_by', 'DecoyCo'],
                ['OtherBuyer', 'purchased', 'DecoyProduct'],
            ])
        run_query("O'Brien", "Mallory' OR '1'='1")
    finally:
        DATA.write_bytes(original)
        subprocess.run(
            [sys.executable, str(SCRIPT), 'Alice', 'Bob'],
            cwd='/home/user', text=True, capture_output=True, timeout=10
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
