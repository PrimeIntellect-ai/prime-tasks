#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

ROOT = Path('/home/user/data_app')
RUST_DIR = ROOT / 'rust_server'
CPP_DIR = ROOT / 'cpp_engine'
RESULTS = Path('/home/user/benchmark_results.json')


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 180)
    return subprocess.run(cmd, **kwargs)


def test_cargo_test_passes():
    assert RUST_DIR.is_dir(), 'rust_server directory is missing.'
    result = run(['cargo', 'test'], cwd=RUST_DIR)
    assert result.returncode == 0, f'cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'


def test_cpp_memory_leak_fixed():
    cpp_path = CPP_DIR / 'processor.cpp'
    assert cpp_path.is_file(), f'{cpp_path} is missing.'
    content = cpp_path.read_text()
    if 'new ' in content or 'new[' in content:
        assert 'delete[]' in content, "Memory leak not fixed: 'new' is used but 'delete[]' is missing."


def test_cpp_out_of_bounds_fixed():
    cpp_path = CPP_DIR / 'processor.cpp'
    assert cpp_path.is_file(), f'{cpp_path} is missing.'
    content = cpp_path.read_text()
    assert '<= length' not in content and '<=length' not in content, 'Out-of-bounds bug (<= length) is still present.'


def test_processor_behavior_and_memory_safety(tmp_path):
    rng = random.SystemRandom()
    cases = [[], [0.0], [1.0], [-2.25, 0.5], [1.0, 2.0, 3.0, 4.0]]
    for _ in range(30):
        cases.append([rng.uniform(-1000.0, 1000.0) for _ in range(rng.randrange(1, 65))])

    initializers = []
    for values in cases:
        vals = ', '.join(format(v, '.17g') for v in values)
        initializers.append('{' + vals + '}')

    harness = tmp_path / 'processor_test.cpp'
    harness.write_text(r'''#include "processor.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>

int main() {
    std::vector<std::vector<double>> cases = {
''' + ',\n'.join(initializers) + r'''
    };
    for (const auto& values : cases) {
        double expected = 0.0;
        for (double value : values) expected += value * 2.5;
        double actual = process_data(values.data(), static_cast<int>(values.size()));
        double tolerance = 1e-9 * std::max(1.0, std::abs(expected));
        if (!std::isfinite(actual) || std::abs(actual - expected) > tolerance) {
            std::cerr << "incorrect result: expected " << expected << ", got " << actual << "\n";
            return 1;
        }
    }
    if (process_data(nullptr, 0) != 0.0 || process_data(nullptr, -3) != 0.0) {
        std::cerr << "non-positive lengths were not handled safely\n";
        return 1;
    }
    return 0;
}
''')
    binary = tmp_path / 'processor_test'
    compiled = run([
        'g++', '-std=c++17', '-O1', '-g', '-fno-omit-frame-pointer',
        '-fsanitize=address,undefined', str(harness), str(CPP_DIR / 'processor.cpp'),
        '-I', str(CPP_DIR), '-o', str(binary)
    ])
    assert compiled.returncode == 0, f'Could not compile processor test:\n{compiled.stdout}\n{compiled.stderr}'
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    checked = run([str(binary)], env=env)
    assert checked.returncode == 0, f'Processor failed behavioral or sanitizer checks:\n{checked.stdout}\n{checked.stderr}'


def test_cmake_fixed(tmp_path):
    cmake_path = CPP_DIR / 'CMakeLists.txt'
    assert cmake_path.is_file(), f'{cmake_path} is missing.'
    content = cmake_path.read_text()
    assert 'add_executable' not in content, 'CMakeLists.txt still contains add_executable.'
    assert 'add_library' in content, 'CMakeLists.txt is missing add_library.'
    assert '-fPIC' in content or 'POSITION_INDEPENDENT_CODE' in content, 'CMakeLists.txt is missing Position Independent Code (-fPIC) configuration.'

    build_dir = tmp_path / 'cmake-build'
    configured = run(['cmake', '-S', str(CPP_DIR), '-B', str(build_dir), '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON'])
    assert configured.returncode == 0, f'CMake configure failed:\n{configured.stdout}\n{configured.stderr}'
    built = run(['cmake', '--build', str(build_dir), '--target', 'processor'])
    assert built.returncode == 0, f'CMake processor target failed:\n{built.stdout}\n{built.stderr}'
    archives = list(build_dir.rglob('libprocessor.a'))
    assert archives, 'CMake did not produce the required static library libprocessor.a.'
    listing = run(['ar', 't', str(archives[0])])
    assert listing.returncode == 0 and listing.stdout.strip(), 'libprocessor.a is not a valid non-empty static archive.'

    compile_db = json.loads((build_dir / 'compile_commands.json').read_text())
    processor_commands = [entry.get('command', '') for entry in compile_db if entry.get('file', '').endswith('processor.cpp')]
    assert processor_commands, 'CMake did not compile processor.cpp.'
    assert any('-fPIC' in command for command in processor_commands), 'processor.cpp was not actually compiled with -fPIC.'


def stop_existing_server():
    subprocess.run(['pkill', '-x', 'rust_server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def wait_for_port(process, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            return False
        try:
            with socket.create_connection(('127.0.0.1', 3000), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def test_rest_server_processes_derived_inputs():
    built = run(['cargo', 'build'], cwd=RUST_DIR)
    assert built.returncode == 0, f'cargo build failed:\n{built.stdout}\n{built.stderr}'
    stop_existing_server()
    binary = RUST_DIR / 'target' / 'debug' / 'rust_server'
    server = subprocess.Popen([str(binary)], cwd=RUST_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        assert wait_for_port(server), 'Rust server did not start on port 3000.'
        rng = random.SystemRandom()
        cases = [[], [1.0], [-4.0, 2.0], [rng.uniform(-50, 50) for _ in range(37)]]
        for _ in range(20):
            cases.append([rng.uniform(-500, 500) for _ in range(rng.randrange(1, 30))])
        for values in cases:
            body = json.dumps({'numbers': values}).encode()
            request = urllib.request.Request('http://127.0.0.1:3000/process', data=body, headers={'Content-Type': 'application/json'}, method='POST')
            with urllib.request.urlopen(request, timeout=5) as response:
                assert response.status == 200
                payload = json.loads(response.read())
            expected = sum(values) * 2.5
            actual = payload.get('result')
            assert isinstance(actual, (int, float))
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), f'For {values}, expected {expected}, got {actual}'
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)


class CountingServer(ThreadingHTTPServer):
    allow_reuse_address = True


class BenchmarkHandler(BaseHTTPRequestHandler):
    valid_requests = 0
    lock = threading.Lock()

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length)
        valid = False
        try:
            payload = json.loads(raw)
            numbers = payload.get('numbers')
            valid = self.path == '/process' and isinstance(numbers, list) and all(isinstance(v, (int, float)) for v in numbers)
        except Exception:
            pass
        if valid:
            with self.lock:
                type(self).valid_requests += 1
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"result":0.0}')
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass


def test_benchmark_runs_1000_successful_requests():
    benchmark = ROOT / 'benchmark.sh'
    assert benchmark.is_file(), f'{benchmark} is missing.'
    stop_existing_server()
    if RESULTS.exists():
        RESULTS.unlink()
    BenchmarkHandler.valid_requests = 0
    server = CountingServer(('127.0.0.1', 3000), BenchmarkHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = run(['bash', str(benchmark)], cwd=ROOT, timeout=120)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    assert result.returncode == 0, f'benchmark.sh failed:\n{result.stdout}\n{result.stderr}'
    assert BenchmarkHandler.valid_requests >= 1000, f'benchmark.sh made only {BenchmarkHandler.valid_requests} valid requests; expected at least 1000.'
    assert RESULTS.is_file(), f'Benchmark results file {RESULTS} is missing.'
    try:
        data = json.loads(RESULTS.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {RESULTS} is not valid JSON: {exc}')
    assert data.get('status') == 'success', f"Expected status 'success', got {data.get('status')}"
    assert data.get('requests') == 1000, f"Expected 1000 requests, got {data.get('requests')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
