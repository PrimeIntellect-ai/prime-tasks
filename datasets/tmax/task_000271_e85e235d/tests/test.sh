#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import signal
import socket
import subprocess
import time
import urllib.request

import pytest

SMUGGLER_DIR = '/home/user/smuggler'
SERVER = '/home/user/target/server'
BENCHMARK = '/home/user/benchmark.py'
BENCHMARK_JSON = '/home/user/benchmark.json'


def server_pids():
    found = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f'/proc/{name}/exe')
        except OSError:
            continue
        if exe == SERVER:
            found.append(int(name))
    return found


def stop_servers():
    for pid in server_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while server_pids() and time.monotonic() < deadline:
        time.sleep(0.05)
    for pid in server_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(timeout=3):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:8080/', timeout=0.3) as response:
                return response.read()
        except Exception as exc:
            last_error = exc
            time.sleep(0.05)
    raise AssertionError(f'Go server did not become reachable: {last_error}')


def test_libsmuggler_compiled():
    """Build through the submitted Makefile and load and exercise the result."""
    makefile = os.path.join(SMUGGLER_DIR, 'Makefile')
    text = open(makefile, encoding='utf-8').read()
    assert '-fPIC' in text, 'Makefile must compile the object as position-independent code.'
    assert '-shared' in text, 'Makefile must link libsmuggler.so as a shared library.'

    result = subprocess.run(
        ['make', 'clean'], cwd=SMUGGLER_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, f'make clean failed:\n{result.stdout}\n{result.stderr}'
    result = subprocess.run(
        ['make'], cwd=SMUGGLER_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, f'make failed:\n{result.stdout}\n{result.stderr}'

    so_path = '/home/user/smuggler/libsmuggler.so'
    assert os.path.isfile(so_path), f'Shared library {so_path} was not created.'
    result = subprocess.run(['file', so_path], capture_output=True, text=True)
    assert 'shared object' in result.stdout, f'{so_path} is not compiled as a shared object. Check Makefile flags (-shared, -fPIC).'

    probe = r'''import ctypes, os
os.environ["SMUGGLER_MODE"] = "CI"
lib = ctypes.CDLL("/home/user/smuggler/libsmuggler.so")
lib.init_smuggler.restype = ctypes.c_int
lib.send_fuzz.argtypes = [ctypes.c_char_p, ctypes.c_int]
lib.send_fuzz.restype = ctypes.c_int
assert lib.init_smuggler() == 1
assert lib.send_fuzz(b"127.0.0.1", 8080) == 1
'''
    result = subprocess.run(['python3', '-c', probe], capture_output=True, text=True)
    assert result.returncode == 0, f'Built library could not be loaded and exercised:\n{result.stdout}\n{result.stderr}'


def test_python_tests_pass():
    """Verify both the requested ordering fix and the submitted test suite."""
    test_path = '/home/user/smuggler/tests/test_smuggler.py'
    source = open(test_path, encoding='utf-8').read()
    tree = ast.parse(source, test_path)

    import_index = None
    assignment_index = None
    for index, node in enumerate(tree.body):
        if isinstance(node, ast.Import) and any(alias.name == 'smuggler' for alias in node.names):
            import_index = index
        elif isinstance(node, ast.ImportFrom) and node.module == 'smuggler':
            import_index = index
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if (isinstance(target, ast.Subscript)
                        and isinstance(target.value, ast.Attribute)
                        and isinstance(target.value.value, ast.Name)
                        and target.value.value.id == 'os'
                        and target.value.attr == 'environ'):
                    key = target.slice
                    if isinstance(key, ast.Constant) and key.value == 'SMUGGLER_MODE':
                        if isinstance(node.value, ast.Constant) and node.value.value == 'CI':
                            assignment_index = index

    assert import_index is not None, 'The test suite must import the smuggler module.'
    assert assignment_index is not None, 'The test suite must set SMUGGLER_MODE="CI" at module scope.'
    assert assignment_index < import_index, 'SMUGGLER_MODE must be set before smuggler is imported.'

    env = os.environ.copy()
    env.pop('SMUGGLER_MODE', None)
    result = subprocess.run(
        ['python3', '-m', 'unittest', 'discover', 'tests'],
        cwd=SMUGGLER_DIR,
        env=env,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f'Python tests failed or import order is still broken.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert 'Ran 1 test' in result.stderr + result.stdout, 'The required smuggler unit test was not run.'


def test_go_server_compiled_and_serves():
    """Verify the executable is a Go binary and actually serves the supplied endpoint."""
    exe_path = SERVER
    assert os.path.isfile(exe_path), f'Go server executable {exe_path} was not created.'
    assert os.access(exe_path, os.X_OK), f'Go server {exe_path} is not executable.'

    file_result = subprocess.run(['file', exe_path], capture_output=True, text=True)
    assert 'executable' in file_result.stdout and 'ELF' in file_result.stdout, 'server is not a compiled ELF executable.'
    go_result = subprocess.run(['go', 'version', '-m', exe_path], capture_output=True, text=True)
    assert go_result.returncode == 0 and '\tgo' in go_result.stdout, 'server is not identifiable as a compiled Go program.'

    stop_servers()
    proc = subprocess.Popen([exe_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        body = wait_for_server()
        assert body.strip() == b'OK', f'Unexpected server response: {body!r}'
        assert proc.poll() is None, 'Go server exited before serving the request.'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    assert not server_pids(), 'Go server remained running after termination.'


def test_benchmark_script_exists():
    script_path = BENCHMARK
    assert os.path.isfile(script_path), f'Benchmark script {script_path} is missing.'


def test_benchmark_json_output():
    """Run the benchmark and derive its request count from observed send_fuzz calls."""
    stop_servers()
    try:
        os.unlink(BENCHMARK_JSON)
    except FileNotFoundError:
        pass

    hook_dir = '/tmp/benchmark_hook'
    os.makedirs(hook_dir, exist_ok=True)
    stats_path = '/tmp/benchmark_observed.json'
    try:
        os.unlink(stats_path)
    except FileNotFoundError:
        pass

    hook = r'''import atexit
import builtins
import json
import socket

_stats = {"calls": 0, "successful_returns": 0, "server_responses": 0}
_out = "/tmp/benchmark_observed.json"
_orig_import = builtins.__import__
_wrapped = set()

def _install(module):
    if module is None or id(module) in _wrapped or not hasattr(module, "send_fuzz"):
        return
    original = module.send_fuzz
    def observed_send_fuzz(host, port):
        _stats["calls"] += 1
        result = original(host, port)
        if result == 1:
            _stats["successful_returns"] += 1
        try:
            with socket.create_connection((host, int(port)), timeout=0.25) as sock:
                sock.sendall(b"GET / HTTP/1.0\r\nHost: verifier\r\n\r\n")
                response = sock.recv(256)
                if b"OK" in response:
                    _stats["server_responses"] += 1
        except OSError:
            pass
        return result
    module.send_fuzz = observed_send_fuzz
    _wrapped.add(id(module))

def _import(name, globals=None, locals=None, fromlist=(), level=0):
    result = _orig_import(name, globals, locals, fromlist, level)
    if name == "smuggler" or name.endswith(".smuggler"):
        import sys
        _install(sys.modules.get(name))
        _install(sys.modules.get("smuggler"))
    return result

builtins.__import__ = _import

@atexit.register
def _save():
    with open(_out, "w") as f:
        json.dump(_stats, f)
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(hook)

    env = os.environ.copy()
    env.pop('SMUGGLER_MODE', None)
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = hook_dir + (os.pathsep + old_pythonpath if old_pythonpath else '')

    start = time.monotonic()
    proc = subprocess.Popen(
        ['python3', BENCHMARK],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    saw_server = False
    try:
        deadline = start + 10
        while proc.poll() is None and time.monotonic() < deadline:
            if server_pids():
                saw_server = True
            time.sleep(0.02)
        if proc.poll() is None:
            proc.kill()
            pytest.fail('benchmark.py did not finish within 10 seconds.')
        stdout, stderr = proc.communicate()
    finally:
        stop_servers()
    wall_time = time.monotonic() - start

    assert proc.returncode == 0, f'benchmark.py failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}'
    assert saw_server, 'benchmark.py never started /home/user/target/server.'
    assert not server_pids(), 'benchmark.py did not terminate the Go server.'
    assert wall_time >= 2.9, f'benchmark.py ran for only {wall_time:.3f} seconds.'
    assert wall_time < 8, f'benchmark.py took unexpectedly long ({wall_time:.3f} seconds).'

    json_path = BENCHMARK_JSON
    assert os.path.isfile(json_path), f'Benchmark output {json_path} is missing.'
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'{json_path} does not contain valid JSON.')

    assert set(data) == {'status', 'duration', 'requests_sent'}, 'benchmark.json must contain exactly the required keys.'
    assert 'status' in data, "Key 'status' missing in benchmark.json"
    assert data['status'] == 'success', f"Expected status 'success', got {data['status']}"
    assert 'duration' in data, "Key 'duration' missing in benchmark.json"
    assert isinstance(data['duration'], float), 'Duration must be a float'
    assert data['duration'] >= 2.9, f"Benchmark duration {data['duration']} is less than the required 3 seconds (allowing slight float margin)."
    assert data['duration'] <= 3.5, f"Benchmark duration {data['duration']} is not an approximately three-second loop."
    assert abs(data['duration'] - wall_time) < 1.5, 'Reported duration is not consistent with observed runtime.'
    assert 'requests_sent' in data, "Key 'requests_sent' missing in benchmark.json"
    assert isinstance(data['requests_sent'], int), 'requests_sent must be an integer'
    assert data['requests_sent'] > 0, 'requests_sent must be greater than 0'

    assert os.path.isfile(stats_path), 'benchmark.py did not import and call the smuggler module.'
    with open(stats_path, 'r') as f:
        observed = json.load(f)
    assert observed['calls'] > 0, 'No send_fuzz calls were observed.'
    assert observed['successful_returns'] == data['requests_sent'], 'requests_sent does not equal the observed successful send_fuzz calls.'
    assert observed['server_responses'] > 0, 'No requests reached the running Go server during the benchmark.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
