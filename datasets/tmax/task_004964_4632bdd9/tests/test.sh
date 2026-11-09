#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import gc
import importlib
import inspect
import json
import math
import os
import pathlib
import random
import subprocess
import sys
import urllib.error
import urllib.request

import pytest

PROJECT = pathlib.Path('/home/user/img_service')
URL = 'http://127.0.0.1:8000/process'


def test_multiplier_file():
    path = PROJECT / 'multiplier.txt'
    assert path.is_file(), f'File {path} is missing. Did you extract the multiplier and save it?'

    content = path.read_text().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float in {path}.")

    assert abs(val - 42.5) < 0.01, f'Expected multiplier to be 42.5, got {val}'


def get_server_pid():
    for pid_str in os.listdir('/proc'):
        if not pid_str.isdigit():
            continue
        try:
            with open(f'/proc/{pid_str}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\x00', b' ').decode(errors='replace')
            if 'python' in cmdline and 'server.py' in cmdline:
                return int(pid_str)
        except Exception:
            continue
    return None


def get_memory_mb(pid):
    try:
        with open(f'/proc/{pid}/statm', 'r') as f:
            rss_pages = int(f.read().split()[1])
        return (rss_pages * os.sysconf('SC_PAGE_SIZE')) / (1024 * 1024)
    except Exception as e:
        pytest.fail(f'Failed to read memory usage for PID {pid}: {e}')


def post_json(url, data):
    req = urllib.request.Request(url, method='POST')
    req.add_header('Content-Type', 'application/json')
    json_data = json.dumps(data).encode('utf-8')
    try:
        with urllib.request.urlopen(req, data=json_data, timeout=5) as response:
            return json.loads(response.read().decode('utf-8'))
    except (urllib.error.URLError, ValueError) as e:
        pytest.fail(f'Request to {url} failed: {e}')


def expected_result(pixels, multiplier):
    return sum(float(value) * float(multiplier) for value in pixels) / len(pixels)


def assert_result(actual, expected):
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
        f'Result must be numeric, got {actual!r}'
    assert math.isfinite(actual), f'Result is not finite: {actual!r}'
    tolerance = max(0.05, abs(expected) * 2e-5)
    assert abs(actual - expected) <= tolerance, \
        f'Numerical correctness failed. Expected {expected}, got {actual}'


def generated_cases():
    rng = random.SystemRandom()
    cases = [
        ([0, 1, 17, 128, 254, 255], 42.5),
        ([255, 3, 201, 99, 17, 240, 64], 73.125),
        ([200] * 1000, 42.5),
    ]
    multipliers = [0.25, 1.5, 7.75, 42.5, 63.125, 97.375]
    for _ in range(12):
        size = rng.randint(17, 257)
        pixels = [rng.randint(0, 255) for _ in range(size)]
        multiplier = rng.choice(multipliers) + rng.randint(0, 7) / 32.0
        cases.append((pixels, multiplier))
    return cases


def test_c_source_builds_and_extension_behavior():
    source = PROJECT / 'processor.c'
    setup = PROJECT / 'setup.py'
    assert source.is_file(), 'processor.c is missing.'
    assert setup.is_file(), 'setup.py is missing.'

    subprocess.run(
        [sys.executable, 'setup.py', 'build_ext', '--inplace', '--force'],
        cwd=PROJECT,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    sys.path.insert(0, str(PROJECT))
    sys.modules.pop('processor', None)
    processor = importlib.import_module('processor')
    module_path = pathlib.Path(processor.__file__).resolve()
    assert module_path.suffix == '.so', f'processor must be a compiled C extension, got {module_path}'
    assert inspect.isbuiltin(processor.process), 'processor.process is not a C-extension function.'

    for pixels, multiplier in generated_cases():
        expected = expected_result(pixels, multiplier)
        assert_result(processor.process(pixels, multiplier), expected)

    # Exercise the extension itself so a server shim cannot hide the C reference leak.
    payload = [100] * 50
    for _ in range(200):
        processor.process(payload, 1.0)
    gc.collect()
    before = get_memory_mb(os.getpid())
    for _ in range(10000):
        processor.process(payload, 1.0)
    gc.collect()
    growth = get_memory_mb(os.getpid()) - before
    assert growth <= 5.0, \
        f'Memory leak detected in processor.process: RSS grew by {growth:.2f} MB.'


def test_reproducer_or_fuzzer_exists_and_runs():
    candidates = []
    for path in PROJECT.rglob('*.py'):
        if path.name in {'server.py', 'setup.py'} or 'build' in path.parts or '__pycache__' in path.parts:
            continue
        try:
            text = path.read_text(errors='replace')
        except OSError:
            continue
        lower = text.lower()
        exercises_processor = 'processor.process' in text or '/process' in text
        diagnoses_bug = any(word in lower for word in ('repro', 'fuzz', 'overflow', 'memory', 'leak'))
        if exercises_processor and diagnoses_bug:
            priority = 0 if any(word in path.name.lower() for word in ('repro', 'fuzz')) else 1
            candidates.append((priority, str(path), path))

    assert candidates, 'No reproducible example or fuzzer script was found.'
    candidate = sorted(candidates)[0][2]
    completed = subprocess.run(
        [sys.executable, str(candidate)],
        cwd=PROJECT,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert completed.returncode == 0, \
        f'Reproducer/fuzzer {candidate} failed when executed:\n{completed.stdout}'


def test_server_correctness_and_memory_leak():
    pid = get_server_pid()
    assert pid is not None, 'server.py is not running. Did you start the service?'

    server_path = PROJECT / 'server.py'
    assert server_path.is_file(), 'server.py is missing.'
    tree = ast.parse(server_path.read_text(), filename=str(server_path))
    processor_aliases = set()
    direct_process_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'processor':
                    processor_aliases.add(alias.asname or 'processor')
        elif isinstance(node, ast.ImportFrom) and node.module == 'processor':
            for alias in node.names:
                if alias.name == 'process':
                    direct_process_aliases.add(alias.asname or 'process')

    uses_extension = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == 'process' \
                and isinstance(node.func.value, ast.Name) \
                and node.func.value.id in processor_aliases:
            uses_extension = True
        if isinstance(node.func, ast.Name) and node.func.id in direct_process_aliases:
            uses_extension = True
    assert uses_extension, 'server.py does not call processor.process from the C extension.'

    try:
        maps = pathlib.Path(f'/proc/{pid}/maps').read_text(errors='replace')
    except OSError as e:
        pytest.fail(f'Could not inspect server mappings: {e}')
    assert any('processor' in line and '.so' in line for line in maps.splitlines()), \
        'The running server has not loaded the processor C extension.'

    # Preserve the original fixed overflow regression assertion.
    test_pixels = [200] * 1000
    payload = {'pixels': test_pixels, 'multiplier': 42.5}
    resp_data = post_json(URL, payload)
    assert 'result' in resp_data, "Response JSON missing 'result' key."
    res = resp_data['result']
    expected = 8500.0
    assert abs(res - expected) <= 1.0, \
        f'Numerical correctness failed. Expected ~{expected}, got {res}. Integer overflow might still exist.'

    # Unpredictable, nonuniform requests prevent a fixed-response service from passing.
    for pixels, multiplier in generated_cases():
        response = post_json(URL, {'pixels': pixels, 'multiplier': multiplier})
        assert 'result' in response, "Response JSON missing 'result' key."
        assert_result(response['result'], expected_result(pixels, multiplier))

    mem_before = get_memory_mb(pid)

    # Preserve the original load test and threshold.
    for _ in range(5000):
        post_json(URL, {'pixels': [100] * 50, 'multiplier': 1.0})

    mem_after = get_memory_mb(pid)
    leaked_mb = mem_after - mem_before
    assert leaked_mb <= 5.0, \
        f'Memory leak detected! Leaked {leaked_mb:.2f} MB during load test, which exceeds the 5.0 MB threshold.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
