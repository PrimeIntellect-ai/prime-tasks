#!/bin/bash
set +e
mkdir -p /logs/verifier

# Freeze the staging input so the reference cannot change while verification runs.
pkill -f '/app/worker.py' 2>/dev/null || true
pkill -f '/app/api_server.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import math
import os
import stat
import subprocess
from collections import defaultdict

import numpy as np
import pytest
import redis
from scipy.stats import wasserstein_distance

SCRIPT_PATH = '/home/user/prepare_data.py'
OUTPUT_PATH = '/home/user/processed_graph.json'


def numeric(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def reference_bootstrap(values, seed):
    values = np.asarray(values, dtype=float)
    rng = np.random.default_rng(seed)
    means = []
    remaining = 100000
    while remaining:
        batch = min(5000, remaining)
        indices = rng.integers(0, len(values), size=(batch, len(values)))
        means.append(values[indices].mean(axis=1))
        remaining -= batch
    means = np.concatenate(means)
    return (
        float(values.mean()),
        float(np.percentile(means, 2.5)),
        float(np.percentile(means, 97.5)),
    )


def test_prepare_data_and_processed_graph():
    assert os.path.lexists(SCRIPT_PATH), f'{SCRIPT_PATH} does not exist.'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_PATH} must be a regular Python file.'

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT_PATH} is not valid Python: {exc}')

    numeric_literals = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant)
        and isinstance(node.value, (int, float))
        and not isinstance(node.value, bool)
    }
    assert 500 in numeric_literals and 1000 in numeric_literals, (
        'prepare_data.py must implement the requested B=500 then B=1000 convergence run.'
    )
    source_lower = source.lower()
    assert any(term in source_lower for term in ('bootstrap', 'resample', 'choice', 'randint', 'integers')), (
        'prepare_data.py does not contain evidence of bootstrap resampling.'
    )

    try:
        client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
        original_items = client.lrange('raw_traffic', 0, -1)
    except Exception as exc:
        pytest.fail(f"Could not connect to Redis or read 'raw_traffic': {exc}")

    valid = []
    for raw in original_items:
        try:
            item = json.loads(raw)
            src = item['src']
            dst = item['dst']
            latency = float(item['latency'])
            if isinstance(src, str) and isinstance(dst, str) and math.isfinite(latency):
                valid.append((src, dst, latency))
        except Exception:
            pass
        if len(valid) == 1200:
            break

    assert len(valid) >= 1000, (
        f"Expected at least 1000 valid records in Redis, found {len(valid)}."
    )

    # Install a fixed, derived snapshot. The transformation keeps valid observational
    # records while ensuring a stale output made before this execution cannot pass.
    controlled = []
    expected_groups = defaultdict(list)
    for index, (src, dst, latency) in enumerate(valid):
        digest = hashlib.sha256(f'{src}\0{dst}'.encode()).digest()
        scale = 0.75 + digest[0] / 510.0
        offset = 1.0 + digest[1] / 51.0
        transformed = latency * scale + offset + (index % 7) * 0.003
        record = {'src': src, 'dst': dst, 'latency': transformed}
        controlled.append(json.dumps(record, separators=(',', ':')))
        expected_groups[(src, dst)].append(transformed)

    client.delete('raw_traffic')
    if controlled:
        client.rpush('raw_traffic', *controlled)

    try:
        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('prepare_data.py did not finish within 120 seconds.')
    assert result.returncode == 0, (
        f'prepare_data.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Output file {OUTPUT_PATH} is not valid JSON: {exc}')

    assert isinstance(data, dict), 'Top-level output must be a JSON object.'
    assert 'wasserstein_distance' in data, "Key 'wasserstein_distance' missing in output."
    assert 'edges' in data, "Key 'edges' missing in output."
    agent_wd = data['wasserstein_distance']
    assert numeric(agent_wd), "'wasserstein_distance' must be a finite number."
    assert isinstance(data['edges'], list), "'edges' must be a list."

    reported = {}
    required_fields = {'src', 'dst', 'mean_latency', 'ci_lower', 'ci_upper'}
    for edge in data['edges']:
        assert isinstance(edge, dict), 'Every edge must be a JSON object.'
        assert set(edge) == required_fields, (
            f'Each edge must contain exactly {sorted(required_fields)}; got {sorted(edge)}.'
        )
        assert isinstance(edge['src'], str) and isinstance(edge['dst'], str), (
            "Edge 'src' and 'dst' must be strings."
        )
        for field in ('mean_latency', 'ci_lower', 'ci_upper'):
            assert numeric(edge[field]), f"Edge field '{field}' must be a finite number."
        key = (edge['src'], edge['dst'])
        assert key not in reported, f'Duplicate directed edge {key}.'
        assert edge['ci_lower'] <= edge['mean_latency'] <= edge['ci_upper'], (
            f'Confidence interval for edge {key} does not contain its mean.'
        )
        reported[key] = edge

    assert set(reported) == set(expected_groups), (
        f'Output directed edges differ from the Redis snapshot. Missing: '
        f'{sorted(set(expected_groups) - set(reported))}; extra: '
        f'{sorted(set(reported) - set(expected_groups))}'
    )

    true_edge_means = []
    for key, values in expected_groups.items():
        seed = int.from_bytes(hashlib.sha256(f'{key[0]}\0{key[1]}'.encode()).digest()[:8], 'big')
        true_mean, ref_lower, ref_upper = reference_bootstrap(values, seed)
        edge = reported[key]
        true_edge_means.append(true_mean)

        assert abs(edge['mean_latency'] - true_mean) <= 0.30, (
            f'Mean latency for edge {key} is inaccurate: reported '
            f"{edge['mean_latency']}, expected approximately {true_mean}."
        )
        width = ref_upper - ref_lower
        ci_tolerance = max(0.40, 0.12 * width)
        assert abs(edge['ci_lower'] - ref_lower) <= ci_tolerance, (
            f'Lower 95% bootstrap bound for edge {key} is inaccurate: reported '
            f"{edge['ci_lower']}, reference {ref_lower}, tolerance {ci_tolerance}."
        )
        assert abs(edge['ci_upper'] - ref_upper) <= ci_tolerance, (
            f'Upper 95% bootstrap bound for edge {key} is inaccurate: reported '
            f"{edge['ci_upper']}, reference {ref_upper}, tolerance {ci_tolerance}."
        )

    # Preserve the original Wasserstein assertion, now against the frozen snapshot.
    edge_means = np.asarray(true_edge_means, dtype=float)
    mean_of_means = np.mean(edge_means)
    std_of_means = np.std(edge_means, ddof=0)
    if std_of_means > 0:
        standardized_means = (edge_means - mean_of_means) / std_of_means
    else:
        standardized_means = np.zeros_like(edge_means)

    np.random.seed(42)
    reference_normal = np.random.normal(0, 1, 100000)
    ref_wd = wasserstein_distance(standardized_means, reference_normal)
    error = abs(agent_wd - ref_wd)
    threshold = 0.05
    assert error <= threshold, (
        f'Absolute error of wasserstein_distance {error:.4f} exceeds threshold '
        f'{threshold}. Agent reported: {agent_wd}, Reference computed: {ref_wd:.4f}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
