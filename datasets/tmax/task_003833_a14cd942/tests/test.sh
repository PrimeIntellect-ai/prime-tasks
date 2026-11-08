#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

import pytest
import redis
import requests

METRICS_PATH = Path('/home/user/metrics.json')
BENCHMARK_PATH = Path('/home/user/benchmark.py')
PROJECT_PATH = Path('/home/user/fast_artifact')
BACKEND_PATH = Path('/app/backend/app.py')

EXPECTED_BENCHMARK = '''import time
import json
import sys

try:
    import fast_artifact
except ImportError:
    print("fast_artifact not installed")
    sys.exit(1)

start = time.time()
for i in range(5000):
    fast_artifact.fetch_artifact(str(i))
end = time.time()

with open("/home/user/metrics.json", "w") as f:
    json.dump({"total_time_seconds": end - start}, f)
'''


def wait_for_backend(timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            response = requests.get('http://127.0.0.1:8080/api/artifact/verifier-ready', timeout=0.5)
            if response.status_code == 200:
                return response
        except requests.RequestException:
            pass
        time.sleep(0.1)
    pytest.fail('Flask backend did not become available on port 8080')


def validate_artifact(value, artifact_id):
    if isinstance(value, str):
        value = json.loads(value)
    assert isinstance(value, dict), 'fetch_artifact must return JSON text or a decoded object'
    assert value == {
        'id': artifact_id,
        'name': f'Artifact {artifact_id}',
        'size': 1024,
        'status': 'ok',
    }


def test_services_build_extension_and_real_benchmark():
    # The services must already have been started by the agent.
    try:
        assert redis.Redis(host='127.0.0.1', port=6379, socket_timeout=1).ping()
    except Exception as exc:
        pytest.fail(f'Redis is not running on port 6379: {exc}')

    initial_id = 'initial-' + uuid.uuid4().hex
    try:
        response = requests.get(f'http://127.0.0.1:8080/api/artifact/{initial_id}', timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f'Flask backend is not running on port 8080: {exc}')
    assert response.status_code == 200
    validate_artifact(response.json(), initial_id)

    # Confirm the requested Maturin build backend was configured.
    pyproject = PROJECT_PATH / 'pyproject.toml'
    assert pyproject.is_file(), 'pyproject.toml is missing'
    try:
        import tomllib
        config = tomllib.loads(pyproject.read_text())
    except Exception as exc:
        pytest.fail(f'pyproject.toml is invalid: {exc}')
    build_system = config.get('build-system', {})
    assert build_system.get('build-backend') == 'maturin', \
        "pyproject.toml must configure Maturin as its build backend"
    assert any(str(item).split('[', 1)[0].strip().lower() == 'maturin'
               for item in build_system.get('requires', [])), \
        "pyproject.toml build requirements must include maturin"

    # Import outside the source tree and reject a Python shim in place of the extension.
    old_cwd = os.getcwd()
    os.chdir('/tmp')
    try:
        sys.path = [p for p in sys.path if p not in ('', str(PROJECT_PATH))]
        importlib.invalidate_caches()
        module = importlib.import_module('fast_artifact')
    finally:
        os.chdir(old_cwd)
    module_file = getattr(module, '__file__', '') or ''
    assert any(module_file.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f'fast_artifact must be an installed native extension, got {module_file!r}'
    assert callable(getattr(module, 'fetch_artifact', None))
    probe_id = 'probe-' + uuid.uuid4().hex
    validate_artifact(module.fetch_artifact(probe_id), probe_id)

    # The supplied benchmark is part of the task and must not be replaced by a
    # script that merely self-reports a passing metric.
    assert BENCHMARK_PATH.is_file(), 'benchmark.py is missing'
    assert BENCHMARK_PATH.read_text() == EXPECTED_BENCHMARK, \
        'benchmark.py was modified instead of being run as supplied'

    # Restart the actual backend with the required REDIS_URL and capture its
    # access log so the benchmark must really issue all 5,000 fetches.
    subprocess.run(['pkill', '-f', '[p]ython3.*\/app\/backend\/app.py'], check=False)
    subprocess.run(['pkill', '-f', '[p]ython.*\/app\/backend\/app.py'], check=False)
    time.sleep(0.3)
    log_path = Path('/tmp/verifier_backend.log')
    log_file = log_path.open('wb')
    env = os.environ.copy()
    env['REDIS_URL'] = 'redis://127.0.0.1:6379/0'
    backend = subprocess.Popen(
        [sys.executable, str(BACKEND_PATH)],
        cwd=str(BACKEND_PATH.parent), env=env,
        stdout=log_file, stderr=subprocess.STDOUT,
    )
    try:
        wait_for_backend()
        log_file.flush()
        benchmark_log_offset = log_path.stat().st_size
        METRICS_PATH.unlink(missing_ok=True)

        started = time.monotonic()
        result = subprocess.run(
            [sys.executable, str(BENCHMARK_PATH)],
            cwd='/tmp', env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=30,
        )
        wall_time = time.monotonic() - started
        assert result.returncode == 0, f'benchmark.py failed:\n{result.stdout}'

        # Give the backend's unbuffered request logger a moment to finish writes.
        time.sleep(0.2)
        log_file.flush()
        with log_path.open('rb') as f:
            f.seek(benchmark_log_offset)
            benchmark_log = f.read().decode('utf-8', errors='replace')
        fetched_ids = set(re.findall(r'GET /api/artifact/([0-9]+)(?:\\s|\\?)', benchmark_log))
        expected_ids = {str(i) for i in range(5000)}
        missing = expected_ids - fetched_ids
        assert not missing, \
            f'benchmark did not fetch all 5,000 artifacts from Flask; missing {len(missing)} IDs'

        # Preserve the original metrics assertions, while enforcing the stated
        # strict threshold and rejecting non-finite/self-evidently fake values.
        assert METRICS_PATH.is_file(), \
            f'Metrics file {METRICS_PATH} does not exist. Did you run the benchmark?'
        try:
            data = json.loads(METRICS_PATH.read_text())
        except Exception as exc:
            pytest.fail(f'Failed to read or parse {METRICS_PATH}: {exc}')
        assert 'total_time_seconds' in data, \
            "metrics.json must contain 'total_time_seconds' key."
        try:
            measured = float(data['total_time_seconds'])
        except (TypeError, ValueError):
            pytest.fail(f"'total_time_seconds' must be a float, got {data['total_time_seconds']}")
        assert math.isfinite(measured) and measured >= 0, \
            'total_time_seconds must be a finite, non-negative number'
        assert measured < 1.5, \
            f'Execution time {measured} seconds does not satisfy the strict 1.5 second threshold.'
        # This is deliberately generous for interpreter startup, while preventing
        # a near-zero metric from standing in for a much longer benchmark run.
        assert measured <= wall_time and wall_time - measured < 1.0, \
            f'Reported benchmark time {measured} is inconsistent with observed runtime {wall_time}'
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()
            backend.wait()
        log_file.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
