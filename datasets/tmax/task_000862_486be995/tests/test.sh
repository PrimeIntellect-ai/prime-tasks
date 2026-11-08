#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import filecmp
import os
import random
import shutil
import stat
import subprocess
import tempfile


def generate_graph(num_nodes, num_edges):
    nodes = []
    types = ['User', 'Product', 'Category']
    for i in range(1, num_nodes + 1):
        nodes.append({
            'node_id': i,
            'node_type': random.choice(types),
            'weight': round(random.uniform(0.0, 100.0), 2)
        })

    edges = []
    rel_types = ['BUYS', 'BELONGS_TO', 'VIEWS']
    for _ in range(num_edges):
        edges.append({
            'source_id': random.randint(1, num_nodes),
            'target_id': random.randint(1, num_nodes),
            'relationship_type': random.choice(rel_types)
        })
    return nodes, edges


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20)


def test_fuzz_equivalence():
    oracle_path = '/app/legacy_engine'
    agent_path = '/home/user/query_engine'
    source_path = '/home/user/query_engine.cpp'

    assert os.path.isfile(oracle_path), f'Oracle not found at {oracle_path}'
    assert os.access(oracle_path, os.X_OK), 'Oracle not executable'

    assert os.path.isfile(agent_path), f'Agent binary not found at {agent_path}. Did you compile it?'
    assert os.access(agent_path, os.X_OK), f'Agent binary at {agent_path} is not executable.'
    assert not os.path.samefile(agent_path, oracle_path), 'Agent binary must not be the oracle itself.'
    assert not filecmp.cmp(agent_path, oracle_path, shallow=False), 'Agent binary is a byte-identical copy of the oracle.'
    with open(agent_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Agent executable must be a compiled ELF binary.'

    assert os.path.exists(source_path), f'C++ source not found at {source_path}.'
    source_stat = os.lstat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), 'query_engine.cpp must be a regular source file, not a symlink.'
    assert source_stat.st_size > 0, 'query_engine.cpp is empty.'

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_path = os.path.join(tmpdir, 'rebuilt_query_engine')
        compile_result = subprocess.run(
            ['g++', '-O3', '-std=c++11', '-static', source_path, '-o', rebuilt_path],
            capture_output=True,
            text=True,
            timeout=60
        )
        assert compile_result.returncode == 0, (
            'Failed to compile query_engine.cpp independently:\n' + compile_result.stderr
        )
        assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)

        # Run the independently rebuilt program in a minimal chroot. This makes
        # /app/legacy_engine and any copies or wrappers left elsewhere by the
        # submission unavailable to it.
        jail = os.path.join(tmpdir, 'jail')
        data_dir = os.path.join(jail, 'data')
        os.makedirs(data_dir)
        os.chmod(jail, 0o755)
        os.chmod(data_dir, 0o755)
        jailed_engine = os.path.join(jail, 'query_engine')
        shutil.copy2(rebuilt_path, jailed_engine)
        os.chmod(jailed_engine, 0o755)

        nodes_file = os.path.join(data_dir, 'nodes.csv')
        edges_file = os.path.join(data_dir, 'edges.csv')

        for i in range(100):
            num_nodes = random.randint(50, 500)
            num_edges = random.randint(100, 2000)
            nodes, edges = generate_graph(num_nodes, num_edges)

            with open(nodes_file, 'w', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=['node_id', 'node_type', 'weight'])
                writer.writeheader()
                writer.writerows(nodes)
            with open(edges_file, 'w', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=['source_id', 'target_id', 'relationship_type'])
                writer.writeheader()
                writer.writerows(edges)
            os.chmod(nodes_file, 0o644)
            os.chmod(edges_file, 0o644)

            offset = random.randint(0, 50)
            limit = random.randint(5, 100)

            cmd_oracle = [oracle_path, edges_file, nodes_file, str(offset), str(limit)]
            cmd_agent = [agent_path, edges_file, nodes_file, str(offset), str(limit)]
            cmd_rebuilt = [
                'chroot', '--userspec=65534:65534', jail,
                '/query_engine', '/data/edges.csv', '/data/nodes.csv',
                str(offset), str(limit)
            ]

            res_oracle = run(cmd_oracle)
            res_agent = run(cmd_agent)
            res_rebuilt = run(cmd_rebuilt)

            assert res_oracle.returncode == 0, f'Oracle failed on iteration {i} with error:\n{res_oracle.stderr}'
            assert res_agent.returncode == 0, f'Agent program failed on iteration {i} with error:\n{res_agent.stderr}'
            assert res_rebuilt.returncode == 0, (
                f'Independently rebuilt program failed in isolation on iteration {i} '
                f'with error:\n{res_rebuilt.stderr}'
            )

            if res_oracle.stdout != res_agent.stdout:
                raise AssertionError(
                    f'Mismatch on iteration {i}.\nCommand: {" ".join(cmd_agent)}\n'
                    f'Oracle output:\n{res_oracle.stdout}\nAgent output:\n{res_agent.stdout}\n'
                )
            if res_oracle.stdout != res_rebuilt.stdout:
                raise AssertionError(
                    f'Independently compiled source mismatched on iteration {i}.\n'
                    f'Oracle output:\n{res_oracle.stdout}\nRebuilt output:\n{res_rebuilt.stdout}\n'
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
