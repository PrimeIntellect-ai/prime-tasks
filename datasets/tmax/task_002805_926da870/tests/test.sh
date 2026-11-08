#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
import sys
import tempfile

SCRIPT = '/home/user/query_tool.py'
CSV_PATH = '/home/user/transactions.csv'


def run_tool(*args, env=None):
    result = subprocess.run(
        [sys.executable, SCRIPT, *map(str, args)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=10,
    )
    assert result.returncode == 0, f"Tool failed: {result.stderr}"
    return result.stdout.splitlines()


def test_query_tool_exists_and_parameterized():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        content = f.read()
    assert '?' in content, "The script does not appear to use parameterized queries (missing '?' placeholders)."

    tree = ast.parse(content, filename=SCRIPT)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split('.')[0])
    assert {'argparse', 'csv', 'sqlite3'} <= imported, \
        "query_tool.py must import argparse, csv, and sqlite3."


def test_q1_output():
    output_path = '/home/user/q1_output.txt'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ['T003', 'T001']
    assert lines == expected, f"Q1 output incorrect. Expected {expected}, got {lines}."

    actual = run_tool('--category', 'Electronics', '--min-amount', '100',
                      '--sort', 'amount:desc', '--limit', '2')
    assert actual == expected, f"Live Report 1 query returned {actual}, expected {expected}."


def test_q2_output():
    output_path = '/home/user/q2_output.txt'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ['T008', 'T005', 'T002']
    assert lines == expected, f"Q2 output incorrect. Expected {expected}, got {lines}."

    actual = run_tool('--category', 'Books', '--sort', 'date:desc',
                      '--limit', '3', '--offset', '1')
    assert actual == expected, f"Live Report 2 query returned {actual}, expected {expected}."


def derived(rows, category=None, minimum=None, sort=None, limit=None, offset=0):
    selected = list(rows)
    if category is not None:
        selected = [r for r in selected if r['category'] == category]
    if minimum is not None:
        selected = [r for r in selected if float(r['amount']) >= minimum]
    if sort:
        column, direction = sort.split(':', 1)
        if column == 'amount':
            key = lambda r: float(r[column])
        else:
            key = lambda r: r[column]
        selected.sort(key=key, reverse=(direction.lower() == 'desc'))
    selected = selected[offset:]
    if limit is not None:
        selected = selected[:limit]
    return [r['tx_id'] for r in selected]


def test_dynamic_csv_queries_and_injection_safety():
    rows = [
        {'tx_id':'R901','date':'2025-03-01','category':'Gadgets','amount':'10.25','customer_id':'C1'},
        {'tx_id':'R902','date':'2025-03-02','category':'Gadgets','amount':'91.75','customer_id':'C2'},
        {'tx_id':'R903','date':'2025-03-03','category':'Gadgets','amount':'47.50','customer_id':'C3'},
        {'tx_id':'R904','date':'2025-03-04','category':'Other','amount':'300.00','customer_id':'C4'},
        {'tx_id':'R905','date':'2025-03-05','category':"Gadgets' OR 1=1 --",'amount':'33.00','customer_id':'C5'},
        {'tx_id':'R906','date':'2025-03-06','category':'Gadgets','amount':'125.00','customer_id':'C6'},
        {'tx_id':'R907','date':'2025-03-07','category':'Other','amount':'4.00','customer_id':'C7'},
    ]
    with open(CSV_PATH, 'rb') as f:
        original = f.read()
    try:
        with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=['tx_id','date','category','amount','customer_id'])
            writer.writeheader()
            writer.writerows(rows)

        args = ['--category','Gadgets','--min-amount','20','--sort','amount:desc','--limit','2','--offset','1']
        assert run_tool(*args) == derived(rows, 'Gadgets', 20, 'amount:desc', 2, 1)

        injection = "Gadgets' OR 1=1 --"
        args = ['--category', injection, '--sort','date:asc','--limit','5','--offset','0']
        assert run_tool(*args) == derived(rows, injection, None, 'date:asc', 5, 0)

        args = ['--min-amount','5','--sort','date:desc','--limit','3','--offset','2']
        assert run_tool(*args) == derived(rows, None, 5, 'date:desc', 3, 2)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original)


def test_filter_limit_and_offset_are_bound_parameters():
    trace_dir = tempfile.mkdtemp(prefix='sqlite_trace_')
    trace_path = os.path.join(trace_dir, 'trace.jsonl')
    sitecustomize = r'''
import json, os, sqlite3
_real_connect = sqlite3.connect
_trace_path = os.environ.get('QUERY_SQL_TRACE')

def _record(sql, params):
    if _trace_path:
        try:
            values = list(params)
        except TypeError:
            values = [params]
        with open(_trace_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'sql': str(sql), 'params': values}, default=str) + '\n')

class CursorProxy:
    def __init__(self, obj): self._obj = obj
    def execute(self, sql, params=()):
        _record(sql, params)
        self._obj.execute(sql, params)
        return self
    def executemany(self, sql, params):
        _record(sql, params)
        self._obj.executemany(sql, params)
        return self
    def __iter__(self): return iter(self._obj)
    def __getattr__(self, name): return getattr(self._obj, name)

class ConnectionProxy:
    def __init__(self, obj): self._obj = obj
    def cursor(self, *a, **kw): return CursorProxy(self._obj.cursor(*a, **kw))
    def execute(self, sql, params=()):
        _record(sql, params)
        return CursorProxy(self._obj.execute(sql, params))
    def executemany(self, sql, params):
        _record(sql, params)
        return CursorProxy(self._obj.executemany(sql, params))
    def __enter__(self):
        self._obj.__enter__()
        return self
    def __exit__(self, *a): return self._obj.__exit__(*a)
    def __getattr__(self, name): return getattr(self._obj, name)

def connect(*a, **kw): return ConnectionProxy(_real_connect(*a, **kw))
sqlite3.connect = connect
'''
    with open(os.path.join(trace_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env['PYTHONPATH'] = trace_dir + os.pathsep + env.get('PYTHONPATH', '')
    env['QUERY_SQL_TRACE'] = trace_path
    run_tool('--category','Electronics','--min-amount','100',
             '--sort','amount:desc','--limit','2','--offset','1', env=env)

    assert os.path.isfile(trace_path), "No SQLite statements were observed."
    with open(trace_path, encoding='utf-8') as f:
        records = [json.loads(line) for line in f if line.strip()]

    matching = []
    for record in records:
        sql = record['sql']
        upper = sql.upper()
        params = record['params']
        if ('SELECT' in upper and 'CATEGORY' in upper and 'AMOUNT' in upper
                and 'LIMIT' in upper and 'OFFSET' in upper
                and sql.count('?') >= 4
                and 'Electronics' in params
                and any(isinstance(v, (int, float)) and float(v) == 100 for v in params)
                and any(isinstance(v, int) and v == 2 for v in params)
                and any(isinstance(v, int) and v == 1 for v in params)):
            matching.append(record)
    assert matching, "The result query must bind category, minimum amount, limit, and offset using ? parameters."
    for record in matching:
        assert 'Electronics' not in record['sql'], "Category was interpolated into SQL instead of bound."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
