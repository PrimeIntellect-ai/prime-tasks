#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import signal
import subprocess
import time
from unittest import mock

import numpy as np
import pytest
import redis
import requests

APP_DIR = '/home/user/app'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def setup_module(module):
    # Ensure any existing services are stopped before starting fresh
    os.system("pkill -f uvicorn")
    os.system("pkill -f worker.py")
    os.system("pkill -f redis-server")
    time.sleep(1)


def teardown_module(module):
    # Cleanup after tests
    os.system("pkill -f uvicorn")
    os.system("pkill -f worker.py")
    os.system("pkill -f redis-server")


def test_regression_test_passes():
    """Verify that the student created a meaningful regression test and it passes."""
    test_file = '/home/user/app/test_serialization.py'
    assert os.path.exists(test_file), f"Regression test file {test_file} does not exist."

    result = subprocess.run(['pytest', test_file], capture_output=True, text=True)
    assert result.returncode == 0, f"Regression test failed to pass:\n{result.stdout}\n{result.stderr}"

    with open(test_file, 'r') as f:
        content = f.read()
    assert 'def test_roundtrip' in content, "test_roundtrip function not found in test_serialization.py"

    tree = ast.parse(content)
    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'test_roundtrip']
    assert functions, "test_roundtrip function not found in test_serialization.py"
    function = functions[0]

    constants = [n.value for n in ast.walk(function) if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
    for expected in (1.5, 2.3, 3.14):
        assert any(abs(float(value) - expected) < 1e-9 for value in constants), \
            "test_roundtrip must exercise the required [1.5, -2.3, 3.14] values"

    has_assert = any(isinstance(n, ast.Assert) for n in ast.walk(function))
    has_assert_call = any(
        isinstance(n, ast.Call) and (
            isinstance(n.func, ast.Name) and n.func.id.startswith('assert')
            or isinstance(n.func, ast.Attribute) and n.func.attr.startswith('assert')
        )
        for n in ast.walk(function)
    )
    assert has_assert or has_assert_call, "test_roundtrip must contain an assertion"


def test_real_api_worker_roundtrip_and_optimization():
    """Execute the API encoder and worker loop and independently validate their data and results."""
    api = load_module('submission_api', os.path.join(APP_DIR, 'api.py'))
    worker = load_module('submission_worker', os.path.join(APP_DIR, 'worker.py'))

    rng = np.random.default_rng(41729)
    expected_arrays = [rng.uniform(-10, 10, 50).astype('<f4') for _ in range(100)]

    class FakeAPIRedis:
        def __init__(self):
            self.payloads = []

        def lpush(self, key, payload):
            assert key == 'task_queue'
            assert isinstance(payload, (str, bytes)), "API must queue a serialized payload"
            self.payloads.append(payload)
            return len(self.payloads)

    api_redis = FakeAPIRedis()
    api.r = api_redis
    generated = iter(expected_arrays)

    def fake_uniform(*args, **kwargs):
        return next(generated).copy()

    with mock.patch.object(api.np.random, 'uniform', side_effect=fake_uniform):
        for _ in range(100):
            response = api.generate()
            assert response == {'status': 'queued'}

    assert len(api_redis.payloads) == 100

    class Completed(Exception):
        pass

    class FakeWorkerRedis:
        def __init__(self, payloads):
            self.payloads = list(payloads)
            self.increments = 0

        def brpop(self, key, timeout=1):
            assert key == 'task_queue'
            if not self.payloads:
                return None
            payload = self.payloads.pop(0)
            if isinstance(payload, str):
                payload = payload.encode('utf-8')
            return b'task_queue', payload

        def incr(self, key):
            assert key == 'processed_count'
            self.increments += 1
            if self.increments == 100:
                raise Completed()
            return self.increments

    fake_worker_redis = FakeWorkerRedis(api_redis.payloads)
    worker.r = fake_worker_redis
    original_gradient_descent = worker.gradient_descent
    decoded_inputs = []
    optimization_results = []

    def checked_gradient_descent(data, *args, **kwargs):
        decoded_inputs.append(np.asarray(data).copy())
        result = original_gradient_descent(data, *args, **kwargs)
        optimization_results.append(result)
        return result

    worker.gradient_descent = checked_gradient_descent

    def timeout_handler(signum, frame):
        raise TimeoutError('worker did not finish 100 real decoding/optimization calls')

    old_handler = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(8)
    start = time.monotonic()
    try:
        with pytest.raises(Completed):
            worker.run()
    finally:
        elapsed = time.monotonic() - start
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)

    assert fake_worker_redis.increments == 100
    assert len(decoded_inputs) == 100, "worker incremented processed_count without optimizing every task"
    assert len(optimization_results) == 100

    for expected, decoded, result in zip(expected_arrays, decoded_inputs, optimization_results):
        np.testing.assert_array_equal(decoded, expected)
        assert np.isfinite(result), "optimization produced a non-finite result"
        ordered = np.sort(expected.astype(np.float64))
        lower, upper = ordered[24], ordered[25]
        assert lower - 0.05 <= float(result) <= upper + 0.05, \
            "optimization result is not a geometric median of the decoded data"

    assert elapsed <= 3.0, f"100 real decode/optimization calls took {elapsed:.2f}s, exceeding 3 seconds"


def test_performance_metric():
    """Verify that the worker can process 100 tasks in <= 3.0 seconds."""
    proc = subprocess.Popen(['bash', '/home/user/app/start_services.sh'], cwd='/home/user/app')

    r = redis.Redis(host='localhost', port=6379, db=0)
    services_ready = False
    for _ in range(50):
        try:
            if r.ping():
                res = requests.get('http://localhost:8000/docs')
                if res.status_code == 200:
                    services_ready = True
                    break
        except Exception:
            pass
        time.sleep(0.1)

    assert services_ready, "Services failed to start properly."

    r.flushdb()

    start_time = time.time()
    for _ in range(100):
        res = requests.post('http://localhost:8000/generate')
        assert res.status_code == 200, "Failed to queue task via API"

    while True:
        processed = r.get('processed_count')
        if processed and int(processed) >= 100:
            break
        if time.time() - start_time > 10.0:
            pytest.fail("TIMEOUT: Worker took too long to process 100 tasks (exceeded 10 seconds).")
        time.sleep(0.05)

    duration = time.time() - start_time
    proc.terminate()

    assert duration <= 3.0, f"Performance metric failed: processing took {duration:.2f}s, which is > 3.0s threshold."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
