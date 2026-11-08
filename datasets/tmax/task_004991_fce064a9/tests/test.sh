#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import runpy
import secrets
import sqlite3
import stat
from pathlib import Path

import pytest
import rdflib
from rdflib.namespace import RDF

SCRIPT = Path('/home/user/generate_report.py')
CSV_PATH = Path('/home/user/compliance_report.csv')
DB_PATH = Path('/home/user/audit_logs.db')
GRAPH_PATH = Path('/home/user/system_graph.ttl')
HIGH_RISK = rdflib.URIRef('http://example.org/ontology#HighRiskSystem')


def read_report():
    assert CSV_PATH.exists(), f"Output file {CSV_PATH} does not exist."
    with CSV_PATH.open('r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        return [[cell.strip() for cell in row] for row in reader if row]


def execute_script():
    if CSV_PATH.exists():
        CSV_PATH.unlink()
    try:
        runpy.run_path(str(SCRIPT), run_name='__main__')
    except SystemExit as exc:
        assert exc.code in (None, 0), f"generate_report.py exited with status {exc.code}"
    assert CSV_PATH.exists(), 'generate_report.py did not create compliance_report.csv'


def derive_expected():
    graph = rdflib.Graph()
    graph.parse(str(GRAPH_PATH), format='turtle')
    systems = sorted({str(subject).rsplit('/', 1)[-1] for subject in graph.subjects(RDF.type, HIGH_RISK)})

    rows = []
    if systems:
        placeholders = ','.join('?' for _ in systems)
        conn = sqlite3.connect(str(DB_PATH))
        try:
            rows = conn.execute(
                f'''SELECT e.department, a.system_name, COUNT(*)
                    FROM employees AS e
                    JOIN access_events AS a ON e.id = a.emp_id
                    WHERE a.system_name IN ({placeholders})
                    GROUP BY e.department, a.system_name
                    HAVING COUNT(*) > 0
                    ORDER BY e.department, a.system_name''',
                systems,
            ).fetchall()
        finally:
            conn.close()
    return [['department', 'system_name', 'access_count']] + [
        [department, system_name, str(count)] for department, system_name, count in rows
    ]


def test_script_generates_report_and_handles_changed_inputs(monkeypatch):
    assert SCRIPT.exists(), f"Required script {SCRIPT} does not exist."
    assert not SCRIPT.is_symlink(), f"{SCRIPT} must be a Python source file, not a symlink."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f"{SCRIPT} is not a regular file."

    source = SCRIPT.read_text(encoding='utf-8')
    compile(source, str(SCRIPT), 'exec')
    assert 'HighRiskSystem' in source, 'The script does not contain a HighRiskSystem SPARQL query.'

    original_db = DB_PATH.read_bytes()
    original_graph = GRAPH_PATH.read_bytes()
    original_csv = CSV_PATH.read_bytes() if CSV_PATH.exists() else None

    parse_calls = []
    query_calls = []
    original_parse = rdflib.Graph.parse
    original_query = rdflib.Graph.query

    def tracked_parse(self, *args, **kwargs):
        parse_calls.append((args, kwargs))
        return original_parse(self, *args, **kwargs)

    def tracked_query(self, *args, **kwargs):
        query_calls.append((args, kwargs))
        return original_query(self, *args, **kwargs)

    monkeypatch.setattr(rdflib.Graph, 'parse', tracked_parse)
    monkeypatch.setattr(rdflib.Graph, 'query', tracked_query)

    try:
        # Preserve the original verifier's exact expected-output assertion, but
        # require the submitted program itself to produce the file first.
        execute_script()
        expected_rows = [
            ['department', 'system_name', 'access_count'],
            ['Finance', 'FIN-01', '2'],
            ['Finance', 'PRD-DB', '1'],
            ['IT', 'FIN-01', '1'],
            ['IT', 'PRD-DB', '2'],
        ]
        actual_rows = read_report()
        assert len(actual_rows) > 0, 'The compliance report CSV is empty.'
        assert actual_rows[0] == expected_rows[0], (
            f"CSV headers are incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}"
        )
        assert actual_rows == expected_rows, (
            'CSV data rows do not match the expected output or are incorrectly sorted.\n'
            f'Expected: {expected_rows}\nActual: {actual_rows}'
        )
        assert parse_calls, 'generate_report.py did not parse the RDF graph with rdflib.'
        assert query_calls, 'generate_report.py did not execute an rdflib SPARQL query.'

        # Change both data sources using unpredictable names. A hardcoded CSV or
        # hardcoded FIN-01/PRD-DB solution cannot satisfy this execution.
        token = secrets.token_hex(6)
        high_system = f'AUDIT-{token}'
        low_system = f'LOW-{token}'
        department = f'Dept-{token}'

        graph_text = GRAPH_PATH.read_text(encoding='utf-8')
        graph_text = graph_text.replace(
            'sys:FIN-01 a ex:HighRiskSystem',
            'sys:FIN-01 a ex:LowRiskSystem',
        )
        graph_text += (
            f'\n<http://example.org/systems/{high_system}> '
            'a <http://example.org/ontology#HighRiskSystem> .\n'
            f'<http://example.org/systems/{low_system}> '
            'a <http://example.org/ontology#LowRiskSystem> .\n'
        )
        GRAPH_PATH.write_text(graph_text, encoding='utf-8')

        conn = sqlite3.connect(str(DB_PATH))
        try:
            employee_id = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM employees').fetchone()[0]
            event_id = conn.execute('SELECT COALESCE(MAX(event_id), 0) + 1 FROM access_events').fetchone()[0]
            conn.execute(
                'INSERT INTO employees (id, name, department) VALUES (?, ?, ?)',
                (employee_id, f'Employee-{token}', department),
            )
            new_events = [
                (event_id, employee_id, high_system, '2026-01-01'),
                (event_id + 1, employee_id, high_system, '2026-01-02'),
                (event_id + 2, employee_id, high_system, '2026-01-03'),
                (event_id + 3, employee_id, 'PRD-DB', '2026-01-04'),
                (event_id + 4, employee_id, low_system, '2026-01-05'),
            ]
            conn.executemany(
                'INSERT INTO access_events (event_id, emp_id, system_name, access_date) VALUES (?, ?, ?, ?)',
                new_events,
            )
            conn.commit()
        finally:
            conn.close()

        execute_script()
        dynamic_expected = derive_expected()
        dynamic_actual = read_report()
        assert dynamic_actual == dynamic_expected, (
            'Report does not reflect the current RDF graph and correctly joined database.\n'
            f'Expected: {dynamic_expected}\nActual: {dynamic_actual}'
        )
    finally:
        DB_PATH.write_bytes(original_db)
        GRAPH_PATH.write_bytes(original_graph)
        if original_csv is None:
            if CSV_PATH.exists():
                CSV_PATH.unlink()
        else:
            CSV_PATH.write_bytes(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
