#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid
from collections import defaultdict, deque

SOURCE = '/home/user/analyze_backups.cpp'
OUTPUT = '/home/user/audit_list.txt'
SERVERS = '/home/user/backup_metadata/servers.json'
RELATIONS = '/home/user/backup_metadata/storage_relations.csv'

ORIGINAL_EXPECTED = [
    'storage-C: 2',
    'storage-D: 2',
    'storage-W: 3',
    'storage-Y: 3',
    'storage-Z: 4',
    'storage-Omega: 5',
]


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def expected_for(servers, relations):
    graph = defaultdict(list)
    storage_nodes = set()

    for server in servers:
        server_id = server['server_id']
        for job in server.get('jobs', []):
            job_id = job['job_id']
            primary = job['primary_storage']
            graph[server_id].append(job_id)
            graph[job_id].append(primary)
            storage_nodes.add(primary)

    for source, replica in relations:
        graph[source].append(replica)
        storage_nodes.add(source)
        storage_nodes.add(replica)

    distances = {'db-srv-042': 0}
    queue = deque(['db-srv-042'])
    while queue:
        node = queue.popleft()
        for neighbor in graph[node]:
            if neighbor not in distances:
                distances[neighbor] = distances[node] + 1
                queue.append(neighbor)

    reachable = [(distances[node], node) for node in storage_nodes if node in distances]
    reachable.sort(key=lambda item: (item[0], item[1]))
    return [f'{node}: {distance}' for distance, node in reachable]


def write_fixture(servers, relations):
    with open(SERVERS, 'w') as f:
        json.dump(servers, f)
    with open(RELATIONS, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['source_storage', 'replica_storage'])
        writer.writerows(relations)


def run_program(executable):
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [executable], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f'Compiled analyzer exited with {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT), 'The compiled analyzer did not generate /home/user/audit_list.txt'
    return read_nonempty_lines(OUTPUT)


def main():
    # Preserve the original verifier's assertion on the submitted final output.
    assert os.path.isfile(OUTPUT), (
        f'The output file {OUTPUT} does not exist. Did your C++ program run and generate it?'
    )
    actual_lines = read_nonempty_lines(OUTPUT)
    assert actual_lines == ORIGINAL_EXPECTED, (
        f'The contents of {OUTPUT} do not match the expected output.\n'
        f"Expected:\n{chr(10).join(ORIGINAL_EXPECTED)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

    assert os.path.exists(SOURCE), f'{SOURCE} does not exist'
    source_stat = os.stat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f'{SOURCE} is not a regular file'
    assert source_stat.st_size > 0, f'{SOURCE} is empty'

    executable = os.path.join(tempfile.gettempdir(), 'analyze_backups_' + uuid.uuid4().hex)
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE, '-o', executable],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f'{SOURCE} failed to compile.\nstdout:\n{compile_result.stdout}\n'
        f'stderr:\n{compile_result.stderr}'
    )

    with open(SERVERS, 'rb') as f:
        original_servers = f.read()
    with open(RELATIONS, 'rb') as f:
        original_relations = f.read()
    with open(OUTPUT, 'rb') as f:
        original_output = f.read()

    try:
        # The artifact must regenerate the correct result for the supplied metadata.
        regenerated = run_program(executable)
        assert regenerated == ORIGINAL_EXPECTED, (
            'Running the compiled analyzer on the original metadata produced an incorrect audit list.\n'
            f'Expected: {ORIGINAL_EXPECTED}\nActual: {regenerated}'
        )

        # Exercise the analyzer on unpredictable metadata so a hardcoded audit file cannot pass.
        tag = uuid.uuid4().hex
        p1 = f'primary-{tag}-b'
        p2 = f'primary-{tag}-a'
        other = f'other-{tag}'
        r1 = f'replica-{tag}-c'
        r2 = f'replica-{tag}-a'
        r3 = f'replica-{tag}-b'
        r4 = f'archive-{tag}'
        disconnected = f'disconnected-{tag}'
        disconnected_replica = f'disconnected-replica-{tag}'

        servers = [
            {
                'server_id': 'db-srv-777',
                'jobs': [{'job_id': f'job-other-{tag}', 'primary_storage': other}],
            },
            {
                'server_id': 'db-srv-042',
                'jobs': [
                    {'job_id': f'job-two-{tag}', 'primary_storage': p2},
                    {'job_id': f'job-one-{tag}', 'primary_storage': p1},
                ],
            },
        ]
        relations = [
            (p1, r1),
            (p1, r2),
            (p2, r2),
            (r1, r3),
            (r2, r3),
            (r3, r4),
            (r4, r1),
            (other, r4),
            (disconnected, disconnected_replica),
        ]
        expected = expected_for(servers, relations)
        write_fixture(servers, relations)
        dynamic_actual = run_program(executable)
        assert dynamic_actual == expected, (
            'The compiled analyzer did not derive the audit list from changed metadata.\n'
            f'Expected:\n{chr(10).join(expected)}\n'
            f'Actual:\n{chr(10).join(dynamic_actual)}'
        )
        assert os.path.isfile(SOURCE) and stat.S_ISREG(os.stat(SOURCE).st_mode), (
            f'{SOURCE} must remain a regular file'
        )
    finally:
        with open(SERVERS, 'wb') as f:
            f.write(original_servers)
        with open(RELATIONS, 'wb') as f:
            f.write(original_relations)
        if os.path.lexists(OUTPUT):
            os.unlink(OUTPUT)
        with open(OUTPUT, 'wb') as f:
            f.write(original_output)
        if os.path.exists(executable):
            os.unlink(executable)


if __name__ == '__main__':
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
