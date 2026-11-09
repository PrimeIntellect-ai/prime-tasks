#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import importlib.util
import io
import json
import math
import os
import re
import secrets
import socket
import subprocess
import sys

import dpkt
import pytest

WORKDIR = '/home/user/ticket_8992'
SCRIPT = os.path.join(WORKDIR, 'netmapper.py')
CAPTURE = os.path.join(WORKDIR, 'capture.pcap')
TOPOLOGY = os.path.join(WORKDIR, 'topology.json')
RESOLUTION = os.path.join(WORKDIR, 'resolution.log')


def capture_counts():
    nodes = {}
    with open(CAPTURE, 'rb') as f:
        for _, buf in dpkt.pcap.Reader(f):
            eth = dpkt.ethernet.Ethernet(buf)
            if not isinstance(eth.data, dpkt.ip.IP):
                continue
            src = socket.inet_ntoa(eth.data.src)
            dst = socket.inet_ntoa(eth.data.dst)
            nodes.setdefault(src, {'sent': 0, 'recv': 0})
            nodes.setdefault(dst, {'sent': 0, 'recv': 0})
            nodes[src]['sent'] += 1
            nodes[dst]['recv'] += 1
    return nodes


def simulate(ratios, initial_weights):
    weights = dict(initial_weights)
    for iteration in range(1, 10001):
        max_change = 0.0
        for ip, ratio in ratios.items():
            old = weights[ip]
            new = old + 0.1 * (ratio - old)
            max_change = max(max_change, abs(new - old))
            weights[ip] = new
        if max_change < 0.001:
            return iteration, weights
    pytest.fail('The corrected convergence calculation did not converge within 10000 iterations.')


@pytest.fixture(scope='session')
def run_state():
    assert os.path.isfile(SCRIPT), 'The repaired netmapper.py is missing.'
    assert not os.path.islink(SCRIPT), 'netmapper.py must be an actual repaired file, not a symlink.'
    with open(SCRIPT, 'rb') as f:
        compile(f.read(), SCRIPT, 'exec')

    if os.path.exists(TOPOLOGY):
        os.remove(TOPOLOGY)

    try:
        proc = subprocess.run(
            [sys.executable, SCRIPT],
            cwd=WORKDIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('The repaired netmapper.py did not terminate, indicating convergence still fails.')

    assert proc.returncode == 0, (
        f'netmapper.py exited with status {proc.returncode}. '
        f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    )
    assert os.path.isfile(TOPOLOGY), 'Running the fixed script did not create topology.json.'

    matches = re.findall(r'Converged in\s+(\d+)\s+iterations', proc.stdout)
    assert len(matches) == 1, f'Expected one convergence iteration report on stdout, got {proc.stdout!r}.'
    printed_iterations = int(matches[0])
    assert printed_iterations > 0

    with open(TOPOLOGY, 'r') as f:
        topology = json.load(f)
    return topology, printed_iterations


def test_resolution_log_exists():
    assert os.path.isfile(RESOLUTION), 'The file /home/user/ticket_8992/resolution.log is missing.'


def test_resolution_log_content(run_state):
    expected_nodes = capture_counts()
    anomalous = sorted(
        ip for ip, counts in expected_nodes.items()
        if (counts['sent'] == 0) != (counts['recv'] == 0)
    )
    assert anomalous == ['10.99.99.99'], 'The anomalous node must be derived from the supplied capture.'

    with open(RESOLUTION, 'r') as f:
        raw = f.read()
    assert re.fullmatch(r'[^\r\n]+\r?\n[0-9]+(?:\r?\n)?', raw), (
        'resolution.log must contain strictly the IP on line 1 and the integer iteration count on line 2.'
    )
    lines = raw.splitlines()
    assert len(lines) == 2
    assert lines[0] == anomalous[0]
    iterations = int(lines[1])
    assert iterations > 0
    assert iterations == run_state[1], 'resolution.log must report the iteration count printed by the executed script.'


def test_topology_json_exists_and_valid(run_state):
    data, printed_iterations = run_state
    expected = capture_counts()

    assert isinstance(data, dict), 'topology.json should contain a JSON object (dictionary) of nodes.'
    assert '10.99.99.99' in data, "The anomalous IP '10.99.99.99' should be present in topology.json."
    assert set(data) == set(expected), 'topology.json does not contain exactly the nodes found in capture.pcap.'

    ratios = {}
    for ip, node_data in data.items():
        assert isinstance(node_data, dict)
        assert node_data.get('sent') == expected[ip]['sent'], f'Incorrect sent count for {ip}.'
        assert node_data.get('recv') == expected[ip]['recv'], f'Incorrect receive count for {ip}.'
        assert 'weight' in node_data, f"Node {ip} is missing a 'weight' value in topology.json."
        assert isinstance(node_data['weight'], (int, float)) and not isinstance(node_data['weight'], bool)
        assert math.isfinite(node_data['weight']), f'Node {ip} has a non-finite weight.'
        assert 'ratio' in node_data, f'Node {ip} is missing its calculated ratio.'
        assert isinstance(node_data['ratio'], (int, float)) and not isinstance(node_data['ratio'], bool)
        assert math.isfinite(node_data['ratio']), f'Node {ip} has a non-finite ratio.'
        if expected[ip]['recv'] > 0:
            assert node_data['ratio'] == pytest.approx(expected[ip]['sent'] / expected[ip]['recv'])
        ratios[ip] = float(node_data['ratio'])

    expected_iterations, expected_weights = simulate(ratios, {ip: 1.0 for ip in ratios})
    assert printed_iterations == expected_iterations, 'The reported iteration count does not match the corrected algorithm.'
    for ip in ratios:
        assert data[ip]['weight'] == pytest.approx(expected_weights[ip], rel=1e-10, abs=1e-10), (
            f'Node {ip} weight was not produced by the corrected convergence update.'
        )


def load_submission_module():
    name = 'submitted_netmapper_' + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_calculate_node_weights_on_derived_inputs():
    module = load_submission_module()
    assert callable(getattr(module, 'calculate_node_weights', None))

    nodes = {}
    for i in range(4):
        sent = 1 + secrets.randbelow(30)
        recv = 1 + secrets.randbelow(30)
        nodes[f'198.51.100.{i + 1}'] = {'sent': sent, 'recv': recv, 'weight': 1.0}

    ratios = {ip: item['sent'] / item['recv'] for ip, item in nodes.items()}
    expected_iterations, expected_weights = simulate(ratios, {ip: 1.0 for ip in nodes})
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        result = module.calculate_node_weights(nodes)

    match = re.search(r'Converged in\s+(\d+)\s+iterations', output.getvalue())
    assert match, 'calculate_node_weights did not print its convergence iteration count.'
    assert int(match.group(1)) == expected_iterations
    assert result is nodes
    for ip in nodes:
        assert nodes[ip]['ratio'] == pytest.approx(ratios[ip])
        assert nodes[ip]['weight'] == pytest.approx(expected_weights[ip], rel=1e-10, abs=1e-10)

    zero_receive = {'203.0.113.77': {'sent': 7, 'recv': 0, 'weight': 1.0}}
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        zero_result = module.calculate_node_weights(zero_receive)
    assert zero_result is zero_receive, 'The zero-receive node was not handled successfully.'
    assert math.isfinite(float(zero_receive['203.0.113.77']['ratio']))
    assert math.isfinite(float(zero_receive['203.0.113.77']['weight']))
    assert re.search(r'Converged in\s+\d+\s+iterations', output.getvalue())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
