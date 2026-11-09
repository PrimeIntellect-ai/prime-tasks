#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
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

from rdflib import Graph, URIRef

DB_PATH = Path('/home/user/locks.db')
TTL_PATH = Path('/home/user/wait_for.ttl')
JSON_PATH = Path('/home/user/deadlocks.json')
NS = 'http://example.org/tx#'
PREDICATE = URIRef(NS + 'waitsFor')


def get_expected_deadlocks():
    """Retain the original verifier's database-derived assertion."""
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute('''
        SELECT a.tx_id, b.tx_id
        FROM lock_requests a
        JOIN lock_requests b ON a.resource_id = b.resource_id
        WHERE b.grant_time IS NOT NULL
          AND a.request_time > b.grant_time
          AND (b.release_time IS NULL OR a.request_time < b.release_time)
          AND a.tx_id != b.tx_id
    ''')
    edges = c.fetchall()
    conn.close()

    graph = {}
    for a, b in edges:
        graph.setdefault(a, []).append(b)

    cycles = []
    for node in graph:
        for neighbor in graph.get(node, []):
            if node in graph.get(neighbor, []):
                cycle = sorted([node, neighbor])
                if cycle not in cycles:
                    cycles.append(cycle)
            for next_node in graph.get(neighbor, []):
                if node in graph.get(next_node, []):
                    cycle = sorted([node, neighbor, next_node])
                    if cycle not in cycles:
                        cycles.append(cycle)
    cycles.sort(key=lambda x: x[0])
    return cycles


def load_json(path):
    try:
        with path.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{path} is not valid JSON: {exc}')


def check_original_outputs():
    assert TTL_PATH.is_file(), f'RDF file missing at {TTL_PATH}'
    content = TTL_PATH.read_text()
    assert 'waitsFor' in content, "The predicate 'waitsFor' was not found in the Turtle file."

    assert JSON_PATH.is_file(), f'JSON file missing at {JSON_PATH}'
    student_data = load_json(JSON_PATH)
    expected_data = get_expected_deadlocks()
    assert isinstance(student_data, list), 'JSON root should be a list.'

    normalized = []
    for cycle in student_data:
        assert isinstance(cycle, list), 'Each cycle should be a list of strings.'
        normalized.append(sorted(cycle))
    normalized.sort(key=lambda x: x[0] if x else '')
    assert normalized == expected_data, f'Expected deadlocks {expected_data}, but got {normalized}'

    # Parse the submitted Turtle and ensure it models the actual original edges.
    graph = Graph()
    graph.parse(str(TTL_PATH), format='turtle')
    actual = {(str(s), str(o)) for s, p, o in graph.triples((None, PREDICATE, None))}
    expected = {
        (NS + 'T2', NS + 'T1'), (NS + 'T1', NS + 'T2'),
        (NS + 'T4', NS + 'T3'), (NS + 'T5', NS + 'T4'),
        (NS + 'T3', NS + 'T5'), (NS + 'T7', NS + 'T6'),
    }
    assert actual == expected, f'Original Turtle edges are incorrect: expected {expected}, got {actual}'


def find_scripts():
    scripts = []
    for path in Path('/home/user').rglob('*.py'):
        if path.is_file():
            try:
                source = path.read_text(errors='replace')
            except OSError:
                continue
            scripts.append((path, source))
    assert scripts, 'No Python workflow scripts were found under /home/user.'

    window_re = re.compile(r'\b(?:LAG|LAST_VALUE|FIRST_VALUE|ROW_NUMBER|RANK|DENSE_RANK|MAX|MIN)\s*\([^;]*?\)\s*OVER\s*\(', re.I | re.S)
    sql_candidates = [(p, s) for p, s in scripts if window_re.search(s)]
    sparql_candidates = [(p, s) for p, s in scripts if re.search(r'\.query\s*\(', s) and re.search(r'\bSELECT\b', s, re.I) and 'waitsFor' in s]

    assert sql_candidates, 'No Python script containing the required SQL window function was found.'
    assert sparql_candidates, 'No Python script containing an rdflib SPARQL query for waitsFor was found.'

    def score(item, terms):
        p, s = item
        return sum(term in s for term in terms) * 10 + sum(term in p.name.lower() for term in ('lock', 'wait', 'deadlock', 'rdf', 'sparql'))

    sql_script = max(sql_candidates, key=lambda x: score(x, ('locks.db', 'wait_for.ttl', 'sqlite3')))[0]
    sparql_script = max(sparql_candidates, key=lambda x: score(x, ('wait_for.ttl', 'deadlocks.json', 'rdflib')))[0]
    return sql_script, sparql_script


def install_instrumentation(directory, sql_log, sparql_log):
    code = r'''
import json
import os
import sqlite3

_sql_log = os.environ.get('VERIFIER_SQL_LOG')
_sparql_log = os.environ.get('VERIFIER_SPARQL_LOG')
_real_connect = sqlite3.connect

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor
    def execute(self, sql, *args, **kwargs):
        if _sql_log:
            with open(_sql_log, 'a') as f:
                f.write(str(sql).replace('\\n', ' ') + '\\n')
        self._cursor.execute(sql, *args, **kwargs)
        return self
    def executemany(self, sql, *args, **kwargs):
        if _sql_log:
            with open(_sql_log, 'a') as f:
                f.write(str(sql).replace('\\n', ' ') + '\\n')
        self._cursor.executemany(sql, *args, **kwargs)
        return self
    def executescript(self, sql, *args, **kwargs):
        if _sql_log:
            with open(_sql_log, 'a') as f:
                f.write(str(sql).replace('\\n', ' ') + '\\n')
        self._cursor.executescript(sql, *args, **kwargs)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection
    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, *args, **kwargs):
        return self.cursor().execute(sql, *args, **kwargs)
    def executemany(self, sql, *args, **kwargs):
        return self.cursor().executemany(sql, *args, **kwargs)
    def executescript(self, sql, *args, **kwargs):
        return self.cursor().executescript(sql, *args, **kwargs)
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect

try:
    import rdflib
    _real_query = rdflib.Graph.query
    def logged_query(self, query_object, *args, **kwargs):
        if _sparql_log:
            with open(_sparql_log, 'a') as f:
                f.write(json.dumps(str(query_object)) + '\\n')
        return _real_query(self, query_object, *args, **kwargs)
    rdflib.Graph.query = logged_query
except Exception:
    pass
'''
    (directory / 'sitecustomize.py').write_text(code)


def create_hidden_database(prefix):
    names = {letter: prefix + '_' + letter for letter in 'ABCDEFGHIJKL'}
    if DB_PATH.exists():
        DB_PATH.unlink()
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute('''CREATE TABLE lock_requests (
        tx_id TEXT, resource_id TEXT, request_time INTEGER,
        grant_time INTEGER, release_time INTEGER
    )''')
    rows = [
        (names['A'], 'RA', 1, 10, None), (names['B'], 'RA', 20, None, None),
        (names['B'], 'RB', 2, 11, None), (names['A'], 'RB', 21, None, None),
        (names['C'], 'RC', 3, 30, None), (names['D'], 'RC', 40, None, None),
        (names['D'], 'RD', 4, 31, None), (names['E'], 'RD', 41, None, None),
        (names['E'], 'RE', 5, 32, None), (names['C'], 'RE', 42, None, None),
        (names['F'], 'RF', 6, 50, 60), (names['G'], 'RF', 55, None, None),
        (names['H'], 'RG', 7, 70, 75), (names['I'], 'RG', 80, None, None),
        (names['J'], 'RH', 8, 90, None), (names['K'], 'RH', 95, 100, 105),
        (names['L'], 'RH', 103, None, None),
    ]
    conn.executemany('INSERT INTO lock_requests VALUES (?, ?, ?, ?, ?)', rows)
    conn.commit()
    conn.close()
    return names


def run_script(path, env):
    result = subprocess.run(
        [sys.executable, str(path)], cwd=str(path.parent), env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
    )
    assert result.returncode == 0, f'Script {path} failed:\n{result.stdout}'


def check_dynamic_workflow(sql_script, sparql_script):
    backup_dir = Path(tempfile.mkdtemp(prefix='workflow-backup-'))
    backups = {}
    for path in (DB_PATH, TTL_PATH, JSON_PATH):
        if path.exists():
            destination = backup_dir / path.name
            shutil.copy2(path, destination)
            backups[path] = destination

    instrument_dir = Path(tempfile.mkdtemp(prefix='workflow-instrument-'))
    sql_log = instrument_dir / 'sql.log'
    sparql_log = instrument_dir / 'sparql.log'
    install_instrumentation(instrument_dir, sql_log, sparql_log)

    try:
        prefix = 'V' + uuid.uuid4().hex[:10]
        names = create_hidden_database(prefix)
        TTL_PATH.unlink(missing_ok=True)
        JSON_PATH.unlink(missing_ok=True)

        env = os.environ.copy()
        env['HOME'] = '/home/user'
        env['VERIFIER_SQL_LOG'] = str(sql_log)
        env['VERIFIER_SPARQL_LOG'] = str(sparql_log)
        old_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = str(instrument_dir) + (os.pathsep + old_pythonpath if old_pythonpath else '')

        run_script(sql_script, env)
        if sparql_script != sql_script:
            run_script(sparql_script, env)

        assert TTL_PATH.is_file(), 'The executed workflow did not create wait_for.ttl.'
        assert JSON_PATH.is_file(), 'The executed workflow did not create deadlocks.json.'

        executed_sql = sql_log.read_text() if sql_log.exists() else ''
        runtime_window = re.compile(r'\b(?:LAG|LAST_VALUE|FIRST_VALUE|ROW_NUMBER|RANK|DENSE_RANK|MAX|MIN)\s*\([^;]*?\)\s*OVER\s*\(', re.I | re.S)
        assert runtime_window.search(executed_sql), 'The executed workflow did not run a SQL window-function query.'

        queries = []
        if sparql_log.exists():
            for line in sparql_log.read_text().splitlines():
                queries.append(json.loads(line))
        relevant = [q for q in queries if re.search(r'\bSELECT\b', q, re.I) and 'waitsFor' in q]
        assert relevant, 'The executed workflow did not execute a waitsFor SPARQL SELECT query.'
        counts = [len(re.findall(r'waitsFor', q, re.I)) for q in relevant]
        combined = '\n'.join(relevant)
        assert max(counts) >= 3 or re.search(r'waitsFor\s*\{\s*2\s*,\s*3\s*\}', combined, re.I), \
            'The executed SPARQL did not express cycle traversal of both required lengths.'

        graph = Graph()
        graph.parse(str(TTL_PATH), format='turtle')
        actual_edges = {(str(s), str(o)) for s, p, o in graph.triples((None, PREDICATE, None))}
        pairs = {
            ('B', 'A'), ('A', 'B'), ('D', 'C'), ('E', 'D'), ('C', 'E'),
            ('G', 'F'), ('K', 'J'), ('L', 'K'),
        }
        expected_edges = {(NS + names[a], NS + names[b]) for a, b in pairs}
        assert actual_edges == expected_edges, f'Hidden-case RDF edges are incorrect: expected {expected_edges}, got {actual_edges}'

        expected_cycles = [sorted([names['A'], names['B']]), sorted([names['C'], names['D'], names['E']])]
        expected_cycles.sort(key=lambda cycle: cycle[0])
        data = load_json(JSON_PATH)
        assert data == expected_cycles, f'Hidden-case deadlocks should be {expected_cycles}, got {data}'
        assert all(isinstance(c, list) and all(isinstance(tx, str) for tx in c) for c in data), 'Cycles must be lists of tx_id strings.'
        assert all(c == sorted(c) for c in data), 'Transaction IDs within each cycle are not sorted.'
        assert data == sorted(data, key=lambda c: c[0]), 'The outer cycle list is not sorted.'
        assert len({tuple(c) for c in data}) == len(data), 'Duplicate cycles were emitted.'
    finally:
        for path in (DB_PATH, TTL_PATH, JSON_PATH):
            path.unlink(missing_ok=True)
            if path in backups:
                shutil.copy2(backups[path], path)
        shutil.rmtree(backup_dir, ignore_errors=True)
        shutil.rmtree(instrument_dir, ignore_errors=True)


def main():
    check_original_outputs()
    sql_script, sparql_script = find_scripts()
    check_dynamic_workflow(sql_script, sparql_script)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
