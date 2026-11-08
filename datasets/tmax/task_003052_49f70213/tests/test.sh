#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

SCRIPT = '/home/user/kg_analyzer.py'
CSV_PATH = '/home/user/interactions.csv'
DB_PATH = '/home/user/kg.db'
OUTPUT_PATH = '/home/user/treatment_candidates.txt'


def _remove_generated_files():
    for path in (DB_PATH, OUTPUT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def _run_script(disease):
    result = subprocess.run(
        ['python3', SCRIPT, disease],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'kg_analyzer.py failed for argument {disease!r}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def _read_output():
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'
    with open(OUTPUT_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def _constant_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return assignments.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _constant_string(node.left, assignments)
        right = _constant_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    return None


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_submission():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist.'

    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    token = uuid.uuid4().hex
    disease = f"Disease_{token}'quoted"
    other_disease = f'OtherDisease_{token}'
    drug_a = f'AlphaDrug_{token}'
    drug_z = f'ZuluDrug_{token}'
    wrong_disease_drug = f'WrongDiseaseDrug_{token}'
    wrong_relation_drug = f'WrongRelationDrug_{token}'
    wrong_type = f'NotADrug_{token}'
    gene_a = f'GeneA_{token}'
    gene_z = f'GeneZ_{token}'
    gene_other = f'GeneOther_{token}'
    gene_wrong_relation = f'GeneWrongRelation_{token}'
    gene_wrong_type = f'GeneWrongType_{token}'

    rows = [
        f'{drug_z},Drug,targets,{gene_z},Gene',
        f'{gene_z},Gene,associated_with,{disease},Disease',
        f'{wrong_disease_drug},Drug,targets,{gene_other},Gene',
        f'{gene_other},Gene,associated_with,{other_disease},Disease',
        f'{drug_a},Drug,targets,{gene_a},Gene',
        f'{gene_a},Gene,associated_with,{disease},Disease',
        f'{wrong_relation_drug},Drug,targets,{gene_wrong_relation},Gene',
        f'{gene_wrong_relation},Gene,interacts_with,{disease},Disease',
        f'{wrong_type},Protein,targets,{gene_wrong_type},Gene',
        f'{gene_wrong_type},Gene,associated_with,{disease},Disease',
    ]

    try:
        with open(CSV_PATH, 'w', newline='') as f:
            f.write('\n'.join(rows) + '\n')

        _remove_generated_files()
        _run_script(disease)

        assert _read_output() == sorted([drug_a, drug_z]), (
            'The script did not derive the sorted candidates from the supplied CSV '
            'and command-line disease argument.'
        )

        assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} does not exist.'
        conn = sqlite3.connect(DB_PATH)
        try:
            tables = {
                row[0] for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
            assert 'nodes' in tables, "The 'nodes' table is missing from the database."
            assert 'edges' in tables, "The 'edges' table is missing from the database."

            node_rows = conn.execute('SELECT * FROM nodes').fetchall()
            edge_rows = conn.execute('SELECT * FROM edges').fetchall()
            node_values = {str(value) for row in node_rows for value in row if value is not None}
            edge_values = {str(value) for row in edge_rows for value in row if value is not None}

            expected_entities = {
                drug_a, drug_z, wrong_disease_drug, wrong_relation_drug, wrong_type,
                gene_a, gene_z, gene_other, gene_wrong_relation, gene_wrong_type,
                disease, other_disease,
            }
            assert expected_entities <= node_values, 'The CSV entities were not populated into nodes.'
            assert {'Drug', 'Gene', 'Disease', 'Protein'} <= node_values, (
                'The CSV entity types were not populated into nodes.'
            )
            assert len(edge_rows) >= len(rows), 'The CSV relationships were not populated into edges.'
            assert {'targets', 'associated_with', 'interacts_with'} <= edge_values, (
                'The CSV relation types were not populated into edges.'
            )
        finally:
            conn.close()
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        _remove_generated_files()
        _run_script('Asthma')

    yield


def test_kg_analyzer_script_exists():
    """Test that the kg_analyzer.py script exists."""
    assert os.path.isfile('/home/user/kg_analyzer.py'), "/home/user/kg_analyzer.py does not exist."


def test_query_is_parameterized():
    """Check that the candidate SELECT is issued with SQL parameters."""
    with open(SCRIPT, 'r') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = _constant_string(node.value, assignments)
            if value is not None:
                assignments[node.targets[0].id] = value

    parameterized_select = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in {'execute', 'read_sql', 'read_sql_query'} or not node.args:
            continue
        query = _constant_string(node.args[0], assignments)
        if query is None or 'SELECT' not in query.upper():
            continue
        has_placeholder = '?' in query or re.search(r'[:@$][A-Za-z_][A-Za-z0-9_]*', query)
        has_parameters = len(node.args) >= 2 or any(
            keyword.arg in {'params', 'parameters'} for keyword in node.keywords
        )
        if has_placeholder and has_parameters:
            parameterized_select = True
            break

    assert parameterized_select, (
        'No parameterized SELECT query was found; the disease argument must be passed '
        'separately from the SQL text.'
    )


def test_sqlite_db_exists_and_schema():
    """Test that the kg.db database exists, has nodes/edges tables, and contains indexes."""
    db_path = '/home/user/kg.db'
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check for nodes and edges tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = {row[0] for row in cursor.fetchall()}
    assert 'nodes' in tables, "The 'nodes' table is missing from the database."
    assert 'edges' in tables, "The 'edges' table is missing from the database."

    # Check for indexes
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No custom indexes found in the database. An index strategy is required."

    # Check that at least one index is on the edges or nodes table
    indexed_tables = {row[1] for row in indexes}
    assert 'edges' in indexed_tables or 'nodes' in indexed_tables, "No indexes found on the 'edges' or 'nodes' tables."

    conn.close()


def test_treatment_candidates_output():
    """Test that the treatment_candidates.txt file exists and contains the correct output."""
    output_path = '/home/user/treatment_candidates.txt'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_drugs = ['Albuterol', 'Fluticasone', 'Omalizumab']

    assert lines == expected_drugs, f"Expected output {expected_drugs}, but got {lines}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
