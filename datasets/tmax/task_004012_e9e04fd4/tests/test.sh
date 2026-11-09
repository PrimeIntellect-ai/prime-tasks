#!/bin/bash
set -u
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:$PATH"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import gc
import importlib
import importlib.machinery
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

PROJECT = Path('/home/user/math_ws_project')
RESULTS = Path('/home/user/benchmark_results.json')

EXPECTED_PURE_PYTHON = '''import math

def compute_trajectory(alpha, beta, iterations):
    x, y = 0.1, 0.1
    res = []
    for _ in range(iterations):
        nx = math.sin(alpha * y) - math.cos(beta * x)
        ny = math.sin(beta * x) - math.cos(alpha * y)
        x, y = nx, ny
        res.append((x, y))
    return res
'''


def oracle(alpha, beta, iterations):
    x, y = 0.1, 0.1
    result = []
    append = result.append
    sin = math.sin
    cos = math.cos
    for _ in range(iterations):
        nx = sin(alpha * y) - cos(beta * x)
        ny = sin(beta * x) - cos(alpha * y)
        x, y = nx, ny
        append((x, y))
    return result


def build_clean_extension():
    wheel_dir = Path(tempfile.mkdtemp(prefix='verified-wheels-'))
    site_dir = Path(tempfile.mkdtemp(prefix='verified-site-'))
    subprocess.run(
        ['maturin', 'build', '--release', '--out', str(wheel_dir)],
        cwd=PROJECT,
        check=True,
        timeout=240,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    wheels = list(wheel_dir.glob('*.whl'))
    assert len(wheels) == 1, f'Expected one wheel from maturin, found {wheels}'
    subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '--no-deps', '--target', str(site_dir), str(wheels[0])],
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return site_dir


def load_native_extension(site_dir):
    sys.modules.pop('rust_engine', None)
    sys.path.insert(0, str(site_dir))
    try:
        module = importlib.import_module('rust_engine')
    finally:
        sys.path.pop(0)
    origin = Path(module.__spec__.origin or '')
    assert any(str(origin).endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f'rust_engine is not a native extension: {origin}'
    assert callable(getattr(module, 'compute_trajectory', None))
    return module


def check_benchmark_source():
    path = PROJECT / 'run_benchmark.py'
    assert path.is_file(), 'run_benchmark.py is missing'
    tree = ast.parse(path.read_text(), filename=str(path))

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
    assert 'pure_python' in imported, 'run_benchmark.py must import pure_python'
    assert 'rust_engine' in imported, 'run_benchmark.py must import rust_engine'

    calls = []
    constants = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)
            elif isinstance(node.func, ast.Name):
                calls.append(node.func.id)
        elif isinstance(node, ast.Constant):
            constants.append(node.value)
    assert calls.count('compute_trajectory') >= 2, \
        'run_benchmark.py must call both trajectory implementations'
    assert 1.75 in constants and 0.95 in constants and 1000000 in constants, \
        'run_benchmark.py must use the parameters extracted from sys_config.png'


def run_benchmark(site_dir):
    RESULTS.unlink(missing_ok=True)
    env = os.environ.copy()
    env['PYTHONPATH'] = str(site_dir)
    subprocess.run(
        [sys.executable, str(PROJECT / 'run_benchmark.py')],
        cwd=PROJECT,
        env=env,
        check=True,
        timeout=240,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert RESULTS.is_file(), f'JSON file missing at {RESULTS}'
    try:
        data = json.loads(RESULTS.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{RESULTS} is not valid JSON: {exc}')
    assert set(data) == {'mse', 'speedup'}, \
        'benchmark_results.json must have exactly the keys mse and speedup'
    mse = float(data['mse'])
    speedup = float(data['speedup'])
    assert math.isfinite(mse), f'Reported MSE is not finite: {mse}'
    assert mse < 1e-5, f'Reported MSE too high: {mse} (threshold: < 1e-5)'
    assert speedup >= 3.0, f'Reported Speedup too low: {speedup}x (threshold: >= 3.0x)'


def check_server(site_dir):
    server_path = PROJECT / 'server.py'
    assert server_path.is_file(), 'server.py is missing'
    source = server_path.read_text()
    tree = ast.parse(source, filename=str(server_path))
    assert any(isinstance(n, ast.Call) and (
        (isinstance(n.func, ast.Attribute) and n.func.attr == 'dumps') or
        (isinstance(n.func, ast.Name) and n.func.id == 'dumps')
    ) for n in ast.walk(tree)), 'server.py must JSON-serialize the trajectory'

    env = os.environ.copy()
    env['PYTHONPATH'] = str(site_dir)
    proc = subprocess.Popen(
        [sys.executable, str(server_path)],
        cwd='/tmp',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )

    async def receive():
        import websockets
        last_error = None
        for _ in range(40):
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else ''
                raise AssertionError(f'server.py exited before accepting connections: {output}')
            try:
                async with websockets.connect('ws://localhost:8765') as ws:
                    return await asyncio.wait_for(ws.recv(), timeout=5)
            except Exception as exc:
                last_error = exc
                await asyncio.sleep(0.1)
        raise AssertionError(f'Could not connect to server.py: {last_error}')

    try:
        message = asyncio.run(receive())
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)

    assert isinstance(message, str), 'WebSocket payload must be serialized text'
    payload = json.loads(message)
    expected = oracle(1.0, 1.0, 100)
    assert isinstance(payload, list) and len(payload) == 100
    for got, want in zip(payload, expected):
        assert isinstance(got, list) and len(got) == 2
        assert abs(float(got[0]) - want[0]) < 1e-12
        assert abs(float(got[1]) - want[1]) < 1e-12


def test_complete_submission():
    # The supplied baseline is not an agent-controlled timing or correctness oracle.
    assert (PROJECT / 'pure_python.py').read_text() == EXPECTED_PURE_PYTHON, \
        'The provided pure_python.py implementation must not be replaced or modified'
    assert not (PROJECT / 'rust_engine.py').exists(), \
        'A Python rust_engine.py is not a Rust extension'
    assert not (PROJECT / 'rust_engine' / '__init__.py').exists(), \
        'rust_engine must be the compiled PyO3 module, not a Python shim'

    check_benchmark_source()
    site_dir = build_clean_extension()
    rust_engine = load_native_extension(site_dir)
    run_benchmark(site_dir)

    # Exercise independently derived inputs so a hard-coded benchmark result cannot pass.
    for alpha, beta, iterations in [(0.3, -0.7, 0), (1.2, 0.4, 17), (-0.8, 1.1, 257)]:
        expected = oracle(alpha, beta, iterations)
        actual = rust_engine.compute_trajectory(alpha, beta, iterations)
        assert len(actual) == iterations
        assert len(expected) == iterations
        mse = (sum((px-rx)**2 + (py-ry)**2
                   for (px, py), (rx, ry) in zip(expected, actual)) / iterations
               if iterations else 0.0)
        assert mse < 1e-5, f'Rust mismatch for {(alpha, beta, iterations)}: {mse}'

    # Preserve the required full-size derived correctness and speed assertions, but
    # compare the freshly built native module against an immutable verifier oracle.
    alpha, beta, iterations = 1.75, 0.95, 1000000
    t0 = time.perf_counter()
    py_res = oracle(alpha, beta, iterations)
    py_time = time.perf_counter() - t0
    t0 = time.perf_counter()
    rs_res = rust_engine.compute_trajectory(alpha, beta, iterations)
    rs_time = time.perf_counter() - t0

    assert len(py_res) == iterations, f'Pure Python returned {len(py_res)}, expected {iterations}'
    assert len(rs_res) == iterations, f'Rust engine returned {len(rs_res)}, expected {iterations}'
    mse = sum((px-rx)**2 + (py-ry)**2
              for (px, py), (rx, ry) in zip(py_res, rs_res)) / iterations
    speedup = py_time / rs_time if rs_time > 0 else float('inf')
    assert mse < 1e-5, f'Derived MSE too high: {mse} (threshold: < 1e-5)'
    assert speedup >= 3.0, f'Derived Speedup too low: {speedup:.2f}x (threshold: >= 3.0x)'

    del py_res, rs_res
    gc.collect()
    check_server(site_dir)
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
