#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import tempfile
from collections import defaultdict

import pytest

DETECTOR = '/home/user/detector.py'
SUMMARY = '/home/user/summarize_graph.py'
GRAPH_FILE = '/app/data/graph.json'
VENDORED = '/app/networkx-3.0'
NODE_LINK_FILE = '/app/networkx-3.0/networkx/readwrite/json_graph/node_link.py'


def run_detector(path):
    return subprocess.run(
        ['python3', DETECTOR, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def expected_is_evil(query):
    return (
        query.get('action') in {'delete', 'update', 'insert'}
        or any(p in {'password', 'ssn', 'auth_token'} for p in query.get('match_properties', []))
        or query.get('limit', 0) > 100
        or query.get('max_depth') == 'unbounded'
        or (isinstance(query.get('max_depth'), (int, float)) and query.get('max_depth') > 5)
    )


def calculate_top_nodes(graph_data):
    degrees = defaultdict(int)
    nodes = set()
    for node in graph_data.get('nodes', []):
        node_id = node.get('id')
        if node_id is not None:
            nodes.add(node_id)
    for link in graph_data.get('links', []):
        source = link.get('source')
        target = link.get('target')
        if source is not None and target is not None:
            degrees[source] += 1
            degrees[target] += 1
            nodes.add(source)
            nodes.add(target)
    for node in nodes:
        degrees[node] += 0
    ordered = sorted(degrees.items(), key=lambda item: (-item[1], str(item[0])))
    return [{'id': node, 'degree': degree} for node, degree in ordered[:5]]


def test_networkx_fixed():
    assert os.path.isfile(NODE_LINK_FILE), f'File {NODE_LINK_FILE} is missing.'
    with open(NODE_LINK_FILE, 'r') as f:
        content = f.read()
    assert 'source="src_bad"' not in content, 'The deliberate perturbation source="src_bad" is still present in node_link.py.'

    sys.path.insert(0, VENDORED)
    try:
        for name in list(sys.modules):
            if name == 'networkx' or name.startswith('networkx.'):
                del sys.modules[name]
        import networkx as nx
        from networkx.readwrite import json_graph

        assert os.path.realpath(nx.__file__).startswith(os.path.realpath(VENDORED) + os.sep)
        graph = nx.MultiDiGraph()
        graph.add_node('alpha', label='A')
        graph.add_node('beta', label='B')
        graph.add_edge('alpha', 'beta', key='edge-1', weight=7)
        serialized = json_graph.node_link_data(graph)
        assert serialized['links'][0]['source'] == 'alpha'
        assert serialized['links'][0]['target'] == 'beta'
        restored = json_graph.node_link_graph(serialized)
        assert restored.is_directed() and restored.is_multigraph()
        assert set(restored.nodes) == {'alpha', 'beta'}
        assert restored.has_edge('alpha', 'beta', key='edge-1')
        assert restored['alpha']['beta']['edge-1']['weight'] == 7

        input_data = {
            'directed': False,
            'multigraph': False,
            'graph': {},
            'nodes': [{'id': 'left'}, {'id': 'right'}],
            'links': [{'source': 'left', 'target': 'right', 'kind': 'test'}],
        }
        loaded = json_graph.node_link_graph(input_data)
        assert loaded.has_edge('left', 'right')
        assert loaded['left']['right']['kind'] == 'test'
    finally:
        sys.path.pop(0)


def test_detector_clean_corpus():
    assert os.path.isfile(DETECTOR), f'Detector script {DETECTOR} is missing.'
    clean_dir = '/app/corpus/clean/'
    assert os.path.isdir(clean_dir), f'Clean corpus directory {clean_dir} is missing.'
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, 'No clean corpus files found.'
    failed_files = []
    for path in clean_files:
        if run_detector(path).returncode != 0:
            failed_files.append(os.path.basename(path))
    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(clean_files)} clean modified (rejected). Offending files: {", ".join(failed_files)}')


def test_detector_evil_corpus():
    assert os.path.isfile(DETECTOR), f'Detector script {DETECTOR} is missing.'
    evil_dir = '/app/corpus/evil/'
    assert os.path.isdir(evil_dir), f'Evil corpus directory {evil_dir} is missing.'
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(evil_files) > 0, 'No evil corpus files found.'
    failed_files = []
    for path in evil_files:
        if run_detector(path).returncode != 1:
            failed_files.append(os.path.basename(path))
    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(evil_files)} evil bypassed (accepted). Offending files: {", ".join(failed_files)}')


def test_detector_generated_queries():
    assert os.path.isfile(DETECTOR), f'Detector script {DETECTOR} is missing.'
    cases = [
        {'action': 'read', 'match_properties': [], 'limit': 100, 'max_depth': 5},
        {'action': 'read', 'match_properties': ['name', 'age'], 'limit': 0, 'max_depth': 0},
        {'action': 'read', 'match_properties': ['name'], 'limit': 101, 'max_depth': 5},
        {'action': 'read', 'match_properties': ['name'], 'limit': 100, 'max_depth': 6},
        {'action': 'read', 'match_properties': ['name'], 'limit': 100, 'max_depth': 'unbounded'},
        {'action': 'delete', 'match_properties': ['name'], 'limit': 1, 'max_depth': 1},
        {'action': 'update', 'match_properties': [], 'limit': 1, 'max_depth': 1},
        {'action': 'insert', 'match_properties': ['public'], 'limit': 1, 'max_depth': 1},
        {'action': 'read', 'match_properties': ['display_name', 'password'], 'limit': 1, 'max_depth': 1},
        {'action': 'read', 'match_properties': ['ssn'], 'limit': 1, 'max_depth': 1},
        {'action': 'read', 'match_properties': ['auth_token'], 'limit': 1, 'max_depth': 1},
        {'action': 'read', 'match_properties': ['password_hash'], 'limit': 100, 'max_depth': 5},
    ]
    rng = random.SystemRandom()
    actions = ['read', 'read', 'read', 'delete', 'update', 'insert']
    properties = ['name', 'age', 'city', 'password', 'ssn', 'auth_token']
    limits = [1, 25, 99, 100, 101, 137]
    depths = [1, 3, 5, 6, 9, 'unbounded']
    for _ in range(36):
        selected = rng.sample(properties, rng.randint(0, 3))
        cases.append({
            'action': rng.choice(actions),
            'match_properties': selected,
            'limit': rng.choice(limits),
            'max_depth': rng.choice(depths),
            'request_tag': rng.randrange(1, 10**9),
        })

    with tempfile.TemporaryDirectory(prefix='query_inputs_') as directory:
        failures = []
        for index, query in enumerate(cases):
            path = os.path.join(directory, f'{rng.randrange(10**12):012d}_{index}.json')
            with open(path, 'w') as handle:
                json.dump(query, handle)
            expected_code = 1 if expected_is_evil(query) else 0
            result = run_detector(path)
            if result.returncode != expected_code:
                failures.append((query, expected_code, result.returncode, result.stderr.decode(errors='replace')))
        assert not failures, f'Detector misclassified generated queries: {failures[:3]}'


def test_top_nodes_json():
    output_file = '/home/user/top_nodes.json'
    assert os.path.isfile(output_file), f'Output file {output_file} is missing.'
    with open(output_file, 'r') as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{output_file} is not valid JSON.')
    assert os.path.isfile(GRAPH_FILE), f'Graph data file {GRAPH_FILE} is missing.'
    with open(GRAPH_FILE, 'r') as f:
        graph_data = json.load(f)
    expected_output = calculate_top_nodes(graph_data)
    assert student_output == expected_output, f'Student output {student_output} does not match expected output {expected_output}.'


def test_summarize_graph_executes_and_uses_vendored_networkx():
    assert os.path.isfile(SUMMARY), f'Summary script {SUMMARY} is missing.'
    assert os.path.isfile(GRAPH_FILE), f'Graph data file {GRAPH_FILE} is missing.'

    rng = random.SystemRandom()
    node_ids = [f'v_{rng.randrange(10**9):09d}_{i}' for i in range(11)]
    edge_pairs = [
        (0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
        (1, 2), (1, 3), (1, 6), (2, 4), (2, 7),
        (3, 8), (4, 9), (5, 6), (6, 7), (7, 8),
        (8, 9), (9, 10),
    ]
    graph_data = {
        'directed': False,
        'multigraph': False,
        'graph': {'verification_nonce': rng.randrange(10**12)},
        'nodes': [{'id': node} for node in node_ids],
        'links': [{'source': node_ids[a], 'target': node_ids[b]} for a, b in edge_pairs],
    }
    expected = calculate_top_nodes(graph_data)

    with open(GRAPH_FILE, 'rb') as handle:
        original_graph = handle.read()

    output_file = '/home/user/top_nodes.json'
    with tempfile.TemporaryDirectory(prefix='nx_probe_') as probe_dir:
        marker = os.path.join(probe_dir, f'marker_{rng.randrange(10**12)}')
        sitecustomize = os.path.join(probe_dir, 'sitecustomize.py')
        with open(sitecustomize, 'w') as handle:
            handle.write("""import os
import networkx as _nx
from networkx.readwrite import json_graph as _jg
from networkx.readwrite.json_graph import node_link as _nl
_original = _nl.node_link_graph
_module_file = os.path.realpath(_nl.__file__)
def _observed_node_link_graph(*args, **kwargs):
    with open(os.environ['NX_CALL_MARKER'], 'a') as _marker:
        _marker.write(_module_file + '\\n')
    return _original(*args, **kwargs)
_nl.node_link_graph = _observed_node_link_graph
_jg.node_link_graph = _observed_node_link_graph
_nx.node_link_graph = _observed_node_link_graph
""")

        try:
            with open(GRAPH_FILE, 'w') as handle:
                json.dump(graph_data, handle)
            if os.path.exists(output_file):
                os.remove(output_file)

            env = os.environ.copy()
            env['NX_CALL_MARKER'] = marker
            env['PYTHONPATH'] = probe_dir + os.pathsep + VENDORED
            result = subprocess.run(
                ['python3', SUMMARY],
                cwd='/home/user',
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert result.returncode == 0, f'summarize_graph.py failed: {result.stderr.decode(errors="replace")}'
            assert os.path.isfile(output_file), 'summarize_graph.py did not create /home/user/top_nodes.json.'
            with open(output_file) as handle:
                actual = json.load(handle)
            assert actual == expected, f'Summary output {actual} does not match expected output {expected}.'
            assert os.path.isfile(marker), 'summarize_graph.py did not call node_link_graph.'
            with open(marker) as handle:
                called_modules = [line.strip() for line in handle if line.strip()]
            vendored_root = os.path.realpath(VENDORED) + os.sep
            assert called_modules and all(path.startswith(vendored_root) for path in called_modules), \
                f'node_link_graph was not loaded from the vendored package: {called_modules}'
        finally:
            with open(GRAPH_FILE, 'wb') as handle:
                handle.write(original_graph)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
