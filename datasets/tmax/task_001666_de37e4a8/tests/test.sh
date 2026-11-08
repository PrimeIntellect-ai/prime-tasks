#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import tempfile
import time

import pytest
import redis
import requests

BACKEND = '/home/user/app/backend/layout_engine'
REAL_BACKEND = '/home/user/app/backend/layout_engine.verifier-real'
API_URL = 'http://127.0.0.1:8000/api/layout'
LOG = '/tmp/layout_engine_invocations'


def run_engine(path, payload):
    lines = [str(payload['vertices'])]
    lines.extend(f"{u} {v}" for u, v in payload['edges'])
    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        f.write('\n'.join(lines) + '\n')
        input_path = f.name
    try:
        result = subprocess.run(
            [path, input_path], text=True, capture_output=True, timeout=3, check=True
        )
    finally:
        os.unlink(input_path)

    coords = []
    for line in result.stdout.strip().splitlines():
        x, y = line.split(',')
        coords.append({'x': float(x), 'y': float(y)})
    return coords


def assert_coordinates(actual, expected):
    assert isinstance(actual, list)
    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        assert isinstance(got, dict)
        assert 'x' in got and 'y' in got
        assert isinstance(got['x'], (int, float)) and not isinstance(got['x'], bool)
        assert isinstance(got['y'], (int, float)) and not isinstance(got['y'], bool)
        assert math.isfinite(got['x']) and math.isfinite(got['y'])
        assert got['x'] == pytest.approx(want['x'], abs=0.0006)
        assert got['y'] == pytest.approx(want['y'], abs=0.0006)


def invocation_inputs():
    if not os.path.exists(LOG):
        return []
    text = open(LOG).read()
    blocks = []
    for part in text.split('BEGIN\n')[1:]:
        body, marker, _ = part.partition('END\n')
        assert marker, 'Incomplete layout_engine invocation log'
        blocks.append([line.strip() for line in body.splitlines() if line.strip()])
    return blocks


def test_executable_exists_and_runs_correctly():
    """Check that the C backend is a real executable with correct output."""
    assert os.path.exists(BACKEND), 'The layout_engine executable was not found. Did you compile it?'
    assert os.path.isfile(BACKEND), 'layout_engine is not a regular file'
    assert os.access(BACKEND, os.X_OK), 'layout_engine is not executable'
    with open(BACKEND, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'layout_engine is not a compiled executable'

    payload = {'vertices': 5, 'edges': [[0, 1], [1, 3], [3, 4]]}
    coords = run_engine(BACKEND, payload)
    expected = [
        {
            'x': round(math.cos(2 * math.pi * i / 5), 3),
            'y': round(math.sin(2 * math.pi * i / 5), 3),
        }
        for i in range(5)
    ]
    assert_coordinates(coords, expected)

    os.replace(BACKEND, REAL_BACKEND)
    with open(BACKEND, 'w') as f:
        f.write('#!/bin/sh\n')
        f.write('{ echo BEGIN; cat "$1"; echo END; } >> ' + LOG + '\n')
        f.write('exec ' + REAL_BACKEND + ' "$@"\n')
    os.chmod(BACKEND, 0o755)
    open(LOG, 'w').close()


def test_api_reachable():
    """Check if the API is running and reachable."""
    payload = {'vertices': 3, 'edges': [[0, 1], [1, 2], [2, 0]]}
    try:
        response = requests.post(API_URL, json=payload, timeout=2)
        assert response.status_code == 200, f'API returned status code {response.status_code}'
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'API is not reachable on 127.0.0.1:8000: {exc}')


def test_api_correctness_serialization_subprocess_and_redis_cache():
    """Compare varied API results with the engine and verify subprocess and Redis caching."""
    client = redis.Redis(host='127.0.0.1', port=6379, db=0)
    client.ping()
    client.flushdb()
    open(LOG, 'w').close()

    rng = random.Random(time.time_ns())
    payloads = []
    for vertices in rng.sample(range(7, 31), 4):
        edges = []
        for _ in range(6):
            u = rng.randrange(vertices)
            v = rng.randrange(vertices)
            edges.append([u, v])
        payloads.append({'vertices': vertices, 'edges': edges})

    for payload in payloads:
        expected = run_engine(REAL_BACKEND, payload)
        before = len(invocation_inputs())

        response = requests.post(API_URL, json=payload, timeout=3)
        assert response.status_code == 200
        body = response.json()
        assert 'coordinates' in body, "Response JSON missing 'coordinates' key"
        assert len(body['coordinates']) == payload['vertices']
        assert_coordinates(body['coordinates'], expected)

        calls = invocation_inputs()
        assert len(calls) == before + 1, 'A cache miss did not invoke layout_engine exactly once'
        expected_input = [str(payload['vertices'])] + [f'{u} {v}' for u, v in payload['edges']]
        assert calls[-1] == expected_input, 'The request was not serialized correctly for layout_engine'

        cached_response = requests.post(API_URL, json=payload, timeout=2)
        assert cached_response.status_code == 200
        assert_coordinates(cached_response.json()['coordinates'], expected)
        assert len(invocation_inputs()) == before + 1, 'Identical request invoked layout_engine instead of using cache'

    keys = client.keys('*')
    assert keys, 'No Redis cache entries were created'
    cached_json_values = []
    for key in keys:
        if client.type(key) == b'string':
            raw = client.get(key)
            try:
                cached_json_values.append(json.loads(raw))
            except (TypeError, ValueError, UnicodeDecodeError):
                pass
    assert any(isinstance(value, dict) and 'coordinates' in value for value in cached_json_values), \
        'Redis does not contain a cached JSON layout result'


def test_api_correctness_original_shape_assertions():
    payload = {'vertices': 3, 'edges': [[0, 1], [1, 2], [2, 0]]}
    response = requests.post(API_URL, json=payload, timeout=2)
    assert response.status_code == 200
    body = response.json()
    assert 'coordinates' in body
    assert len(body['coordinates']) == 3
    for coord in body['coordinates']:
        assert 'x' in coord and 'y' in coord
        assert isinstance(coord['x'], (int, float))
        assert isinstance(coord['y'], (int, float))


def test_api_latency_metric():
    """The original metric: 100 cached requests must complete in at most 0.5 seconds."""
    payload = {'vertices': 3, 'edges': [[0, 1], [1, 2], [2, 0]]}
    warmup = requests.post(API_URL, json=payload, timeout=2)
    assert warmup.status_code == 200

    start = time.time()
    for _ in range(100):
        response = requests.post(API_URL, json=payload, timeout=2)
        assert response.status_code == 200
    total_time = time.time() - start

    threshold = 0.5
    assert total_time <= threshold, (
        f'Metric failed: total_time for 100 requests was {total_time:.4f}s, '
        f'threshold is <= {threshold}s. Redis caching might not be working properly.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
