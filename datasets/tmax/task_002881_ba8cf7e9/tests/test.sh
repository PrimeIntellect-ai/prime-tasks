#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys
import tempfile

RECOVERED = '/home/user/recovered/suspicious.py'
REGRESSION = '/home/user/recovered/test_suspicious.py'
DUMP = '/home/user/evidence/mem_dump.bin'

EXPECTED_ORIGINAL = '''import threading
import time

class ConnectionPool:
    def __init__(self):
        self.conn_lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.active_connections = 0

    def acquire_connection(self):
        with self.conn_lock:
            time.sleep(0.01) # Simulate work
            with self.state_lock:
                self.active_connections += 1

    def release_connection(self):
        with self.state_lock:
            time.sleep(0.01) # Simulate work
            with self.conn_lock:
                self.active_connections -= 1

pool = ConnectionPool()

def worker1():
    for _ in range(50):
        pool.acquire_connection()

def worker2():
    for _ in range(50):
        pool.release_connection()

def run():
    t1 = threading.Thread(target=worker1)
    t2 = threading.Thread(target=worker2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

if __name__ == "__main__":
    run()
'''

EXPECTED_FIXED = EXPECTED_ORIGINAL.replace(
    '''    def release_connection(self):
        with self.state_lock:
            time.sleep(0.01) # Simulate work
            with self.conn_lock:
                self.active_connections -= 1
''',
    '''    def release_connection(self):
        with self.conn_lock:
            time.sleep(0.01) # Simulate work
            with self.state_lock:
                self.active_connections -= 1
'''
)


def read_text(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


def extracted_dump_script():
    data = open(DUMP, 'rb').read()
    start_marker = b'### SCRIPT_START\n'
    end_marker = b'### SCRIPT_END\n'
    assert data.count(start_marker) == 1, 'Memory dump must contain one SCRIPT_START marker'
    assert data.count(end_marker) == 1, 'Memory dump must contain one SCRIPT_END marker'
    start = data.index(start_marker) + len(start_marker)
    end = data.index(end_marker, start)
    return data[start:end].decode('utf-8')


def test_suspicious_py_exists():
    assert os.path.isfile(RECOVERED), f'{RECOVERED} is missing'


def test_test_suspicious_py_exists():
    assert os.path.isfile(REGRESSION), f'{REGRESSION} is missing'


def test_source_was_recovered_and_only_required_fix_was_made():
    original = extracted_dump_script()
    assert original == EXPECTED_ORIGINAL, 'The supplied memory dump source is not the expected workload'
    content = read_text(RECOVERED)
    assert content == EXPECTED_FIXED, (
        'suspicious.py must preserve the recovered source, workload, and thread count, '
        'changing only release_connection to acquire conn_lock before state_lock'
    )


def test_suspicious_py_fixed():
    content = read_text(RECOVERED)
    tree = ast.parse(content)
    release_func = next(
        (node for node in ast.walk(tree)
         if isinstance(node, ast.FunctionDef) and node.name == 'release_connection'),
        None
    )
    assert release_func is not None, 'Function release_connection not found in suspicious.py'
    body_text = ast.get_source_segment(content, release_func)
    conn_idx = body_text.find('conn_lock')
    state_idx = body_text.find('state_lock')
    assert conn_idx != -1 and state_idx != -1, 'Locks not found in release_connection'
    assert conn_idx < state_idx, 'conn_lock must be acquired before state_lock in release_connection'


def _attribute_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return '.'.join(reversed(parts))


def _timeout_value(node):
    if not isinstance(node, ast.Call) or not _attribute_name(node.func).endswith('mark.timeout'):
        return None
    value = node.args[0] if node.args else next(
        (kw.value for kw in node.keywords if kw.arg in ('timeout', 'seconds')), None
    )
    if isinstance(value, ast.Constant) and isinstance(value.value, (int, float)):
        return float(value.value)
    return None


def test_regression_test_imports_calls_run_with_timeout():
    content = read_text(REGRESSION)
    assert 'timeout' in content, 'The test file does not configure a timeout. Use pytest-timeout.'
    assert 'run' in content, "The test file does not import or use the 'run' function."
    tree = ast.parse(content)

    direct_names = set()
    module_names = set()
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module == 'suspicious':
            for alias in node.names:
                if alias.name == 'run':
                    direct_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'suspicious':
                    module_names.add(alias.asname or alias.name)

    assert direct_names or module_names, 'The regression test must import run from suspicious.py'

    module_timeout = None
    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(t, ast.Name) and t.id == 'pytestmark' for t in targets):
                value = node.value
                candidates = value.elts if isinstance(value, (ast.List, ast.Tuple)) else [value]
                for candidate in candidates:
                    timeout = _timeout_value(candidate)
                    if timeout is not None:
                        module_timeout = timeout

    found = False
    for func in (n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith('test')):
        calls_run = False
        for node in ast.walk(func):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Name) and node.func.id in direct_names:
                calls_run = True
            elif isinstance(node.func, ast.Attribute) and node.func.attr == 'run':
                if isinstance(node.func.value, ast.Name) and node.func.value.id in module_names:
                    calls_run = True
        if not calls_run:
            continue
        timeout = module_timeout
        for decorator in func.decorator_list:
            value = _timeout_value(decorator)
            if value is not None:
                timeout = value
        if timeout is not None and 0 < timeout <= 5:
            found = True
            break

    assert found, 'A test that calls suspicious.run must have a pytest-timeout limit of at most 5 seconds'


def test_recovered_program_executes_without_deadlock():
    code = (
        "import suspicious; suspicious.run(); "
        "assert suspicious.pool.active_connections == 0, "
        "f'unexpected final count: {suspicious.pool.active_connections}'"
    )
    result = subprocess.run(
        [sys.executable, '-c', code],
        cwd='/home/user/recovered',
        capture_output=True,
        text=True,
        timeout=5
    )
    assert result.returncode == 0, f'suspicious.run failed:\n{result.stdout}\n{result.stderr}'


def test_pytest_runs_successfully_and_really_calls_run():
    with tempfile.TemporaryDirectory() as td:
        marker = os.path.join(td, 'run-called')
        test_copy = os.path.join(td, 'test_suspicious.py')
        with open(test_copy, 'w', encoding='utf-8') as f:
            f.write(read_text(REGRESSION))
        with open(os.path.join(td, 'conftest.py'), 'w', encoding='utf-8') as f:
            f.write(
                "import suspicious\n"
                "_original_run = suspicious.run\n"
                "def _tracked_run(*args, **kwargs):\n"
                f"    open({marker!r}, 'a').close()\n"
                "    return _original_run(*args, **kwargs)\n"
                "suspicious.run = _tracked_run\n"
            )
        env = os.environ.copy()
        env['PYTHONPATH'] = '/home/user/recovered' + os.pathsep + env.get('PYTHONPATH', '')
        result = subprocess.run(
            ['pytest', test_copy],
            cwd=td,
            env=env,
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f'pytest failed with output:\n{result.stdout}\n{result.stderr}'
        assert os.path.isfile(marker), 'The regression test passed without actually calling suspicious.run()'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
