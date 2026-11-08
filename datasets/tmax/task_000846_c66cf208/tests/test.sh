#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest
import requests
from rdflib import Graph, Literal, Namespace
from rdflib.namespace import XSD

HOME = Path('/home/user')
DATA = HOME / 'data'
BASE = 'http://example.org/logistics/'
LOG = Namespace(BASE)
AUTH = ('analyst', 'graph123')
GATEWAY = 'http://127.0.0.1:8080'


def binding_values(payload, *variables):
    assert isinstance(payload, dict), 'SPARQL response should be a JSON object.'
    assert 'head' in payload or 'results' in payload or 'boolean' in payload, (
        'Response does not match standard SPARQL JSON format.'
    )
    assert 'results' in payload and isinstance(payload['results'].get('bindings'), list), (
        f'Expected SPARQL SELECT JSON results, got: {payload}'
    )
    rows = []
    for binding in payload['results']['bindings']:
        rows.append(tuple(binding[v]['value'] for v in variables))
    return rows


def post_sparql(base_url, query, auth=None):
    response = requests.post(
        base_url + '/sparql', json={'query': query}, auth=auth, timeout=5
    )
    assert response.status_code == 200, (
        f'Expected 200 OK, got {response.status_code}. Response: {response.text}'
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')


def test_required_artifacts_and_implementations():
    for path in [HOME / 'build_graph.py', HOME / 'api.py', HOME / 'nginx.conf', HOME / '.htpasswd']:
        assert path.is_file(), f'Required artifact {path} does not exist or is not a regular file.'

    build_source = (HOME / 'build_graph.py').read_text()
    api_source = (HOME / 'api.py').read_text()
    ast.parse(build_source)
    ast.parse(api_source)

    build_lower = build_source.lower()
    assert 'rdflib' in build_lower, 'build_graph.py must use RDFLib.'
    assert re.search(r'(^|\n)\s*(import csv|from csv import)', build_source), (
        'build_graph.py must read the CSV input using Python CSV support.'
    )
    assert 'cities.csv' in build_source and 'connections.csv' in build_source, (
        'build_graph.py must consume both supplied CSV files.'
    )
    assert 'graph.ttl' in build_source, 'build_graph.py must write graph.ttl.'

    api_lower = api_source.lower()
    assert 'fastapi' in api_lower, 'api.py must implement a FastAPI application.'
    assert 'rdflib' in api_lower, 'api.py must use RDFLib for graph/SPARQL operations.'
    assert 'networkx' in api_lower, 'api.py must use NetworkX.'
    assert 'digraph' in api_lower, 'api.py must construct a NetworkX directed graph.'
    assert any(term in api_lower for term in ('dijkstra', 'shortest_path', 'shortest_path_length')), (
        'api.py must use NetworkX shortest-path/Dijkstra functionality.'
    )
    assert '.query(' in api_source, 'api.py must execute a SPARQL query when projecting the graph.'
    assert '/sparql' in api_source and '/shortest-path' in api_source, (
        'api.py must define both required endpoints.'
    )


def test_graph_materialized():
    """Check and validate the RDF graph materialized at the required path."""
    graph_path = DATA / 'graph.ttl'
    assert graph_path.exists(), (
        'Graph file /home/user/data/graph.ttl does not exist. '
        'Did you run the graph materialization script?'
    )
    graph = Graph()
    graph.parse(graph_path, format='turtle')

    expected_edges = {
        ('Alpha', 'Beta'), ('Beta', 'Gamma'), ('Alpha', 'Delta'),
        ('Gamma', 'Delta'), ('Beta', 'Delta')
    }
    actual_edges = {
        (str(s).removeprefix(BASE + 'City/'), str(o).removeprefix(BASE + 'City/'))
        for s, o in graph.subject_objects(LOG.connectedTo)
    }
    assert actual_edges == expected_edges, f'Incorrect connectedTo triples: {actual_edges}'

    expected_costs = {'Alpha': {10, 50}, 'Beta': {15, 30}, 'Gamma': {10}}
    actual_costs = {}
    for subject, value in graph.subject_objects(LOG.cost):
        name = str(subject).removeprefix(BASE + 'City/')
        assert value.datatype == XSD.integer, f'Cost {value!r} is not an integer literal.'
        actual_costs.setdefault(name, set()).add(int(value))
    assert actual_costs == expected_costs, f'Incorrect cost triples: {actual_costs}'


def test_service_status_log():
    """Check if the service status log exists and indicates readiness."""
    log_path = HOME / 'service_status.log'
    assert log_path.exists(), f'Log file {log_path} does not exist.'
    content = log_path.read_text()
    assert 'SERVICES READY' in content, (
        f"Log file does not contain 'SERVICES READY'. Content: {content}"
    )


def test_nginx_configuration_and_auth_file():
    conf = (HOME / 'nginx.conf').read_text()
    uncommented = '\n'.join(line.split('#', 1)[0] for line in conf.splitlines())
    assert re.search(r'listen\s+127\.0\.0\.1:8080\s*;', uncommented), (
        'Nginx must listen on 127.0.0.1:8080.'
    )
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:8000/?\s*;', uncommented), (
        'Nginx must proxy requests to 127.0.0.1:8000.'
    )
    assert re.search(r'auth_basic\s+[^;]+;', uncommented), 'HTTP Basic Authentication is not configured.'
    assert re.search(r'auth_basic_user_file\s+/home/user/\.htpasswd\s*;', uncommented), (
        'Nginx must use /home/user/.htpasswd.'
    )
    for configured_user in re.findall(r'(?m)^\s*user\s+([^;\s]+)', uncommented):
        assert configured_user not in {'root', 'nobody'}, (
            'Nginx must not be configured to drop privileges to root or nobody.'
        )
    check = subprocess.run(
        ['htpasswd', '-vb', str(HOME / '.htpasswd'), 'analyst', 'graph123'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert check.returncode == 0, 'The required analyst:graph123 credentials are not in .htpasswd.'


def test_nginx_auth_required():
    """Verify that the Nginx gateway requires authentication."""
    try:
        response = requests.get(
            GATEWAY + '/shortest-path?start=Alpha&end=Delta', timeout=5
        )
    except requests.exceptions.ConnectionError:
        pytest.fail('Could not connect to Nginx on 127.0.0.1:8080. Is it running?')
    assert response.status_code == 401, (
        f'Expected 401 Unauthorized without auth, got {response.status_code}.'
    )
    assert 'basic' in response.headers.get('WWW-Authenticate', '').lower(), (
        'Nginx did not issue an HTTP Basic authentication challenge.'
    )
    bad = requests.get(
        GATEWAY + '/shortest-path?start=Alpha&end=Delta',
        auth=('analyst', 'wrong-password'), timeout=5
    )
    assert bad.status_code == 401, 'Nginx accepted an incorrect password.'


def test_shortest_path_endpoint():
    """Verify the original shortest path calculation for Alpha to Delta."""
    try:
        response = requests.get(
            GATEWAY + '/shortest-path?start=Alpha&end=Delta', auth=AUTH, timeout=5
        )
    except requests.exceptions.ConnectionError:
        pytest.fail('Could not connect to Nginx on 127.0.0.1:8080. Is it running?')
    assert response.status_code == 200, (
        f'Expected 200 OK, got {response.status_code}. Response: {response.text}'
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')
    assert 'path' in data, "Response JSON is missing the 'path' key."
    assert 'total_cost' in data, "Response JSON is missing the 'total_cost' key."
    expected_path = ['Alpha', 'Beta', 'Gamma', 'Delta']
    expected_cost = 35
    assert data['path'] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data['total_cost'] == expected_cost, (
        f"Expected total_cost {expected_cost}, but got {data['total_cost']}."
    )


def test_sparql_endpoint():
    """Verify that the SPARQL endpoint executes the supplied query correctly."""
    query = '''
    PREFIX log: <http://example.org/logistics/>
    SELECT ?s ?o WHERE { ?s log:connectedTo ?o . }
    '''
    payload = post_sparql(GATEWAY, query, AUTH)
    rows = set(binding_values(payload, 's', 'o'))
    expected = {
        (BASE + 'City/Alpha', BASE + 'City/Beta'),
        (BASE + 'City/Beta', BASE + 'City/Gamma'),
        (BASE + 'City/Alpha', BASE + 'City/Delta'),
        (BASE + 'City/Gamma', BASE + 'City/Delta'),
        (BASE + 'City/Beta', BASE + 'City/Delta'),
    }
    assert rows == expected, f'SPARQL endpoint returned incorrect graph rows: {rows}'


def test_z_randomized_materialization_and_api_behavior():
    """Execute the submitted artifacts against verifier-generated graph data."""
    token = secrets.token_hex(4)
    names = [f'V{token}{letter}' for letter in 'ABCDE']
    a = 3 + secrets.randbelow(15)
    b = 4 + secrets.randbelow(15)
    c = b + 20 + secrets.randbelow(20)
    d = 5 + secrets.randbelow(15)
    edges = [
        (1, 2, a), (1, 3, a), (2, 4, b), (3, 4, c), (4, 5, d)
    ]

    cities_path = DATA / 'cities.csv'
    connections_path = DATA / 'connections.csv'
    graph_path = DATA / 'graph.ttl'
    originals = {
        cities_path: cities_path.read_bytes(),
        connections_path: connections_path.read_bytes(),
        graph_path: graph_path.read_bytes(),
    }
    proc = None
    try:
        cities_path.write_text(
            'city_id,name,region\n' +
            ''.join(f'{i},{name},R{i}\n' for i, name in enumerate(names, 1))
        )
        connections_path.write_text(
            'from_id,to_id,cost\n' +
            ''.join(f'{src},{dst},{cost}\n' for src, dst, cost in edges)
        )
        if graph_path.exists():
            graph_path.unlink()

        built = subprocess.run(
            [sys.executable, str(HOME / 'build_graph.py')], cwd=str(HOME),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20
        )
        assert built.returncode == 0, f'build_graph.py failed when executed:\n{built.stdout}'
        assert graph_path.is_file(), 'Executing build_graph.py did not create graph.ttl.'

        graph = Graph()
        graph.parse(graph_path, format='turtle')
        expected_rdf_edges = {
            (BASE + 'City/' + names[src - 1], BASE + 'City/' + names[dst - 1])
            for src, dst, _ in edges
        }
        actual_rdf_edges = {(str(s), str(o)) for s, o in graph.subject_objects(LOG.connectedTo)}
        assert actual_rdf_edges == expected_rdf_edges, (
            f'Randomized RDF connections are incorrect: {actual_rdf_edges}'
        )
        expected_costs = {}
        for src, _, cost in edges:
            expected_costs.setdefault(BASE + 'City/' + names[src - 1], set()).add(cost)
        actual_costs = {}
        for subject, value in graph.subject_objects(LOG.cost):
            assert value.datatype == XSD.integer, 'Randomized costs must be integer literals.'
            actual_costs.setdefault(str(subject), set()).add(int(value))
        assert actual_costs == expected_costs, f'Randomized RDF costs are incorrect: {actual_costs}'

        proc = subprocess.Popen(
            [sys.executable, '-m', 'uvicorn', 'api:app', '--app-dir', str(HOME),
             '--host', '127.0.0.1', '--port', '18000'],
            cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            start_new_session=True
        )
        direct = 'http://127.0.0.1:18000'
        for _ in range(50):
            if proc.poll() is not None:
                output = proc.stdout.read().decode(errors='replace')
                pytest.fail(f'api.py could not be served by uvicorn:\n{output}')
            try:
                r = requests.get(
                    direct + f'/shortest-path?start={names[0]}&end={names[4]}',
                    timeout=0.3
                )
                if r.status_code < 500:
                    break
            except requests.RequestException:
                pass
            time.sleep(0.1)
        else:
            pytest.fail('The submitted FastAPI application did not start on the test port.')

        cases = [
            (names[0], names[3], [names[0], names[1], names[3]], a + b),
            (names[0], names[4], [names[0], names[1], names[3], names[4]], a + b + d),
            (names[2], names[4], [names[2], names[3], names[4]], c + d),
        ]
        for start, end, expected_path, expected_cost in cases:
            response = requests.get(
                direct + f'/shortest-path?start={start}&end={end}', timeout=5
            )
            assert response.status_code == 200, response.text
            result = response.json()
            assert result.get('path') == expected_path, (
                f'For randomized {start}->{end}, expected {expected_path}, got {result}'
            )
            assert result.get('total_cost') == expected_cost, (
                f'For randomized {start}->{end}, expected cost {expected_cost}, got {result}'
            )

        select_query = f'''
        PREFIX log: <{BASE}>
        SELECT ?o WHERE {{ <{BASE}City/{names[0]}> log:connectedTo ?o . }}
        '''
        selected = set(binding_values(post_sparql(direct, select_query), 'o'))
        assert selected == {
            (BASE + 'City/' + names[1],), (BASE + 'City/' + names[2],)
        }, f'Raw randomized SELECT query returned wrong results: {selected}'

        ask_query = f'''ASK {{ <{BASE}City/{names[4]}> <{BASE}connectedTo> <{BASE}City/{names[0]}> }}'''
        ask_result = post_sparql(direct, ask_query)
        assert ask_result.get('boolean') is False, (
            f'Raw randomized ASK query was not executed correctly: {ask_result}'
        )
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        for path, content in originals.items():
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
