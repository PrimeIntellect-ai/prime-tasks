#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
from pathlib import Path
import secrets
import subprocess

import pytest

HOME = Path('/home/user')
LOCATIONS = HOME / 'locations.csv'
ROUTES = HOME / 'routes.csv'
OUTPUT = HOME / 'shortest_path.json'


def load_output():
    assert OUTPUT.is_file(), f"File not found: {OUTPUT}. Ensure your script generated the output file."
    try:
        with OUTPUT.open('r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT} does not contain valid JSON.")


def test_shortest_path_json_exists_and_correct():
    data = load_output()

    expected_path = [
        'Warehouse_Alpha',
        'Hub_Beta',
        'Hub_Gamma',
        'Hub_Delta',
        'Store_Omega',
    ]
    expected_distance = 60

    assert 'path' in data, "Key 'path' is missing in the JSON output."
    assert 'total_distance' in data, "Key 'total_distance' is missing in the JSON output."
    assert data['path'] == expected_path, (
        f"The computed path is incorrect.\nExpected: {expected_path}\nGot: {data['path']}"
    )
    assert data['total_distance'] == expected_distance, (
        f"The computed total_distance is incorrect.\n"
        f"Expected: {expected_distance}\nGot: {data['total_distance']}"
    )


def find_candidate_scripts():
    candidates = []
    excluded = {LOCATIONS.resolve(), ROUTES.resolve(), OUTPUT.resolve()}
    for path in HOME.rglob('*'):
        if not path.is_file() or any(part.startswith('.') for part in path.relative_to(HOME).parts):
            continue
        if path.resolve() in excluded:
            continue
        try:
            prefix = path.read_bytes()[:256]
        except OSError:
            continue
        suffix = path.suffix.lower()
        has_shebang = prefix.startswith(b'#!')
        if suffix in {'.py', '.sh', '.bash'} or has_shebang or os.access(path, os.X_OK):
            candidates.append(path)
    return candidates


def shortest_distance(node_ids, routes, source, target):
    graph = {node_id: [] for node_id in node_ids}
    for src, dst, weight in routes:
        graph[src].append((dst, weight))

    distances = {source: 0}
    queue = [(0, source)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == target:
            return distance
        for neighbor, weight in graph[node]:
            candidate = distance + weight
            if candidate < distances.get(neighbor, float('inf')):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))
    raise AssertionError('Generated test graph unexpectedly has no path')


def command_for(path):
    if path.suffix.lower() == '.py':
        return ['python3', str(path)]
    if path.suffix.lower() in {'.sh', '.bash'}:
        return ['bash', str(path)]
    prefix = path.read_bytes()[:128]
    if b'python' in prefix.split(b'\n', 1)[0]:
        return ['python3', str(path)]
    if b'sh' in prefix.split(b'\n', 1)[0]:
        return ['bash', str(path)]
    return [str(path)]


def test_saved_solution_processes_changed_csv_data_dynamically():
    candidates = find_candidate_scripts()
    assert candidates, (
        'No runnable Python or shell solution artifact was found under /home/user. '
        'A precomputed JSON file alone is insufficient.'
    )

    original_locations = LOCATIONS.read_bytes()
    original_routes = ROUTES.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    rng = secrets.SystemRandom()
    node_ids = rng.sample(range(20, 500), 7)
    source = node_ids[rng.randrange(len(node_ids))]
    remaining = [n for n in node_ids if n != source]
    target = remaining.pop(rng.randrange(len(remaining)))
    names = {
        source: 'Warehouse_Alpha',
        target: 'Store_Omega',
    }
    token = secrets.token_hex(5)
    for index, node_id in enumerate(remaining):
        names[node_id] = f'Hub_{token}_{index}'

    middle = remaining[:]
    rng.shuffle(middle)
    guaranteed_path = [source] + middle[:3] + [target]
    route_map = {}
    for left, right in zip(guaranteed_path, guaranteed_path[1:]):
        route_map[(left, right)] = rng.randint(3, 30)
    for left in node_ids:
        for right in node_ids:
            if left != right and (left, right) not in route_map and rng.random() < 0.32:
                route_map[(left, right)] = rng.randint(8, 90)
    routes = [(left, right, weight) for (left, right), weight in route_map.items()]
    expected_distance = shortest_distance(node_ids, routes, source, target)
    edge_weights = {(left, right): weight for left, right, weight in routes}
    name_to_id = {name: node_id for node_id, name in names.items()}

    try:
        with LOCATIONS.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['loc_id', 'loc_name'])
            for node_id in node_ids:
                writer.writerow([node_id, names[node_id]])
        with ROUTES.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['source_id', 'dest_id', 'distance'])
            writer.writerows(routes)

        failures = []
        for candidate in candidates:
            LOCATIONS.write_text(LOCATIONS.read_text())
            ROUTES.write_text(ROUTES.read_text())
            if OUTPUT.exists():
                OUTPUT.unlink()
            try:
                result = subprocess.run(
                    command_for(candidate),
                    cwd=str(HOME),
                    env={**os.environ, 'HOME': str(HOME)},
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
            except Exception as exc:
                failures.append(f'{candidate}: {exc}')
                continue
            if result.returncode != 0 or not OUTPUT.is_file():
                failures.append(f'{candidate}: exit={result.returncode}, no valid output file')
                continue
            try:
                data = json.loads(OUTPUT.read_text())
                path = data['path']
                total = data['total_distance']
                assert isinstance(path, list) and len(path) >= 2
                assert path[0] == 'Warehouse_Alpha' and path[-1] == 'Store_Omega'
                ids = [name_to_id[name] for name in path]
                measured = sum(edge_weights[(a, b)] for a, b in zip(ids, ids[1:]))
                assert total == measured == expected_distance
                return
            except (AssertionError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
                failures.append(f'{candidate}: incorrect dynamic result ({exc})')

        pytest.fail('No saved solution artifact correctly processed randomized CSV data. ' + '; '.join(failures))
    finally:
        LOCATIONS.write_bytes(original_locations)
        ROUTES.write_bytes(original_routes)
        if original_output is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
