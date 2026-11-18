#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIG_GRAPH=/tmp/org_graph.original.ttl
cp /home/user/org_graph.ttl "$ORIG_GRAPH"
restore_graph() {
    cp "$ORIG_GRAPH" /home/user/org_graph.ttl 2>/dev/null || true
}
trap restore_graph EXIT

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT = Path('/home/user/audit.py')
GRAPH = Path('/home/user/org_graph.ttl')
REPORT = Path('/home/user/audit_report.json')
ORIGINAL_GRAPH = Path('/tmp/org_graph.original.ttl')
TRACE_DIR = Path('/tmp/audit_instrumentation')
TRACE = Path('/tmp/audit_rdflib_trace.jsonl')

EXPECTED_ORIGINAL = [
    {'employee_name': 'Bob Jones', 'department_name': 'Sales'},
    {'employee_name': 'Charlie Brown', 'department_name': 'Direct Sales'},
    {'employee_name': 'Frank Miller', 'department_name': 'Operations'},
]


def validate_index_strategy(data):
    assert 'index_strategy' in data, "JSON missing 'index_strategy' key."
    index_strategy = data['index_strategy'].strip()
    normalized_strategy = re.sub(r'\s+', ' ', index_strategy).upper()
    assert normalized_strategy, 'Index strategy is empty.'
    pattern = r'^CREATE\s+INDEX\s+idx_system_time\s+ON\s+access_logs\s*\(\s*system_name\s*,\s*access_time\s+DESC\s*\)\s*;?$'
    assert re.match(pattern, index_strategy, re.IGNORECASE), \
        f'Index strategy does not match the expected CREATE INDEX statement. Got: {index_strategy}'
    assert 'idx_system_time' in index_strategy, "Index name 'idx_system_time' not found with exact case."
    assert 'access_logs' in index_strategy, "Table name 'access_logs' not found with exact case."
    assert 'system_name' in index_strategy, "Column name 'system_name' not found with exact case."
    assert 'access_time' in index_strategy, "Column name 'access_time' not found with exact case."


def load_and_validate_report(expected):
    report_path = str(REPORT)
    assert os.path.exists(report_path), f'Expected file {report_path} does not exist.'
    assert os.path.isfile(report_path), f'{report_path} is not a regular file.'
    try:
        with REPORT.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f'{report_path} is not a valid JSON file.'

    assert 'unauthorized_accesses' in data, "JSON missing 'unauthorized_accesses' key."
    assert 'index_strategy' in data, "JSON missing 'index_strategy' key."
    unauthorized = data['unauthorized_accesses']
    assert isinstance(unauthorized, list), "'unauthorized_accesses' should be a list."
    assert len(unauthorized) == len(expected), \
        f'Expected exactly {len(expected)} unauthorized accesses, got {len(unauthorized)}.'

    employee_names = [item.get('employee_name', '') for item in unauthorized]
    assert employee_names == sorted(employee_names), \
        "'unauthorized_accesses' is not sorted alphabetically by employee_name."
    for item in expected:
        assert item in unauthorized, f"Expected entry {item} not found in 'unauthorized_accesses'."
    assert unauthorized == sorted(expected, key=lambda x: x['employee_name']), \
        f'Unexpected unauthorized access data: {unauthorized}'
    validate_index_strategy(data)


def install_instrumentation():
    TRACE_DIR.mkdir(exist_ok=True)
    (TRACE_DIR / 'sitecustomize.py').write_text(r'''
import json
import os
import rdflib

_trace = os.environ.get('AUDIT_RDFLIB_TRACE')
_original_parse = rdflib.graph.Graph.parse
_original_query = rdflib.graph.Graph.query

def _write(event, values):
    if not _trace:
        return
    try:
        with open(_trace, 'a') as f:
            f.write(json.dumps({'event': event, 'values': values}) + '\n')
    except Exception:
        pass

def _parse(self, source=None, publicID=None, format=None, location=None, file=None, data=None, **args):
    vals = [str(source), str(location), str(file), str(getattr(source, 'name', None)), str(getattr(file, 'name', None))]
    _write('parse', vals)
    return _original_parse(self, source=source, publicID=publicID, format=format,
                           location=location, file=file, data=data, **args)

def _query(self, query_object, *args, **kwargs):
    _write('query', [str(query_object)])
    return _original_query(self, query_object, *args, **kwargs)

rdflib.graph.Graph.parse = _parse
rdflib.graph.Graph.query = _query
rdflib.Graph.parse = _parse
rdflib.Graph.query = _query
''')


def run_audit():
    if REPORT.exists():
        REPORT.unlink()
    if TRACE.exists():
        TRACE.unlink()
    env = os.environ.copy()
    env['PYTHONPATH'] = str(TRACE_DIR) + os.pathsep + env.get('PYTHONPATH', '')
    env['AUDIT_RDFLIB_TRACE'] = str(TRACE)
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f'audit.py failed with exit code {result.returncode}. stderr: {result.stderr}'
    assert TRACE.exists(), 'No rdflib execution trace was produced.'
    events = [json.loads(line) for line in TRACE.read_text().splitlines() if line.strip()]
    parses = [e for e in events if e.get('event') == 'parse']
    queries = [e for e in events if e.get('event') == 'query']
    assert parses, 'audit.py did not use rdflib Graph.parse to load RDF data.'
    assert any('/home/user/org_graph.ttl' in value for e in parses for value in e.get('values', [])), \
        'audit.py did not load /home/user/org_graph.ttl using rdflib.'
    assert queries, 'audit.py did not execute a SPARQL query through rdflib.'


def assert_rdflib_import():
    try:
        tree = ast.parse(SCRIPT.read_text(), filename=str(SCRIPT))
    except SyntaxError as exc:
        assert False, f'audit.py is not valid Python: {exc}'
    imported = any(
        (isinstance(node, ast.Import) and any(alias.name == 'rdflib' or alias.name.startswith('rdflib.') for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == 'rdflib' or node.module.startswith('rdflib.')))
        for node in ast.walk(tree)
    )
    assert imported, 'audit.py must import and use the rdflib library.'


def test_audit_script_and_report():
    assert SCRIPT.exists(), 'Expected /home/user/audit.py does not exist.'
    assert SCRIPT.is_file(), '/home/user/audit.py is not a regular file.'
    assert_rdflib_import()
    install_instrumentation()

    # Preserve and exercise all checks against the supplied fixture.
    shutil.copyfile(ORIGINAL_GRAPH, GRAPH)
    run_audit()
    load_and_validate_report(EXPECTED_ORIGINAL)

    # Exercise the implementation on an unpredictable RDF graph so a fixed report cannot pass.
    token = secrets.token_hex(8)
    names = [f'Ada {token}', f'Mira {token}', f'Zoe {token}']
    expected = [
        {'employee_name': names[0], 'department_name': f'Finance {token}'},
        {'employee_name': names[1], 'department_name': f'Field Sales {token}'},
        {'employee_name': names[2], 'department_name': f'Operations {token}'},
    ]
    GRAPH.write_text(f'''@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix org: <http://www.w3.org/ns/org#> .

ex:IT a org:OrganizationalUnit ; foaf:name "IT" .
ex:Security a org:OrganizationalUnit ; foaf:name "Security" .
ex:NetOps a org:OrganizationalUnit ; foaf:name "Network {token}" ; org:subOrganizationOf ex:IT .
ex:Finance a org:OrganizationalUnit ; foaf:name "Finance {token}" .
ex:Sales a org:OrganizationalUnit ; foaf:name "Sales {token}" .
ex:FieldSales a org:OrganizationalUnit ; foaf:name "Field Sales {token}" ; org:subOrganizationOf ex:Sales .
ex:Operations a org:OrganizationalUnit ; foaf:name "Operations {token}" .

ex:E1 a foaf:Person ; foaf:name "{names[0]}" ; org:memberOf ex:Finance .
ex:E2 a foaf:Person ; foaf:name "{names[1]}" ; org:memberOf ex:FieldSales .
ex:E3 a foaf:Person ; foaf:name "{names[2]}" ; org:memberOf ex:Operations .
ex:E4 a foaf:Person ; foaf:name "Authorized IT {token}" ; org:memberOf ex:IT .
ex:E5 a foaf:Person ; foaf:name "Authorized Sub {token}" ; org:memberOf ex:NetOps .
ex:E6 a foaf:Person ; foaf:name "Authorized Security {token}" ; org:memberOf ex:Security .

ex:A1 ex:accessedBy ex:E1 ; ex:system "System_Omega" .
ex:A2 ex:accessedBy ex:E2 ; ex:system "System_Omega" .
ex:A3 ex:accessedBy ex:E3 ; ex:system "System_Omega" .
ex:A4 ex:accessedBy ex:E4 ; ex:system "System_Omega" .
ex:A5 ex:accessedBy ex:E5 ; ex:system "System_Omega" .
ex:A6 ex:accessedBy ex:E6 ; ex:system "System_Omega" .
ex:A7 ex:accessedBy ex:E3 ; ex:system "System_Alpha" .
''')
    run_audit()
    load_and_validate_report(expected)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
