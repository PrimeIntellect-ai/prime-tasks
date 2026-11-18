#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid
import pytest


def test_process_graph_script_exists_and_executable():
    script_path = '/home/user/process_graph.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_top_servers_json_exists_and_correct():
    output_path = '/home/user/top_servers.json'
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_data = {
        "ap-south": "s5",
        "eu-west": "s3",
        "us-east": "s2"
    }

    assert data == expected_data, f"The content of {output_path} is incorrect. Expected {expected_data}, but got {data}."


def build_fixture(rng):
    for _ in range(100):
        tag = uuid.uuid4().hex[:10]
        datacenters = [f'dc-{tag}-{i}' for i in range(3)]
        nodes = []
        servers = []
        for dc_index, dc in enumerate(datacenters):
            for server_index in range(3):
                node = {
                    'id': f'srv-{tag}-{dc_index}-{server_index}',
                    'type': 'Server',
                    'datacenter': dc,
                }
                nodes.append(node)
                servers.append(node)
        nodes.extend([
            {'id': f'db-{tag}', 'type': 'Database', 'datacenter': datacenters[0]},
            {'id': f'client-{tag}', 'type': 'Client', 'datacenter': datacenters[1]},
        ])

        all_ids = [node['id'] for node in nodes]
        edges = []
        for server in servers:
            sid = server['id']
            other_ids = [node_id for node_id in all_ids if node_id != sid]
            edges.append({
                'src': sid,
                'dst': rng.choice(other_ids),
                'rel': 'NETWORK_LINK',
                'weight': rng.randint(3, 120),
            })
            edges.append({
                'src': rng.choice(other_ids),
                'dst': sid,
                'rel': 'NETWORK_LINK',
                'weight': rng.randint(3, 120),
            })

        for _ in range(8):
            src, dst = rng.sample(all_ids, 2)
            edges.append({
                'src': src,
                'dst': dst,
                'rel': rng.choice(['NETWORK_LINK', 'DB_CONNECTION', 'OWNS']),
                'weight': rng.randint(1, 250),
            })

        edges.append({
            'src': servers[0]['id'],
            'dst': f'db-{tag}',
            'rel': 'DB_CONNECTION',
            'weight': 1000000,
        })

        totals = {server['id']: 0 for server in servers}
        for edge in edges:
            if edge['rel'] != 'NETWORK_LINK':
                continue
            for server_id in totals:
                if edge['src'] == server_id or edge['dst'] == server_id:
                    totals[server_id] += edge['weight']

        expected = {}
        unique = True
        for dc in datacenters:
            candidates = [server['id'] for server in servers if server['datacenter'] == dc]
            values = [totals[server_id] for server_id in candidates]
            highest = max(values)
            if values.count(highest) != 1:
                unique = False
                break
            expected[dc] = next(server_id for server_id in candidates if totals[server_id] == highest)

        if unique:
            rng.shuffle(nodes)
            rng.shuffle(edges)
            return nodes, edges, expected

    raise AssertionError('Could not generate a fixture with unique maxima.')


def write_jsonl(path, records):
    with open(path, 'w') as output:
        for record in records:
            output.write(json.dumps(record, separators=(',', ':')) + '\n')


def test_script_recomputes_results_from_backup_files():
    script_path = '/home/user/process_graph.sh'
    nodes_path = '/home/user/backups/nodes.jsonl'
    edges_path = '/home/user/backups/edges.jsonl'
    output_path = '/home/user/top_servers.json'

    with open(nodes_path, 'rb') as f:
        original_nodes = f.read()
    with open(edges_path, 'rb') as f:
        original_edges = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, 'rb') as f:
            original_output = f.read()

    rng = random.SystemRandom()
    try:
        for _ in range(2):
            nodes, edges, expected = build_fixture(rng)
            write_jsonl(nodes_path, nodes)
            write_jsonl(edges_path, edges)
            if os.path.exists(output_path):
                os.remove(output_path)

            result = subprocess.run(
                [script_path],
                cwd='/home/user',
                env={**os.environ, 'HOME': '/home/user'},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, (
                f'The script exited with status {result.returncode}. '
                f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
            )
            assert os.path.isfile(output_path), f'The script did not generate {output_path}.'
            try:
                with open(output_path, 'r') as f:
                    actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f'The script generated invalid JSON: {exc}')
            assert actual == expected, (
                f'The script did not correctly aggregate the supplied backups. '
                f'Expected {expected}, but got {actual}.'
            )
    finally:
        with open(nodes_path, 'wb') as f:
            f.write(original_nodes)
        with open(edges_path, 'wb') as f:
            f.write(original_edges)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
