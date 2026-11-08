#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import sys
import random
import subprocess
import importlib.util
from collections import defaultdict

EXECUTOR_PATH = "/app/vendored/py-graph-engine/core/executor.py"
ANALYZE_PATH = "/home/user/analyze.py"
RESULTS_PATH = "/home/user/centrality_results.json"
DATA_PATH = "/home/user/data/papers.jsonl"


def get_truth_centrality(data_path):
    centrality = defaultdict(int)
    with open(data_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            paper = json.loads(line)
            year = paper.get("year", 0)
            if year >= 2010:
                authors = paper.get("authors", [])
                num_authors = len(authors)
                if num_authors > 1:
                    for author in authors:
                        centrality[author] += (num_authors - 1)
    return dict(centrality)


def unoptimized_build_edge_list(srcs, tgts):
    edges = []
    for s in srcs:
        for t in tgts:
            if s['ref_id'] == t['node_id']:
                edges.append((s['node_id'], t['node_id'], s['weight']))
    return edges


def load_executor():
    assert os.path.isfile(EXECUTOR_PATH), "Executor file missing"
    spec = importlib.util.spec_from_file_location("executor_under_test", EXECUTOR_PATH)
    executor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(executor)
    assert callable(getattr(executor, "build_edge_list", None)), "build_edge_list is missing or not callable"
    return executor


def test_results_exist_and_accurate():
    assert os.path.isfile(ANALYZE_PATH), f"Analysis script not found at {ANALYZE_PATH}"
    assert os.path.isfile(EXECUTOR_PATH), "Executor file missing"

    marker_path = "/tmp/verifier_build_edge_list_used"
    try:
        os.remove(marker_path)
    except FileNotFoundError:
        pass

    with open(EXECUTOR_PATH, "rb") as f:
        original_executor = f.read()

    instrumentation = b'''\n\n# Verification-time instrumentation\n_verifier_original_build_edge_list = build_edge_list\ndef build_edge_list(*args, **kwargs):\n    with open("/tmp/verifier_build_edge_list_used", "a") as _marker:\n        _marker.write("called\\n")\n    return _verifier_original_build_edge_list(*args, **kwargs)\n'''

    try:
        with open(EXECUTOR_PATH, "wb") as f:
            f.write(original_executor)
            f.write(instrumentation)

        try:
            os.remove(RESULTS_PATH)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        completed = subprocess.run(
            [sys.executable, ANALYZE_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert completed.returncode == 0, (
            "analyze.py failed when executed:\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(marker_path) and os.path.getsize(marker_path) > 0, (
            "analyze.py did not use the vendored package's build_edge_list function"
        )
    finally:
        with open(EXECUTOR_PATH, "wb") as f:
            f.write(original_executor)

    assert os.path.isfile(RESULTS_PATH), f"Results file not found at {RESULTS_PATH}"

    with open(RESULTS_PATH, 'r') as f:
        student_results = json.load(f)

    truth_results = get_truth_centrality(DATA_PATH)

    # Check MSE == 0.0 (exact match)
    all_authors = set(student_results.keys()).union(set(truth_results.keys()))
    mse = 0.0
    for author in all_authors:
        student_val = student_results.get(author, 0)
        truth_val = truth_results.get(author, 0)
        mse += (student_val - truth_val) ** 2

    if len(all_authors) > 0:
        mse /= len(all_authors)

    assert mse == 0.0, f"MSE is {mse}, expected 0.0. Centrality results do not match ground truth."


def test_build_edge_list_correctness():
    executor = load_executor()

    fixed_sources = [
        {'node_id': 's0', 'ref_id': 't2', 'weight': 7},
        {'node_id': 's1', 'ref_id': 'missing', 'weight': 3},
        {'node_id': 's2', 'ref_id': 't0', 'weight': 11},
        {'node_id': 's3', 'ref_id': 't2', 'weight': -2},
    ]
    fixed_targets = [
        {'node_id': 't0', 'val': 100},
        {'node_id': 't1', 'val': 101},
        {'node_id': 't2', 'val': 102},
    ]
    assert executor.build_edge_list(fixed_sources, fixed_targets) == unoptimized_build_edge_list(fixed_sources, fixed_targets)

    rng = random.Random(918273)
    for trial in range(12):
        target_count = 25 + trial
        targets = [
            {'node_id': f'target_{trial}_{i}', 'val': rng.randrange(100000)}
            for i in range(target_count)
        ]
        rng.shuffle(targets)
        valid_ids = [t['node_id'] for t in targets]
        sources = []
        for i in range(80 + trial * 3):
            ref_id = rng.choice(valid_ids) if rng.random() < 0.8 else f'absent_{trial}_{i}'
            sources.append({
                'node_id': f'source_{trial}_{i}',
                'ref_id': ref_id,
                'weight': rng.randint(-20, 50),
            })
        expected = unoptimized_build_edge_list(sources, targets)
        actual = executor.build_edge_list(sources, targets)
        assert actual == expected, f"build_edge_list returned incorrect edges on correctness trial {trial}"


def test_speedup_metric():
    executor = load_executor()

    # Generate synthetic data for benchmark
    N = 2000
    sources = [{'node_id': f's_{i}', 'ref_id': f't_{i % 500}', 'weight': 1} for i in range(N)]
    targets = [{'node_id': f't_{i}', 'val': i} for i in range(500)]

    # Benchmark agent's implementation
    start = time.perf_counter()
    agent_edges = executor.build_edge_list(sources, targets)
    agent_time = time.perf_counter() - start

    # Unoptimized O(N^2) implementation for baseline
    start_unopt = time.perf_counter()
    unopt_edges = unoptimized_build_edge_list(sources, targets)
    unopt_time = time.perf_counter() - start_unopt

    assert len(agent_edges) == len(unopt_edges), "Agent's build_edge_list returned incorrect number of edges"
    assert agent_edges == unopt_edges, "Agent's build_edge_list returned incorrect edge contents"

    speedup = unopt_time / max(agent_time, 1e-6)
    assert speedup >= 20.0, f"Speedup is {speedup:.2f}x, expected >= 20.0x"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
