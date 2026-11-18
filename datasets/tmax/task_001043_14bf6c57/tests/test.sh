#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

HOME = Path('/home/user')
DB_PATH = HOME / 'bom.db'
FINAL_BOM_PATH = HOME / 'final_bom.json'

EXPECTED_BOM = [
    {'category': 'Fastener', 'is_leaf': True, 'name': 'Screws', 'part_id': 'PART-100'},
    {'category': 'Electrical', 'is_leaf': True, 'name': 'DC Motor', 'part_id': 'PART-200'},
    {'category': 'Housing', 'is_leaf': True, 'name': 'Plastic Shell', 'part_id': 'PART-300'},
    {'category': 'Accessory', 'is_leaf': True, 'name': 'Rubber Feet', 'part_id': 'PART-400'},
    {'category': 'Subassembly', 'is_leaf': False, 'name': 'Motor Assembly', 'part_id': 'SUB-010'},
    {'category': 'Subassembly', 'is_leaf': False, 'name': 'Casing Assembly', 'part_id': 'SUB-020'}
]


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != '__pycache__']
        for filename in files:
            path = Path(root) / filename
            try:
                if path.stat().st_size > 1024 * 1024:
                    continue
                first_line = path.open('r', errors='ignore').readline()
            except (OSError, UnicodeError):
                continue
            if path.suffix == '.py' or ('python' in first_line and first_line.startswith('#!')):
                scripts.append(path)
    return sorted(set(scripts))


def derive_expected(db_path):
    conn = sqlite3.connect(db_path)
    try:
        components = {
            part_id: (name, category)
            for part_id, name, category in conn.execute(
                'SELECT part_id, name, category FROM components'
            ).fetchall()
        }
        edges = conn.execute('SELECT parent_id, child_id FROM assembly').fetchall()
    finally:
        conn.close()

    children = {}
    for parent, child in edges:
        children.setdefault(parent, set()).add(child)

    found = set()
    pending = list(children.get('PROD-001', ()))
    while pending:
        part_id = pending.pop()
        if part_id in found:
            continue
        found.add(part_id)
        pending.extend(children.get(part_id, ()))

    result = []
    for part_id in sorted(found):
        name, category = components[part_id]
        result.append({
            'part_id': part_id,
            'name': name,
            'category': category,
            'is_leaf': not bool(children.get(part_id))
        })
    return result, components, edges


def validate_output(path, expected):
    with path.open('r') as f:
        data = json.load(f)
    assert isinstance(data, list)
    assert data == expected
    assert [x['part_id'] for x in data] == sorted(x['part_id'] for x in data)
    for item in data:
        assert set(item) == {'part_id', 'name', 'category', 'is_leaf'}
        assert type(item['part_id']) is str
        assert type(item['name']) is str
        assert type(item['category']) is str
        assert type(item['is_leaf']) is bool


def make_instrumentation(directory):
    sitecustomize = Path(directory) / 'sitecustomize.py'
    sitecustomize.write_text(r'''import json
import os

LOG = os.environ.get('BOM_TRACE_LOG')

def emit(value):
    if not LOG:
        return
    try:
        with open(LOG, 'a') as f:
            f.write(json.dumps(value) + '\n')
    except Exception:
        pass

try:
    import sqlite3
    _connect = sqlite3.connect
    def traced_connect(*args, **kwargs):
        conn = _connect(*args, **kwargs)
        conn.set_trace_callback(lambda sql: emit({'event': 'sql', 'sql': sql}))
        return conn
    sqlite3.connect = traced_connect
except Exception:
    pass

try:
    import rdflib
    _query = rdflib.Graph.query
    def traced_query(self, query_object, *args, **kwargs):
        emit({
            'event': 'query',
            'query': str(query_object),
            'triples': sorted([[str(s), str(p), str(o)] for s, p, o in self])
        })
        return _query(self, query_object, *args, **kwargs)
    rdflib.Graph.query = traced_query
except Exception:
    pass
''')


def read_events(log_path):
    events = []
    if not log_path.exists():
        return events
    for line in log_path.read_text(errors='replace').splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return events


def is_full_select(sql, table):
    normalized = ' ' + re.sub(r'\s+', ' ', sql.lower()) + ' '
    table_pattern = r'\bfrom\s+["`\[]?' + re.escape(table) + r'\b'
    return bool(re.search(r'\bselect\b', normalized) and
                re.search(table_pattern, normalized) and
                ' where ' not in normalized)


def validate_trace(events, components, edges):
    sql_statements = [e.get('sql', '') for e in events if e.get('event') == 'sql']
    assert any(is_full_select(sql, 'components') for sql in sql_statements), \
        'The script did not execute a full-table SELECT from components.'
    assert any(is_full_select(sql, 'assembly') for sql in sql_statements), \
        'The script did not execute a full-table SELECT from assembly.'

    ns = 'http://example.org/bom/'
    required_triples = set()
    for part_id, (name, category) in components.items():
        required_triples.add((ns + part_id, ns + 'name', name))
        required_triples.add((ns + part_id, ns + 'category', category))
    for parent, child in edges:
        required_triples.add((ns + parent, ns + 'hasChild', ns + child))

    matching_query = False
    for event in events:
        if event.get('event') != 'query':
            continue
        query = event.get('query', '')
        triples = {tuple(t) for t in event.get('triples', [])}
        # A transitive SPARQL property path must be executed against the fully
        # populated RDF graph. The behavioural test below verifies its result.
        if 'hasChild' in query and ('+' in query or '*' in query) and required_triples <= triples:
            matching_query = True
            break
    assert matching_query, \
        'No transitive SPARQL query was executed against a complete BOM RDF graph.'


def test_pipeline_script_is_executed_and_generalizes(tmp_path):
    scripts = find_python_scripts()
    assert scripts, 'No Python script was created under /home/user.'

    original_db = DB_PATH.read_bytes()
    mutated_db = tmp_path / 'mutated.db'
    mutated_db.write_bytes(original_db)

    token = uuid.uuid4().hex[:10].upper()
    a = 'DYN-A-' + token
    b = 'DYN-B-' + token
    c = 'DYN-C-' + token
    unused = 'DYN-U-' + token

    conn = sqlite3.connect(mutated_db)
    try:
        conn.execute(
            "UPDATE components SET name = ?, category = ? WHERE part_id = 'PART-200'",
            ('Motor ' + token, 'Electrical-' + token)
        )
        conn.executemany('INSERT INTO components VALUES (?, ?, ?)', [
            (a, 'Dynamic A ' + token, 'Dynamic'),
            (b, 'Dynamic B ' + token, 'Dynamic'),
            (c, 'Dynamic C ' + token, 'Dynamic'),
            (unused, 'Unreachable ' + token, 'Decoy')
        ])
        conn.executemany('INSERT INTO assembly VALUES (?, ?)', [
            ('PROD-001', a),
            (a, b),
            ('PART-400', c)
        ])
        conn.commit()
    finally:
        conn.close()

    expected, components, edges = derive_expected(mutated_db)
    instrumentation = tmp_path / 'instrumentation'
    instrumentation.mkdir()
    make_instrumentation(instrumentation)

    selected = None
    failures = []
    try:
        for script in scripts:
            DB_PATH.write_bytes(mutated_db.read_bytes())
            FINAL_BOM_PATH.unlink(missing_ok=True)
            trace_log = tmp_path / ('trace-' + str(len(failures)) + '.jsonl')
            env = os.environ.copy()
            old_pythonpath = env.get('PYTHONPATH')
            env['PYTHONPATH'] = str(instrumentation) + (os.pathsep + old_pythonpath if old_pythonpath else '')
            env['BOM_TRACE_LOG'] = str(trace_log)
            try:
                proc = subprocess.run(
                    [sys.executable, str(script)],
                    cwd=str(HOME), env=env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
                )
                assert proc.returncode == 0, proc.stderr
                assert FINAL_BOM_PATH.is_file(), 'Script did not create final_bom.json.'
                validate_output(FINAL_BOM_PATH, expected)
                validate_trace(read_events(trace_log), components, edges)
                selected = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')
    finally:
        DB_PATH.write_bytes(original_db)

    assert selected is not None, 'No Python script implemented the required pipeline:\n' + '\n'.join(failures)

    FINAL_BOM_PATH.unlink(missing_ok=True)
    proc = subprocess.run(
        [sys.executable, str(selected)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, proc.stderr


def test_final_bom_exists():
    assert os.path.isfile(FINAL_BOM_PATH), f'Output file {FINAL_BOM_PATH} does not exist.'


def test_final_bom_format_and_content():
    with open(FINAL_BOM_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {FINAL_BOM_PATH} is not valid JSON.')

    assert isinstance(data, list), f'Expected JSON root to be a list, got {type(data).__name__}.'

    part_ids = [item.get('part_id') for item in data if isinstance(item, dict)]
    assert part_ids == sorted(part_ids), 'The JSON array is not sorted alphabetically by part_id.'

    assert len(data) == len(EXPECTED_BOM), f'Expected {len(EXPECTED_BOM)} items, found {len(data)}.'

    for expected_item, actual_item in zip(EXPECTED_BOM, data):
        assert isinstance(actual_item, dict), 'Each item in the JSON array must be an object/dictionary.'

        for key in ['part_id', 'name', 'category', 'is_leaf']:
            assert key in actual_item, f"Missing key '{key}' in item {actual_item}"
            assert actual_item[key] == expected_item[key], (
                f"Mismatch for part_id {expected_item['part_id']} on key '{key}': "
                f"expected {expected_item[key]}, got {actual_item[key]}"
            )

        extra_keys = set(actual_item.keys()) - set(expected_item.keys())
        assert not extra_keys, f"Found unexpected keys in item {actual_item['part_id']}: {extra_keys}"
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
