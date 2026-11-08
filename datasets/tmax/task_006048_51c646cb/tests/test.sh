#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_vulnerable_servers_log():
    """Test that the vulnerable_servers.log contains the correct output."""
    log_path = '/home/user/vulnerable_servers.log'
    assert os.path.exists(log_path), f"Failure: Output file not found at {log_path}."

    with open(log_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["Server_Alpha", "Server_Delta", "Server_Gamma"]
    assert lines == expected, f"Failure: Expected {expected}, got {lines}"

def test_audit_script_exists_and_uses_rdflib():
    """Test that the python script exists and contains expected rdflib / query features."""
    script_path = '/home/user/audit_vulnerabilities.py'
    assert os.path.exists(script_path), f"Failure: Script not found at {script_path}."

    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'rdflib' in content, "Failure: The script must import and use the 'rdflib' library."

    # Check for parameterized query usage (initBindings or prepareQuery)
    has_parameterization = 'initBindings' in content or 'prepareQuery' in content
    assert has_parameterization, "Failure: The script must use parameterized queries (e.g., initBindings or prepareQuery)."

    # Check for graph matching features to filter out active patches
    has_graph_filtering = 'MINUS' in content.upper() or 'FILTER NOT EXISTS' in content.upper() or 'NOT EXISTS' in content.upper()
    assert has_graph_filtering, "Failure: The script's SPARQL query must use graph matching features like MINUS or FILTER NOT EXISTS."
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import json
import os
import secrets
import subprocess
from pathlib import Path

script = Path('/home/user/audit_vulnerabilities.py')
graph = Path('/home/user/security_graph.ttl')
output = Path('/home/user/vulnerable_servers.log')
original_graph = graph.read_bytes()

token = secrets.token_hex(8)
names = {
    'superseded': f'Server_Superseded_{token}',
    'active': f'Server_Active_{token}',
    'none': f'Server_Unpatched_{token}',
    'revoked': f'Server_Revoked_{token}',
    'wrongfix': f'Server_WrongFix_{token}',
    'other': f'Server_OtherCVE_{token}',
}
expected = sorted([
    names['superseded'], names['none'], names['revoked'], names['wrongfix']
])

ttl = f'''@prefix ex: <http://example.org/sec#> .

ex:{names['superseded']} ex:hasVuln ex:CVE-2024-1111 ; ex:hasPatch ex:Patch_S_{token} .
ex:Patch_S_{token} ex:fixes ex:CVE-2024-1111 ; ex:status "Superseded" .

ex:{names['active']} ex:hasVuln ex:CVE-2024-1111 ; ex:hasPatch ex:Patch_A_{token} .
ex:Patch_A_{token} ex:fixes ex:CVE-2024-1111 ; ex:status "Active" .

ex:{names['none']} ex:hasVuln ex:CVE-2024-1111 .

ex:{names['revoked']} ex:hasVuln ex:CVE-2024-1111 ; ex:hasPatch ex:Patch_R_{token} .
ex:Patch_R_{token} ex:fixes ex:CVE-2024-1111 ; ex:status "Revoked" .

ex:{names['wrongfix']} ex:hasVuln ex:CVE-2024-1111 ; ex:hasPatch ex:Patch_W_{token} .
ex:Patch_W_{token} ex:fixes ex:CVE-2024-2222 ; ex:status "Active" .

ex:{names['other']} ex:hasVuln ex:CVE-2024-2222 .
'''

hook_dir = Path('/tmp/verifier_hook')
hook_dir.mkdir(exist_ok=True)
trace = Path('/tmp/rdflib_query_trace.jsonl')
trace.unlink(missing_ok=True)
(hook_dir / 'sitecustomize.py').write_text(r'''
import inspect
import json
import os
import rdflib

_trace = os.environ.get("RDFLIB_QUERY_TRACE")
_original_query = rdflib.Graph.query
_signature = inspect.signature(_original_query)

def _recording_query(self, *args, **kwargs):
    record = {"called": True, "bindings": {}}
    try:
        bound = _signature.bind_partial(self, *args, **kwargs)
        bindings = bound.arguments.get("initBindings") or {}
        record["bindings"] = {str(k): str(v) for k, v in bindings.items()}
        query_object = bound.arguments.get("query_object")
        if query_object is None and args:
            query_object = args[0]
        record["query"] = str(query_object)
    except Exception as exc:
        record["trace_error"] = repr(exc)
    if _trace:
        with open(_trace, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(record) + "\n")
    return _original_query(self, *args, **kwargs)

rdflib.Graph.query = _recording_query
''', encoding='utf-8')

try:
    graph.write_text(ttl, encoding='utf-8')
    output.unlink(missing_ok=True)
    env = os.environ.copy()
    env['RDFLIB_QUERY_TRACE'] = str(trace)
    env['PYTHONPATH'] = str(hook_dir) + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    completed = subprocess.run(
        ['python3', str(script)], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert completed.returncode == 0, (
        f'audit script failed on a valid graph: {completed.stderr}'
    )
    assert output.exists(), 'audit script did not create vulnerable_servers.log'
    actual = [line.strip() for line in output.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert actual == expected, f'expected dynamically derived output {expected}, got {actual}'

    assert trace.exists(), 'the script did not execute rdflib.Graph.query'
    records = [json.loads(line) for line in trace.read_text(encoding='utf-8').splitlines() if line.strip()]
    target = 'http://example.org/sec#CVE-2024-1111'
    assert any(target in record.get('bindings', {}).values() for record in records), (
        'the executed RDFLib query did not bind the target CVE through initBindings'
    )
finally:
    graph.write_bytes(original_graph)
BEHAVIOR_EOF

status=0

# Execute the submitted artifact on the original graph before retaining the
# original verifier assertions.
timeout 20s python3 /home/user/audit_vulnerabilities.py >/tmp/audit_stdout.txt 2>/tmp/audit_stderr.txt || status=1
if [ "$status" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

# Exercise the script against an unpredictable graph and verify that an actual
# parameter-bound RDFLib query is made.
if [ "$status" -eq 0 ]; then
    python3 /tmp/test_behavior.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
