#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

HOME = Path('/home/user')
SCRIPT = HOME / 'query_pipeline.py'
REPORT = HOME / 'report.json'
DB = HOME / 'company.db'
RDF = HOME / 'knowledge.ttl'
SCHEMA = HOME / 'schema.json'
TRACE = Path('/tmp/query_pipeline_trace.jsonl')
INSTRUMENT = Path('/tmp/pipeline_instrument')

ORIGINAL_EXPECTED = [
    {
        'project_name': 'Apollo',
        'lead_name': 'Alice',
        'department_name': 'Engineering',
        'direct_reports': 2,
        'risk_level': 'High',
    },
    {
        'project_name': 'Hermes',
        'lead_name': 'Diana',
        'department_name': 'HR',
        'direct_reports': 1,
        'risk_level': 'Low',
    },
]

SITE_CUSTOMIZE = r'''
import json
import os

TRACE = os.environ.get('PIPELINE_TRACE')

def record(kind, **fields):
    if not TRACE:
        return
    try:
        with open(TRACE, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'kind': kind, **fields}, default=repr) + '\n')
    except Exception:
        pass

try:
    import sqlite3
    _connect = sqlite3.connect
    def traced_connect(*args, **kwargs):
        conn = _connect(*args, **kwargs)
        try:
            conn.set_trace_callback(lambda statement: record('sql', statement=statement))
        except Exception:
            pass
        return conn
    sqlite3.connect = traced_connect
except Exception:
    pass

try:
    import rdflib
    _graph_query = rdflib.Graph.query
    def traced_graph_query(self, *args, **kwargs):
        binding = kwargs.get('initBindings')
        if binding is None and len(args) > 4:
            binding = args[4]
        record('sparql', query=repr(args[0]) if args else '', bindings=repr(binding))
        return _graph_query(self, *args, **kwargs)
    rdflib.Graph.query = traced_graph_query
except Exception:
    pass

try:
    import jsonschema
    _validate = jsonschema.validate
    def traced_validate(*args, **kwargs):
        record('jsonschema.validate')
        return _validate(*args, **kwargs)
    jsonschema.validate = traced_validate

    for class_name in ('Draft3Validator', 'Draft4Validator', 'Draft6Validator',
                       'Draft7Validator', 'Draft201909Validator', 'Draft202012Validator'):
        cls = getattr(jsonschema, class_name, None)
        if cls is None:
            continue
        for method_name in ('validate', 'iter_errors'):
            try:
                original = getattr(cls, method_name)
                def make_wrapper(original_method, label):
                    def wrapper(self, *args, **kwargs):
                        record(label)
                        return original_method(self, *args, **kwargs)
                    return wrapper
                setattr(cls, method_name, make_wrapper(
                    original, 'jsonschema.' + class_name + '.' + method_name))
            except Exception:
                pass
except Exception:
    pass
'''


def install_instrumentation():
    INSTRUMENT.mkdir(exist_ok=True)
    (INSTRUMENT / 'sitecustomize.py').write_text(SITE_CUSTOMIZE, encoding='utf-8')


def run_pipeline():
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()
    TRACE.unlink(missing_ok=True)
    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = str(INSTRUMENT) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['PIPELINE_TRACE'] = str(TRACE)
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(HOME),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'query_pipeline.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert REPORT.is_file(), f'Expected output file missing after execution: {REPORT}'
    try:
        return json.loads(REPORT.read_text(encoding='utf-8'))
    except json.JSONDecodeError as exc:
        pytest.fail(f'Invalid JSON in {REPORT}: {exc}')


def assert_report(data, expected):
    assert isinstance(data, list), 'The report should be a JSON array (list).'
    assert len(data) == len(expected), (
        f'Expected exactly {len(expected)} records in the report, found {len(data)}.'
    )
    sorted_data = sorted(data, key=lambda record: record.get('project_name', ''))
    sorted_expected = sorted(expected, key=lambda record: record.get('project_name', ''))
    for actual, wanted in zip(sorted_data, sorted_expected):
        assert actual == wanted, f'Record mismatch. Expected {wanted}, but got {actual}'


def read_trace():
    assert TRACE.is_file(), 'The executed pipeline produced no instrumentation trace.'
    events = []
    for line in TRACE.read_text(encoding='utf-8').splitlines():
        if line.strip():
            events.append(json.loads(line))
    return events


def write_mutated_fixtures(token):
    if DB.exists():
        DB.unlink()
    conn = sqlite3.connect(DB)
    try:
        conn.executescript(f'''
        CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER);
        CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT, lead_id INTEGER);
        INSERT INTO departments VALUES (7, 'Research-{token}'), (8, 'Operations-{token}');
        INSERT INTO employees VALUES (301, 'Lead-A-{token}', NULL, 7);
        INSERT INTO employees VALUES (302, 'Report-A1-{token}', 301, 7);
        INSERT INTO employees VALUES (303, 'Report-A2-{token}', 301, 7);
        INSERT INTO employees VALUES (304, 'Lead-B-{token}', NULL, 8);
        INSERT INTO employees VALUES (305, 'Report-B1-{token}', 304, 8);
        INSERT INTO employees VALUES (306, 'NoReports-{token}', NULL, 7);
        INSERT INTO projects VALUES (2001, 'Orion-{token}', 301);
        INSERT INTO projects VALUES (2002, 'O''Brien-{token}', 304);
        INSERT INTO projects VALUES (2003, 'Excluded-{token}', 306);
        ''')
        conn.commit()
    finally:
        conn.close()

    RDF.write_text(f'''@prefix ex: <http://example.org/> .
ex:a ex:projectName "Orion-{token}" ; ex:riskLevel "Critical-{token}" .
ex:b ex:projectName "O'Brien-{token}" ; ex:riskLevel "Guarded-{token}" .
ex:c ex:projectName "Excluded-{token}" ; ex:riskLevel "Unused-{token}" .
''', encoding='utf-8')

    schema = {
        '$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': {
            'project_name': {'type': 'string'},
            'lead_name': {'type': 'string'},
            'department_name': {'type': 'string'},
            'direct_reports': {'type': 'integer', 'minimum': 1},
            'risk_level': {'type': 'string'},
        },
        'required': ['project_name', 'lead_name', 'department_name', 'direct_reports', 'risk_level'],
        'additionalProperties': False,
    }
    SCHEMA.write_text(json.dumps(schema), encoding='utf-8')

    return [
        {
            'project_name': f'Orion-{token}',
            'lead_name': f'Lead-A-{token}',
            'department_name': f'Research-{token}',
            'direct_reports': 2,
            'risk_level': f'Critical-{token}',
        },
        {
            'project_name': f"O'Brien-{token}",
            'lead_name': f'Lead-B-{token}',
            'department_name': f'Operations-{token}',
            'direct_reports': 1,
            'risk_level': f'Guarded-{token}',
        },
    ]


def test_pipeline_exists_executes_and_uses_required_systems():
    assert SCRIPT.is_file(), f'Expected Python script missing: {SCRIPT}'
    assert not SCRIPT.is_symlink(), 'query_pipeline.py must be a regular submitted script, not a symlink.'
    py_compile.compile(str(SCRIPT), doraise=True)
    install_instrumentation()

    # Preserve the original verifier's assertions, but derive the report by executing the script.
    original_data = run_pipeline()
    assert_report(original_data, ORIGINAL_EXPECTED)

    backups = {path: path.read_bytes() for path in (DB, RDF, SCHEMA)}
    token = 'v9f3c1'
    try:
        mutated_expected = write_mutated_fixtures(token)
        mutated_data = run_pipeline()
        assert_report(mutated_data, mutated_expected)

        events = read_trace()
        sql_statements = [e.get('statement', '') for e in events if e.get('kind') == 'sql']
        relevant_sql = [s.upper() for s in sql_statements if s.lstrip().upper().startswith(('SELECT', 'WITH'))]
        assert relevant_sql, 'No SQL query was executed against the SQLite database.'
        assert any(
            'PROJECTS' in s and 'EMPLOYEES' in s and 'DEPARTMENTS' in s and
            'JOIN' in s and 'MANAGER_ID' in s and
            ('COUNT' in s or 'GROUP BY' in s or s.count('SELECT') > 1)
            for s in relevant_sql
        ), 'The executed SQL did not perform the required joins and direct-report aggregation/subquery.'

        sparql_events = [e for e in events if e.get('kind') == 'sparql']
        assert len(sparql_events) >= len(mutated_expected), 'SPARQL was not queried for every qualifying SQL row.'
        for record in mutated_expected:
            name = record['project_name']
            assert any(
                e.get('bindings') not in (None, 'None') and name in e.get('bindings', '')
                for e in sparql_events
            ), f'No parameterized SPARQL binding was used for project {name!r}.'

        schema_events = [e for e in events if str(e.get('kind', '')).startswith('jsonschema.')]
        assert len(schema_events) >= len(mutated_expected), 'jsonschema did not validate every output record.'
    finally:
        for path, content in backups.items():
            path.write_bytes(content)

    # Leave the requested report corresponding to the original supplied fixtures.
    restored_data = run_pipeline()
    assert_report(restored_data, ORIGINAL_EXPECTED)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
