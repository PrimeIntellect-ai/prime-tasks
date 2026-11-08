#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.metadata
import json
import os
import secrets
import subprocess
import sys
import urllib.request
from pathlib import Path

import pytest
from packaging.requirements import Requirement

WORKSPACE_DIR = Path('/home/user/workspace')
URL = 'http://localhost:8000/api/v1/execute'


def post_program(program):
    payload = json.dumps({'program': program}).encode('utf-8')
    req = urllib.request.Request(URL, data=payload, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode(), json.loads(response.read().decode('utf-8'))
    except Exception as exc:
        pytest.fail(f'Failed to reach the API endpoint at {URL} or bad response: {exc}')


def test_requirements_are_resolved_and_installed():
    requirements_path = WORKSPACE_DIR / 'requirements.txt'
    assert requirements_path.is_file(), 'requirements.txt is missing'
    requirements = []
    for line in requirements_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            requirements.append(Requirement(line))
    assert requirements, 'requirements.txt is empty'
    for requirement in requirements:
        installed = importlib.metadata.version(requirement.name)
        assert installed in requirement.specifier, (
            f'{requirement.name} {installed} does not satisfy {requirement.specifier}'
        )
    result = subprocess.run(
        [sys.executable, '-m', 'pip', 'check'], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
    import fastapi
    import pydantic
    assert fastapi and pydantic


def test_vm_source_was_not_modified():
    expected = '''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int execute_vm(const char* instructions) {
    int accumulator = 0;
    char* copy = strdup(instructions);
    char* token = strtok(copy, "\\n");

    while (token != NULL) {
        if (strncmp(token, "ADD ", 4) == 0) {
            accumulator += atoi(token + 4);
        } else if (strncmp(token, "SUB ", 4) == 0) {
            accumulator -= atoi(token + 4);
        } else if (strncmp(token, "RET", 3) == 0) {
            break;
        }
        token = strtok(NULL, "\\n");
    }

    free(copy);
    return accumulator;
}
'''
    assert (WORKSPACE_DIR / 'vm.c').read_text() == expected, 'vm.c was modified'


def test_makefile_and_libvm_so_compiled_correctly():
    makefile = WORKSPACE_DIR / 'Makefile'
    assert makefile.is_file(), 'Makefile is missing'
    make_text = makefile.read_text()
    assert '-shared' in make_text, 'Makefile does not use -shared'
    assert '-fPIC' in make_text, 'Makefile does not use -fPIC'

    build = subprocess.run(
        ['make', '-B'], cwd=WORKSPACE_DIR, capture_output=True, text=True
    )
    assert build.returncode == 0, build.stdout + build.stderr

    lib_path = WORKSPACE_DIR / 'libvm.so'
    assert lib_path.is_file(), 'libvm.so was not compiled'
    result = subprocess.run(['file', str(lib_path)], capture_output=True, text=True)
    assert 'shared object' in result.stdout.lower(), (
        'libvm.so is not a valid shared object. Did you add -shared and -fPIC to the Makefile?'
    )

    library = ctypes.CDLL(str(lib_path))
    function = library.execute_vm
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_int
    assert function(b'ADD 31\nSUB 9\nADD 4\nRET') == 26


def test_app_py_exists_and_uses_ctypes_with_correct_signature():
    app_path = WORKSPACE_DIR / 'app.py'
    assert app_path.is_file(), 'app.py is missing'
    content = app_path.read_text()
    assert 'ctypes' in content, 'app.py does not import/use ctypes'
    assert 'libvm.so' in content, 'app.py does not load libvm.so'

    sys.path.insert(0, str(WORKSPACE_DIR))
    try:
        sys.modules.pop('app', None)
        import app as submitted_app
    finally:
        sys.path.pop(0)

    assert hasattr(submitted_app, 'app'), 'app.py does not expose a FastAPI app'
    candidates = []
    for value in vars(submitted_app).values():
        if isinstance(value, ctypes._CFuncPtr):
            candidates.append(value)
        if isinstance(value, ctypes.CDLL):
            try:
                candidates.append(value.execute_vm)
            except AttributeError:
                pass
    functions = [fn for fn in candidates if getattr(fn, '__name__', '') == 'execute_vm']
    assert functions, 'app.py does not expose/load the C execute_vm function through ctypes'
    assert any(fn.argtypes == [ctypes.c_char_p] for fn in functions), (
        'execute_vm.argtypes must be [ctypes.c_char_p]'
    )
    assert any(fn.restype is ctypes.c_int for fn in functions), (
        'execute_vm.restype must be ctypes.c_int'
    )


def test_submitted_test_exists_and_runs():
    test_path = WORKSPACE_DIR / 'test_app.py'
    assert test_path.is_file(), 'test_app.py is missing'
    content = test_path.read_text()
    assert 'TestClient' in content, 'test_app.py does not use TestClient'
    assert 'ADD 5' in content and 'ADD 10' in content, (
        'test_app.py does not contain the required test payload'
    )
    result = subprocess.run(
        [sys.executable, '-m', 'pytest', str(test_path), '-q'],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert '1 passed' in result.stdout, 'The required pytest test was not collected and passed'


def test_api_endpoint_running_and_correct_for_derived_inputs():
    # Preserve the original API check.
    status, data = post_program('ADD 20\nSUB 5\nRET')
    assert status == 200, f'Expected HTTP 200, got {status}'
    assert 'result' in data, "Response JSON missing 'result' key"
    assert data['result'] == 15, f"Expected result 15, got {data['result']}"

    rng = secrets.SystemRandom()
    for _ in range(6):
        first = rng.randint(-5000, 5000)
        second = rng.randint(-5000, 5000)
        third = rng.randint(-5000, 5000)
        ignored = rng.randint(-5000, 5000)
        program = f'ADD {first}\nSUB {second}\nADD {third}\nRET\nADD {ignored}'
        expected = first - second + third
        status, body = post_program(program)
        assert status == 200, f'Expected HTTP 200, got {status}'
        assert body == {'result': expected}, f'For {program!r}, expected {expected}, got {body!r}'


def test_success_log_exists_and_is_exact_status():
    log_path = WORKSPACE_DIR / 'success.log'
    assert log_path.is_file(), 'success.log is missing'
    content = log_path.read_text().strip()
    assert '200' in content, f"success.log does not contain '200'. Found: '{content}'"
    assert content == '200', f"success.log must contain exactly '200'. Found: '{content}'"


def test_z_endpoint_actually_calls_execute_vm():
    lib_path = WORKSPACE_DIR / 'libvm.so'
    backup_path = WORKSPACE_DIR / '.libvm.so.verifier-backup'
    marker = Path('/tmp/vm_called_by_submission')
    shim_source = Path('/tmp/verifier_vm_shim.c')
    marker.unlink(missing_ok=True)
    backup_path.unlink(missing_ok=True)
    shim_source.write_text(r'''
#include <stdio.h>
#include <string.h>
int execute_vm(const char *instructions) {
    FILE *f = fopen("/tmp/vm_called_by_submission", "w");
    if (f) { fputs(instructions, f); fclose(f); }
    return 700000 + (int)strlen(instructions);
}
''')
    lib_path.rename(backup_path)
    try:
        build = subprocess.run(
            ['gcc', '-shared', '-fPIC', '-o', str(lib_path), str(shim_source)],
            capture_output=True,
            text=True,
        )
        assert build.returncode == 0, build.stdout + build.stderr
        probe_program = 'ADD 123\nSUB 456\nRET'
        expected = 700000 + len(probe_program.encode())
        probe = r'''
import json
import sys
sys.path.insert(0, '/home/user/workspace')
from fastapi.testclient import TestClient
import app
response = TestClient(app.app).post('/api/v1/execute', json={'program': 'ADD 123\nSUB 456\nRET'})
assert response.status_code == 200, response.text
assert response.json() == {'result': EXPECTED}, response.text
'''.replace('EXPECTED', str(expected))
        result = subprocess.run(
            [sys.executable, '-c', probe],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert marker.is_file(), 'The endpoint did not call the C execute_vm function'
        assert marker.read_text() == probe_program, 'The endpoint did not pass the submitted program to C'
    finally:
        lib_path.unlink(missing_ok=True)
        if backup_path.exists():
            backup_path.rename(lib_path)
        marker.unlink(missing_ok=True)
        shim_source.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
