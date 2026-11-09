#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/audit_verify

cat << 'HOOK_EOF' > /tmp/audit_verify/sitecustomize.py
import json
import os
import rdflib

_original_query = rdflib.graph.Graph.query

def _logged_query(self, query_object, processor='sparql', result='sparql', initNs=None,
                  initBindings=None, use_store_provided=True, **kwargs):
    bindings = []
    for key, value in (initBindings or {}).items():
        bindings.append({
            'key': str(key),
            'value': str(value),
            'type': type(value).__name__,
        })
    log_path = os.environ.get('AUDIT_QUERY_LOG')
    if log_path:
        with open(log_path, 'a', encoding='utf-8') as log:
            json.dump({'query': str(query_object), 'bindings': bindings}, log)
            log.write('\n')
    return _original_query(
        self, query_object, processor=processor, result=result,
        initNs=initNs, initBindings=initBindings,
        use_store_provided=use_store_provided, **kwargs
    )

rdflib.graph.Graph.query = _logged_query
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid
from pathlib import Path

from rdflib import Graph, Literal, Namespace, RDF, URIRef
from rdflib.namespace import XSD

SCRIPT = Path('/home/user/audit.py')
REPORT = Path('/home/user/audit_report.json')
GRAPH_PATH = Path('/home/user/access_graph.ttl')
HOOK_DIR = '/tmp/audit_verify'


def test_audit_script_exists():
    """Test that the audit.py script was created."""
    script_path = "/home/user/audit.py"
    assert os.path.exists(script_path), f"The script {script_path} is missing."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_audit_report_exists():
    """Test that the audit_report.json file was generated."""
    report_path = "/home/user/audit_report.json"
    assert os.path.exists(report_path), f"The report file {report_path} is missing. Did you run the script?"
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."


def test_audit_report_content():
    """Test that the audit_report.json contains the correct aggregated data."""
    report_path = "/home/user/audit_report.json"

    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {report_path} does not contain valid JSON."
    except Exception as e:
        assert False, f"Could not read {report_path}: {e}"

    expected_data = {
        "Alice": 2,
        "Bob": 1
    }

    assert data == expected_data, f"The report content is incorrect. Expected {expected_data}, but got {data}."


def _run_audit(dept, resource, min_hour, max_hour, output, expected):
    output = Path(output)
    output.unlink(missing_ok=True)
    log_path = output.with_suffix(output.suffix + '.queries')
    log_path.unlink(missing_ok=True)

    env = os.environ.copy()
    env['PYTHONPATH'] = HOOK_DIR + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['AUDIT_QUERY_LOG'] = str(log_path)
    command = [
        'python3', str(SCRIPT), '--dept', dept, '--resource', resource,
        '--min-hour', str(min_hour), '--max-hour', str(max_hour),
        '--output', str(output),
    ]
    completed = subprocess.run(command, text=True, capture_output=True, env=env, timeout=30)
    assert completed.returncode == 0, (
        f"audit.py failed for {command}:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert output.is_file(), f'audit.py did not create the requested output file {output}'
    try:
        data = json.loads(output.read_text(encoding='utf-8'))
    except Exception as exc:
        raise AssertionError(f'{output} is not valid JSON: {exc}') from exc
    assert data == expected, f'For {command}, expected {expected}, got {data}'
    assert isinstance(data, dict)
    assert all(type(key) is str and type(value) is int for key, value in data.items()), (
        'Report keys must be strings and counts must be integers'
    )

    assert log_path.is_file(), 'No rdflib Graph.query call was observed'
    records = [json.loads(line) for line in log_path.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert records, 'The script did not execute an rdflib SPARQL query'

    expected_terms = {
        ('Literal', dept),
        ('URIRef', 'http://example.org/' + resource),
        ('Literal', str(min_hour)),
        ('Literal', str(max_hour)),
    }
    acceptable_literal_types = {'Literal'}
    matching_record = None
    for record in records:
        terms = {(item['type'], item['value']) for item in record.get('bindings', [])}
        if expected_terms.issubset(terms):
            matching_record = record
            break
    assert matching_record is not None, (
        'The SPARQL query must receive department, resource URI, minimum hour, and maximum hour '
        f'as rdflib initBindings. Observed calls: {records}'
    )

    query_text = matching_record['query']
    forbidden = [dept, resource, 'http://example.org/' + resource, str(min_hour), str(max_hour)]
    assert all(value not in query_text for value in forbidden), (
        'Runtime filter values were embedded in the SPARQL text instead of being supplied only through initBindings'
    )


def _add_employee(graph, ex, identifier, name, department):
    employee = ex[identifier]
    graph.add((employee, RDF.type, ex.Employee))
    graph.add((employee, ex.name, Literal(name)))
    graph.add((employee, ex.department, Literal(department)))
    return employee


def _add_event(graph, ex, identifier, employee, resource, hour):
    event = ex[identifier]
    graph.add((event, RDF.type, ex.AccessEvent))
    graph.add((event, ex.accessedBy, employee))
    graph.add((event, ex.accessedResource, ex[resource]))
    graph.add((event, ex.accessHour, Literal(hour, datatype=XSD.integer)))


def test_script_executes_sparql_with_cli_arguments_and_bindings(tmp_path):
    original_graph = GRAPH_PATH.read_bytes()
    token = uuid.uuid4().hex
    dept = 'Dept_' + token
    other_dept = 'OtherDept_' + token
    resource = 'Resource_' + token
    other_resource = 'OtherResource_' + token
    name_a = 'NameA_' + token
    name_b = 'NameB_' + token
    name_c = 'NameC_' + token
    ex = Namespace('http://example.org/')

    graph = Graph()
    emp_a = _add_employee(graph, ex, 'EmpA_' + token, name_a, dept)
    emp_b = _add_employee(graph, ex, 'EmpB_' + token, name_b, dept)
    emp_c = _add_employee(graph, ex, 'EmpC_' + token, name_c, other_dept)

    events = [
        (emp_a, resource, 314),
        (emp_a, resource, 319),
        (emp_b, resource, 316),
        (emp_b, other_resource, 315),
        (emp_c, resource, 315),
        (emp_a, resource, 313),
        (emp_a, resource, 320),
    ]
    for index, (employee, event_resource, hour) in enumerate(events):
        _add_event(graph, ex, f'Event_{token}_{index}', employee, event_resource, hour)

    try:
        graph.serialize(destination=str(GRAPH_PATH), format='turtle')
        _run_audit(dept, resource, 314, 319, tmp_path / 'all.json', {name_a: 2, name_b: 1})
        _run_audit(dept, resource, 319, 319, tmp_path / 'boundary.json', {name_a: 1})
        _run_audit(other_dept, resource, 314, 319, tmp_path / 'department.json', {name_c: 1})
        _run_audit(dept, other_resource, 314, 319, tmp_path / 'resource.json', {name_b: 1})
    finally:
        GRAPH_PATH.write_bytes(original_graph)

    # Execute the exact required final command after restoring the supplied graph.
    _run_audit('Finance', 'Resource_ProjectX', 18, 23, REPORT, {'Alice': 2, 'Bob': 1})
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
