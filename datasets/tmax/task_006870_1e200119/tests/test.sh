#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest
from jsonschema import Draft7Validator, FormatChecker
from rdflib import Graph, Namespace, RDF, URIRef

SCRIPT = Path('/home/user/extract.py')
DATA_DIR = Path('/home/user/data')
GRAPH_PATH = DATA_DIR / 'network.ttl'
SCHEMA_PATH = DATA_DIR / 'schema.json'
AUDIT_DIR = Path('/tmp/extract_audit')
AUDIT_LOG = AUDIT_DIR / 'query.jsonl'

AUDIT_DIR.mkdir(exist_ok=True)
(AUDIT_DIR / 'sitecustomize.py').write_text(r'''
import json
import os
import rdflib
import rdflib.plugins.sparql as sparql

log_path = os.environ.get("EXTRACT_QUERY_AUDIT")

def emit(record):
    if log_path:
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record) + "\\n")

_original_query = rdflib.Graph.query

def audited_query(self, *args, **kwargs):
    positional_bindings = args[4] if len(args) > 4 else None
    bindings = kwargs.get("initBindings", positional_bindings)
    emit({
        "kind": "query",
        "query": repr(args[0]) if args else "",
        "bindings": repr(bindings),
        "args": repr(args),
        "kwargs": repr(kwargs),
    })
    return _original_query(self, *args, **kwargs)

rdflib.Graph.query = audited_query

_original_prepare = sparql.prepareQuery

def audited_prepare(queryString, *args, **kwargs):
    emit({"kind": "prepare", "query": str(queryString), "bindings": ""})
    return _original_prepare(queryString, *args, **kwargs)

sparql.prepareQuery = audited_prepare
''', encoding='utf-8')


def run_extract(type_name, check_query=True):
    AUDIT_LOG.unlink(missing_ok=True)
    env = os.environ.copy()
    env['EXTRACT_QUERY_AUDIT'] = str(AUDIT_LOG)
    env['PYTHONPATH'] = str(AUDIT_DIR) + os.pathsep + env.get('PYTHONPATH', '')
    result = subprocess.run(
        ['python3', str(SCRIPT), type_name],
        cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, (
        f'extract.py failed for {type_name}:\nstdout: {result.stdout}\nstderr: {result.stderr}'
    )

    if check_query:
        assert AUDIT_LOG.is_file(), 'extract.py did not execute an rdflib SPARQL query.'
        records = [json.loads(line) for line in AUDIT_LOG.read_text().splitlines() if line.strip()]
        query_calls = [record for record in records if record.get('kind') == 'query']
        assert query_calls, 'extract.py did not call rdflib.Graph.query().'
        combined_queries = ' '.join(record.get('query', '') for record in records).lower()
        assert 'count' in combined_queries, 'The SPARQL query must perform aggregation with COUNT.'
        assert 'connectedto' in combined_queries, 'The SPARQL query must query connectedTo edges.'
        expected_type = f'http://example.org/{type_name}'
        assert any(expected_type in record.get('bindings', '') for record in query_calls), (
            'The requested RDF type must be supplied to Graph.query via parameter bindings.'
        )
    return result


def load_and_validate(path):
    assert path.is_file(), f'Expected output file {path} does not exist.'
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'File {path} is not valid JSON.')
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft7Validator(schema, format_checker=FormatChecker()).validate(data)
    return data


def test_extract_script_exists():
    path = '/home/user/extract.py'
    assert os.path.isfile(path), f'Expected script {path} does not exist.'
    source = Path(path).read_text(encoding='utf-8')
    compile(source, path, 'exec')


def test_execute_required_types():
    Path('/home/user/output_Person.json').unlink(missing_ok=True)
    Path('/home/user/output_Organization.json').unlink(missing_ok=True)
    run_extract('Person')
    run_extract('Organization')


def test_output_person_json():
    path = '/home/user/output_Person.json'
    assert os.path.isfile(path), f'Expected output file {path} does not exist.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {path} is not valid JSON.')

    expected_data = [
        {'connection_count': 3, 'entity': 'http://example.org/Alice'},
        {'connection_count': 1, 'entity': 'http://example.org/Bob'},
        {'connection_count': 0, 'entity': 'http://example.org/Charlie'}
    ]

    assert isinstance(data, list), f'Data in {path} must be a JSON array.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} items in {path}, got {len(data)}.'

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get('entity') == expected['entity'], f"Item {i} in {path} has wrong entity. Expected {expected['entity']}, got {actual.get('entity')}."
        assert actual.get('connection_count') == expected['connection_count'], f"Item {i} in {path} has wrong connection_count. Expected {expected['connection_count']}, got {actual.get('connection_count')}."

    assert data == expected_data, 'Person output must contain exactly the schema-defined properties.'
    load_and_validate(Path(path))


def test_output_organization_json():
    path = '/home/user/output_Organization.json'
    assert os.path.isfile(path), f'Expected output file {path} does not exist.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {path} is not valid JSON.')

    expected_data = [
        {'connection_count': 4, 'entity': 'http://example.org/DataInc'},
        {'connection_count': 2, 'entity': 'http://example.org/TechCorp'},
        {'connection_count': 0, 'entity': 'http://example.org/WebLLC'}
    ]

    assert isinstance(data, list), f'Data in {path} must be a JSON array.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} items in {path}, got {len(data)}.'

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get('entity') == expected['entity'], f"Item {i} in {path} has wrong entity. Expected {expected['entity']}, got {actual.get('entity')}."
        assert actual.get('connection_count') == expected['connection_count'], f"Item {i} in {path} has wrong connection_count. Expected {expected['connection_count']}, got {actual.get('connection_count')}."

    assert data == expected_data, 'Organization output must contain exactly the schema-defined properties.'
    load_and_validate(Path(path))


def test_dynamic_type_query_aggregation_sorting_and_schema_validation():
    original_graph = GRAPH_PATH.read_bytes()
    original_schema = SCHEMA_PATH.read_bytes()
    token = secrets.token_hex(8)
    type_name = 'AuditType' + token
    output_path = Path(f'/home/user/output_{type_name}.json')
    ex = Namespace('http://example.org/')

    graph = Graph()
    entity_counts = [
        ('Zulu' + token, 0),
        ('Alpha' + token, 2),
        ('Middle' + token, 4),
    ]
    type_uri = ex[type_name]
    for local_name, count in entity_counts:
        subject = ex[local_name]
        graph.add((subject, RDF.type, type_uri))
        for index in range(count):
            graph.add((subject, ex.connectedTo, ex[f'Target{index}_{local_name}']))
    graph.add((ex['Unrelated' + token], RDF.type, ex.OtherType))

    try:
        graph.serialize(destination=str(GRAPH_PATH), format='turtle')
        output_path.unlink(missing_ok=True)
        run_extract(type_name)

        actual = load_and_validate(output_path)
        expected = []
        parsed = Graph().parse(str(GRAPH_PATH), format='turtle')
        for subject in parsed.subjects(RDF.type, URIRef(str(type_uri))):
            expected.append({
                'entity': str(subject),
                'connection_count': sum(1 for _ in parsed.objects(subject, ex.connectedTo)),
            })
        expected.sort(key=lambda item: item['entity'])
        assert actual == expected, 'Output must be derived from the current graph and sorted by entity.'
        assert all(type(item['connection_count']) is int for item in actual)

        rejecting_schema = {
            '$schema': 'http://json-schema.org/draft-07/schema#',
            'type': 'array',
            'maxItems': 0,
        }
        SCHEMA_PATH.write_text(json.dumps(rejecting_schema), encoding='utf-8')
        output_path.unlink(missing_ok=True)
        env = os.environ.copy()
        env['PYTHONPATH'] = str(AUDIT_DIR) + os.pathsep + env.get('PYTHONPATH', '')
        env['EXTRACT_QUERY_AUDIT'] = str(AUDIT_LOG)
        subprocess.run(
            ['python3', str(SCRIPT), type_name], cwd='/home/user', env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert not output_path.exists(), 'Output was written even though JSON schema validation failed.'
    finally:
        GRAPH_PATH.write_bytes(original_graph)
        SCHEMA_PATH.write_bytes(original_schema)
        output_path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
