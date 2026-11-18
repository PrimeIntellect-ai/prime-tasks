#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_solution.py
import csv
import heapq
import os
import random
import subprocess

DATA_DIR = '/home/user/data'
RESULT_FILE = '/home/user/result.txt'
SOLVE_CPP = '/home/user/solve.cpp'
BINARY = '/tmp/solve_submission'
EXPECTED_PATH = 'W001,W002,W005,W006'
EXPECTED_DISTANCE = '45'

ORIGINAL = {
    'warehouses.csv': '''w_id,name,region
W001,Alpha,North
W002,Beta,North
W003,Gamma,East
W004,Delta,South
W005,Epsilon,West
W006,Zeta,Central
''',
    'routes.csv': '''src_w_id,dst_w_id,distance,risk_score
W001,W002,10,2
W001,W004,50,5
W001,W006,100,9
W002,W003,20,4
W002,W005,15,3
W004,W005,10,1
W005,W006,20,1
W002,W006,10,8
W003,W006,30,2
''',
    'inventory.csv': '''w_id,item_id,quantity
W001,ITEM-111,200
W003,ITEM-999,40
W005,ITEM-999,10
W006,ITEM-999,150
'''
}

def write_original():
    os.makedirs(DATA_DIR, exist_ok=True)
    for name, content in ORIGINAL.items():
        with open(os.path.join(DATA_DIR, name), 'w', newline='') as f:
            f.write(content)

def read_result():
    assert os.path.isfile(RESULT_FILE), f'The file {RESULT_FILE} was not created.'
    with open(RESULT_FILE, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]
    assert len(lines) == 2, f'Expected exactly 2 lines in {RESULT_FILE}, found {len(lines)}.'
    return lines[0], lines[1]

def assert_original_result():
    path, distance = read_result()
    assert path == EXPECTED_PATH, f"Expected path '{EXPECTED_PATH}', but got '{path}'."
    assert distance == EXPECTED_DISTANCE, f"Expected distance '{EXPECTED_DISTANCE}', but got '{distance}'."

def execute():
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    subprocess.run([BINARY], cwd='/home/user', check=True, timeout=10)

def write_random_dataset(rng):
    nodes = [f'W{i:03d}' for i in range(1, 9)]
    edges = {}

    # A safe directed chain guarantees that qualifying warehouses are reachable.
    for i in range(len(nodes) - 1):
        edges[(nodes[i], nodes[i + 1])] = (rng.randint(5, 25), rng.randint(1, 7))

    # Add unpredictable directed routes.
    for src in nodes:
        for dst in nodes:
            if src != dst and rng.random() < 0.32 and (src, dst) not in edges:
                edges[(src, dst)] = (rng.randint(3, 45), rng.randint(1, 10))

    # These tempting shortcuts must be rejected because risk 8 and above is forbidden.
    edges[('W001', 'W006')] = (1, 8)
    edges[('W001', 'W008')] = (1, 10)
    # A reverse-only cheap edge also checks that routes are treated as directed.
    edges[('W008', 'W001')] = (1, 1)

    with open(os.path.join(DATA_DIR, 'warehouses.csv'), 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['w_id', 'name', 'region'])
        for node in nodes:
            writer.writerow([node, 'Name-' + node, 'Region-' + str(rng.randint(1, 4))])

    with open(os.path.join(DATA_DIR, 'routes.csv'), 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['src_w_id', 'dst_w_id', 'distance', 'risk_score'])
        for (src, dst), (distance, risk) in sorted(edges.items()):
            writer.writerow([src, dst, distance, risk])

    with open(os.path.join(DATA_DIR, 'inventory.csv'), 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['w_id', 'item_id', 'quantity'])
        writer.writerow(['W002', 'ITEM-999', 49])
        writer.writerow(['W006', 'ITEM-999', 50])
        writer.writerow(['W008', 'ITEM-999', 80])
        writer.writerow(['W003', 'ITEM-111', 500])

    return nodes, edges, {'W006', 'W008'}

def oracle_distance(nodes, edges, targets):
    graph = {node: [] for node in nodes}
    for (src, dst), (distance, risk) in edges.items():
        if risk < 8:
            graph[src].append((dst, distance))
    distances = {'W001': 0}
    queue = [(0, 'W001')]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        for dst, weight in graph[node]:
            candidate = distance + weight
            if candidate < distances.get(dst, 10**30):
                distances[dst] = candidate
                heapq.heappush(queue, (candidate, dst))
    answer = min(distances.get(target, 10**30) for target in targets)
    assert answer < 10**30
    return answer

def validate_dynamic_result(nodes, edges, targets, optimum):
    path_text, distance_text = read_result()
    path = path_text.split(',')
    assert path and path[0] == 'W001', 'The path must start at W001.'
    assert path[-1] in targets, 'The path must end at a warehouse stocking at least 50 ITEM-999.'
    assert all(node in nodes for node in path), 'The path contains an unknown warehouse ID.'
    try:
        reported = int(distance_text)
    except ValueError:
        raise AssertionError('The second output line must be an integer distance.')

    actual = 0
    for src, dst in zip(path, path[1:]):
        assert (src, dst) in edges, f'Route {src}->{dst} does not exist.'
        weight, risk = edges[(src, dst)]
        assert risk < 8, f'Route {src}->{dst} has forbidden risk score {risk}.'
        actual += weight
    assert reported == actual, f'Reported distance {reported} does not equal path distance {actual}.'
    assert actual == optimum, f'Path distance {actual} is not the optimal distance {optimum}.'

def main():
    # Preserve the original existence and exact-content assertions.
    assert os.path.isfile(SOLVE_CPP), f'The C++ source file {SOLVE_CPP} is missing.'
    assert os.path.isfile(RESULT_FILE), f'The file {RESULT_FILE} was not created.'
    assert_original_result()

    write_original()
    subprocess.run(
        ['g++', '-std=c++17', '-O2', SOLVE_CPP, '-o', BINARY],
        check=True,
        timeout=30
    )

    # Execute the submitted artifact against the original inputs and retain the
    # original verifier's exact expected path and distance checks.
    execute()
    assert_original_result()

    # Exercise the program on verifier-generated inputs and derive each answer.
    rng = random.SystemRandom()
    for _ in range(3):
        nodes, edges, targets = write_random_dataset(rng)
        optimum = oracle_distance(nodes, edges, targets)
        execute()
        validate_dynamic_result(nodes, edges, targets, optimum)

    # Leave the task's original data and required result in place.
    write_original()
    execute()
    assert_original_result()

try:
    main()
finally:
    write_original()
PY_EOF

if python3 /tmp/verify_solution.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
