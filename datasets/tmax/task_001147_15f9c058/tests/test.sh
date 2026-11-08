#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
from pathlib import Path
import secrets
import subprocess

ROOT = Path('/home/user/logistics_graph')
DATA = ROOT / 'data'
OUTPUT = ROOT / 'output'
RUN_SCRIPT = ROOT / 'run.sh'
COMPILED_BINARY = Path('/tmp/logistics_graph_submission')


def compute_expected_results(data_dir):
    edges_csv = os.path.join(data_dir, 'edges.csv')
    queries_csv = os.path.join(data_dir, 'queries.csv')

    graph = {}
    with open(edges_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src = row['source_id']
            tgt = row['target_id']
            dist = float(row['distance'])
            cost = float(row['cost'])
            if src not in graph:
                graph[src] = []
            graph[src].append((tgt, dist, cost))
            if tgt not in graph:
                graph[tgt] = []

    queries = []
    with open(queries_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            queries.append((row['source_id'], row['target_id']))

    results = []
    succ_count = 0
    fail_count = 0
    tot_dist = 0.0
    tot_cost = 0.0

    for src, tgt in queries:
        pq = [(0.0, 0.0, src, [src])]
        visited = set()
        found = False

        while pq:
            d, c, u, path = heapq.heappop(pq)
            if u in visited:
                continue
            visited.add(u)

            if u == tgt:
                results.append((src, tgt, d, c, '-'.join(path)))
                succ_count += 1
                tot_dist += d
                tot_cost += c
                found = True
                break

            for v, weight, cost_val in graph.get(u, []):
                if v not in visited:
                    heapq.heappush(pq, (d + weight, c + cost_val, v, path + [v]))

        if not found:
            results.append((src, tgt, -1.0, -1.0, 'NONE'))
            fail_count += 1

    return results, succ_count, fail_count, tot_dist, tot_cost


def clear_outputs():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ('results.csv', 'summary.txt'):
        path = OUTPUT / name
        if path.exists():
            path.unlink()


def execute(command):
    clear_outputs()
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert (OUTPUT / 'results.csv').is_file(), 'Execution did not create results.csv.'
    assert (OUTPUT / 'summary.txt').is_file(), 'Execution did not create summary.txt.'


def assert_outputs_match(data_dir):
    expected, exp_succ, exp_fail, exp_dist, exp_cost = compute_expected_results(str(data_dir))

    with open(OUTPUT / 'results.csv', newline='') as f:
        rows = list(csv.reader(f))
    assert rows, 'results.csv is empty.'
    assert rows[0] == ['source_id', 'target_id', 'total_distance', 'total_cost', 'path'], 'Incorrect results.csv header.'
    assert len(rows[1:]) == len(expected), 'results.csv must contain exactly one row per query.'

    for row, (src, tgt, dist, cost, path) in zip(rows[1:], expected):
        assert len(row) == 5, f'Invalid results.csv row: {row}'
        assert row[0] == src and row[1] == tgt, f'Incorrect query row order or IDs: {row}'
        assert abs(float(row[2]) - dist) < 1e-5, f'Incorrect distance for {src}->{tgt}.'
        assert abs(float(row[3]) - cost) < 1e-5, f'Incorrect cost for {src}->{tgt}.'
        assert row[4] == path, f'Incorrect path for {src}->{tgt}: expected {path}, got {row[4]}.'

    expected_summary = '\n'.join([
        f'Successful Queries: {exp_succ}',
        f'Failed Queries: {exp_fail}',
        f'Total Accumulated Distance: {exp_dist:.1f}',
        f'Total Accumulated Cost: {exp_cost:.1f}',
    ])
    with open(OUTPUT / 'summary.txt') as f:
        actual_summary = f.read().strip()
    assert actual_summary == expected_summary, f'Incorrect summary.txt. Expected:\n{expected_summary}\nGot:\n{actual_summary}'


def compile_cpp_submission():
    sources = sorted(
        str(p) for p in ROOT.rglob('*')
        if p.is_file() and p.suffix.lower() in ('.cpp', '.cc', '.cxx')
        and 'data' not in p.parts and 'output' not in p.parts
    )
    assert sources, 'No C++ source implementation was found.'
    completed = subprocess.run(
        ['g++', '-O3', '-std=c++17', *sources, '-o', str(COMPILED_BINARY)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f'C++17 compilation failed:\n{completed.stdout}\n{completed.stderr}'
    assert COMPILED_BINARY.is_file() and os.access(COMPILED_BINARY, os.X_OK)


def test_run_script_exists_and_executable():
    script_path = '/home/user/logistics_graph/run.sh'
    assert os.path.isfile(script_path), f'Build and run script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} must be executable.'


def test_cpp_implementation_compiles():
    compile_cpp_submission()


def test_run_script_executes_application():
    execute([str(RUN_SCRIPT)])


def test_results_csv_correctness():
    output_csv = '/home/user/logistics_graph/output/results.csv'
    assert os.path.isfile(output_csv), f'Output file {output_csv} is missing.'

    data_dir = '/home/user/logistics_graph/data'
    expected_results, _, _, _, _ = compute_expected_results(data_dir)

    actual_results = {}
    with open(output_csv, 'r') as f:
        lines = f.read().strip().split('\n')
        for line in lines:
            if line.startswith('source_id'):
                continue
            parts = line.split(',')
            if len(parts) == 5:
                src, tgt, dist, cost, path = parts
                actual_results[(src, tgt)] = (float(dist), float(cost), path)

    for src, tgt, exp_d, exp_c, exp_p in expected_results:
        assert (src, tgt) in actual_results, f'Missing query result for {src} to {tgt}.'
        act_d, act_c, act_p = actual_results[(src, tgt)]
        assert abs(act_d - exp_d) < 1e-5, f'Incorrect distance for {src}->{tgt}. Expected {exp_d}, got {act_d}.'
        assert abs(act_c - exp_c) < 1e-5, f'Incorrect cost for {src}->{tgt}. Expected {exp_c}, got {act_c}.'
        assert act_p == exp_p, f'Incorrect path for {src}->{tgt}. Expected {exp_p}, got {act_p}.'


def test_summary_txt_correctness():
    summary_txt = '/home/user/logistics_graph/output/summary.txt'
    assert os.path.isfile(summary_txt), f'Output file {summary_txt} is missing.'

    data_dir = '/home/user/logistics_graph/data'
    _, exp_succ, exp_fail, exp_dist, exp_cost = compute_expected_results(data_dir)

    with open(summary_txt, 'r') as f:
        content = f.read()

    assert f'Successful Queries: {exp_succ}' in content, 'Incorrect successful queries count.'
    assert f'Failed Queries: {exp_fail}' in content, 'Incorrect failed queries count.'

    exp_dist_str = f'Total Accumulated Distance: {exp_dist:.1f}'
    exp_cost_str = f'Total Accumulated Cost: {exp_cost:.1f}'

    assert exp_dist_str in content, f"Incorrect total distance. Expected '{exp_dist_str}'."
    assert exp_cost_str in content, f"Incorrect total cost. Expected '{exp_cost_str}'."


def test_generalizes_and_compiled_cpp_produces_outputs():
    original = {name: (DATA / name).read_bytes() for name in ('nodes.csv', 'edges.csv', 'queries.csv')}
    token = secrets.token_hex(4).upper()
    a, b, c, d, isolated = [f'{prefix}{token}' for prefix in ('P', 'Q', 'R', 'S', 'X')]
    w1 = 3 + secrets.randbelow(8)
    w2 = 4 + secrets.randbelow(8)
    w3 = 2 + secrets.randbelow(8)
    c1 = 11 + secrets.randbelow(9)
    c2 = 21 + secrets.randbelow(9)
    c3 = 31 + secrets.randbelow(9)

    try:
        (DATA / 'nodes.csv').write_text(
            'node_id,node_name\n' + ''.join(f'{node},Name_{i}\n' for i, node in enumerate((a, b, c, d, isolated)))
        )
        (DATA / 'edges.csv').write_text(
            'source_id,target_id,distance,cost\n'
            f'{a},{b},{w1}.0,{c1}.0\n'
            f'{b},{c},{w2}.0,{c2}.0\n'
            f'{a},{c},{w1 + w2 + 17}.0,1.0\n'
            f'{c},{d},{w3}.0,{c3}.0\n'
            f'{b},{d},{w2 + w3 + 19}.0,2.0\n'
        )
        (DATA / 'queries.csv').write_text(
            'source_id,target_id\n'
            f'{a},{d}\n'
            f'{a},{c}\n'
            f'{b},{d}\n'
            f'{isolated},{a}\n'
            f'{d},{d}\n'
        )

        execute([str(RUN_SCRIPT)])
        assert_outputs_match(DATA)

        if not COMPILED_BINARY.exists():
            compile_cpp_submission()
        execute([str(COMPILED_BINARY)])
        assert_outputs_match(DATA)
    finally:
        for name, contents in original.items():
            (DATA / name).write_bytes(contents)
        execute([str(RUN_SCRIPT)])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
