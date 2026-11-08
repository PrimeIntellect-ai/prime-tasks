#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import math
import os
import pathlib
import subprocess
import sys

import pytest
from werkzeug.routing import FloatConverter

PROJECT = pathlib.Path('/home/user/math_api')
LIBRARY = PROJECT / 'build/libmath_ops.so'
RESULTS = pathlib.Path('/home/user/test_results.txt')

EXPECTED_TEST = '''import pytest
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from api.app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_hypotenuse(client):
    response = client.get('/api/hypotenuse/3.0/4.0')
    assert response.status_code == 200
    assert response.get_json() == {"result": 5.0}
'''


def test_00_original_final_state_assertions():
    cpp_file = PROJECT / 'src/math_ops.cpp'
    assert cpp_file.is_file(), f'File {cpp_file} does not exist.'
    content = cpp_file.read_text()
    assert 'extern "C"' in content, 'math_ops.cpp does not contain \'extern "C"\' to fix the ABI.'

    app_file = PROJECT / 'api/app.py'
    assert app_file.is_file(), f'File {app_file} does not exist.'
    content = app_file.read_text()
    assert '<float:a>' in content and '<float:b>' in content, 'app.py does not contain <float:a> and <float:b> in the route.'

    assert LIBRARY.is_file(), f'Shared library {LIBRARY} was not built.'

    assert RESULTS.is_file(), f'File {RESULTS} does not exist.'
    content = RESULTS.read_text()
    assert '1 passed' in content or 'passed in' in content or '100%' in content, 'test_results.txt does not indicate a successful pytest run.'


def _check_library(path):
    assert path.is_file(), f'{path} was not produced'
    assert path.read_bytes()[:4] == b'\x7fELF', f'{path} is not an ELF shared library'
    lib = ctypes.CDLL(str(path))
    function = lib.calculate_hypotenuse
    function.argtypes = [ctypes.c_double, ctypes.c_double]
    function.restype = ctypes.c_double
    cases = [(3.0, 4.0), (5.25, 12.75), (0.125, 0.375), (123.456, 78.9)]
    for a, b in cases:
        actual = function(a, b)
        expected = math.hypot(a, b)
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12)


def test_10_source_and_cmake_build_produce_working_library():
    build = PROJECT / 'build'
    configured = subprocess.run(
        ['cmake', '..'], cwd=build, text=True, capture_output=True, timeout=60
    )
    assert configured.returncode == 0, configured.stdout + configured.stderr

    if LIBRARY.exists():
        LIBRARY.unlink()
    compiled = subprocess.run(
        ['make'], cwd=build, text=True, capture_output=True, timeout=60
    )
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    _check_library(LIBRARY)

    direct_library = pathlib.Path('/tmp/verifier_math_ops.so')
    if direct_library.exists():
        direct_library.unlink()
    direct = subprocess.run(
        ['g++', '-std=c++14', '-shared', '-fPIC', str(PROJECT / 'src/math_ops.cpp'), '-o', str(direct_library)],
        text=True, capture_output=True, timeout=60
    )
    assert direct.returncode == 0, direct.stdout + direct.stderr
    _check_library(direct_library)


def test_20_flask_route_uses_float_converters_and_calls_library():
    sys.path.insert(0, str(PROJECT))
    sys.modules.pop('api.app', None)
    module = importlib.import_module('api.app')
    app = module.app

    matching = [rule for rule in app.url_map.iter_rules()
                if rule.rule == '/api/hypotenuse/<float:a>/<float:b>']
    assert len(matching) == 1, 'The required hypotenuse route is not registered'
    rule = matching[0]
    assert isinstance(rule._converters.get('a'), FloatConverter)
    assert isinstance(rule._converters.get('b'), FloatConverter)

    app.config['TESTING'] = True
    with app.test_client() as client:
        for a, b in [(3.0, 4.0), (6.25, 8.5), (0.5, 0.75)]:
            response = client.get(f'/api/hypotenuse/{a}/{b}')
            assert response.status_code == 200
            payload = response.get_json()
            assert isinstance(payload, dict) and isinstance(payload.get('result'), (int, float))
            assert payload['result'] == pytest.approx(math.hypot(a, b), rel=1e-12)
        for path in ['/api/hypotenuse/not-a-number/4.0',
                     '/api/hypotenuse/3.0/not-a-number']:
            assert client.get(path).status_code == 404


def test_30_original_tests_unchanged_and_really_pass():
    test_file = PROJECT / 'tests/test_api.py'
    assert test_file.is_file()
    assert test_file.read_text() == EXPECTED_TEST, 'tests/test_api.py was modified'

    run = subprocess.run(
        ['python3', '-m', 'pytest', 'tests/test_api.py'],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert run.returncode == 0, run.stdout + run.stderr
    assert 'tests/test_api.py' in run.stdout
    assert '1 passed' in run.stdout

    saved = RESULTS.read_text()
    assert 'tests/test_api.py' in saved, 'test_results.txt is not pytest output for tests/test_api.py'
    assert '1 passed' in saved, 'test_results.txt does not record the passing test run'
    assert ' failed' not in saved and ' error' not in saved.lower()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
