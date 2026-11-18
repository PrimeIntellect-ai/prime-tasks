#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from decimal import Decimal


def expected_projection():
    with open('/home/user/nodes.csv', newline='') as f:
        nodes = {row['node_id']: row['status'] for row in csv.DictReader(f)}

    rows = []
    with open('/home/user/edges.csv', newline='') as f:
        for row in csv.DictReader(f):
            if (nodes.get(row['source_node']) == 'active' and
                    nodes.get(row['target_node']) == 'active' and
                    Decimal(row['cost']) > 0):
                rows.append((row['source_node'], row['target_node'], row['cost']))

    rows.sort(key=lambda row: (row[0], row[1]))
    return '\n'.join(','.join(row) for row in rows)


def lexicographic_shortest_path(edges):
    adjacency = {}
    for source, target, _cost in edges:
        adjacency.setdefault(source, set()).add(target)

    paths = [('START',)]
    while paths:
        next_paths = []
        for path in sorted(paths):
            if path[-1] == 'END':
                return list(path)
            for target in sorted(adjacency.get(path[-1], ())):
                if target not in path:
                    next_paths.append(path + (target,))
        paths = next_paths
    raise AssertionError('Generated test graph unexpectedly has no START-to-END path')


def format_path(path):
    return '\n'.join(f'{index},{node}' for index, node in enumerate(path))


def test_final_state_and_script_behavior():
    # Preserve the original fixed-fixture assertions.
    projected_path = '/home/user/projected_edges.csv'
    assert os.path.isfile(projected_path), f'File {projected_path} does not exist.'

    expected_content = '''C,D,15
C,E,10
D,END,5
E,F,5
START,A,10
START,C,5
START,E,20'''
    with open(projected_path, 'r') as f:
        content = f.read().strip()
    assert content == expected_content, f'Content of {projected_path} does not match the expected projected edges.'

    # Independently derive the projection from the supplied node and edge data.
    assert content == expected_projection(), 'projected_edges.csv is not the required filtered and sorted projection.'

    shortest_path = '/home/user/shortest_path.csv'
    assert os.path.isfile(shortest_path), f'File {shortest_path} does not exist.'

    expected_content = '''0,START
1,C
2,D
3,END'''
    with open(shortest_path, 'r') as f:
        content = f.read().strip()
    assert content == expected_content, f'Content of {shortest_path} does not match the expected shortest path.'

    script_path = '/home/user/find_path.sh'
    assert os.path.isfile(script_path), f'File {script_path} does not exist.'
    assert os.access(script_path, os.X_OK), f'File {script_path} is not executable.'
    assert stat.S_ISREG(os.stat(script_path).st_mode), f'File {script_path} is not a regular file.'

    with open(script_path, 'rb') as f:
        script_bytes = f.read()
    assert b'\x00' not in script_bytes, 'find_path.sh must be a Bash/AWK text script, not a binary.'
    try:
        script_text = script_bytes.decode('utf-8')
    except UnicodeDecodeError:
        raise AssertionError('find_path.sh must be a Bash/AWK text script.')
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ''
    assert first_line.startswith('#!') and any(name in first_line for name in ('bash', '/sh', 'awk', 'gawk')), \
        'find_path.sh must be directly executable as a Bash/sh/AWK script.'

    with open(projected_path, 'rb') as f:
        original_projected = f.read()
    with open(shortest_path, 'rb') as f:
        original_shortest = f.read()

    try:
        # Exercise the submitted script on fresh node names and graph layouts so
        # fixed output or an empty executable cannot pass.
        for _ in range(3):
            labels = sorted('N' + secrets.token_hex(5).upper() for _ in range(6))
            a, b, c, d, e, f = labels
            raw_edges = [
                ('START', a, '7'),
                ('START', b, '3'),
                (a, c, '12'),
                (b, d, '2'),
                (c, 'END', '9'),
                (d, 'END', '8'),
                (a, e, '1'),
                (e, f, '4'),
                (f, 'END', '6'),
                (c, a, '5'),
                (b, c, '11'),
            ]
            edges = sorted(raw_edges, key=lambda row: (row[0], row[1]))
            with open(projected_path, 'w') as out:
                out.write('\n'.join(','.join(row) for row in edges) + '\n')

            if os.path.exists(shortest_path):
                os.remove(shortest_path)

            result = subprocess.run(
                [script_path],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, \
                f'find_path.sh failed on a generated graph: {result.stderr}'

            # Conventional scripts print the path for shell redirection. Also
            # accept scripts that directly create the required output file.
            if result.stdout.strip():
                actual = result.stdout.strip()
            else:
                assert os.path.isfile(shortest_path), \
                    'find_path.sh produced neither path output nor shortest_path.csv.'
                with open(shortest_path, 'r') as f_out:
                    actual = f_out.read().strip()

            expected = format_path(lexicographic_shortest_path(edges))
            assert actual == expected, \
                f'find_path.sh returned the wrong shortest lexicographic path. Expected:\n{expected}\nGot:\n{actual}'
    finally:
        with open(projected_path, 'wb') as f_out:
            f_out.write(original_projected)
        with open(shortest_path, 'wb') as f_out:
            f_out.write(original_shortest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
