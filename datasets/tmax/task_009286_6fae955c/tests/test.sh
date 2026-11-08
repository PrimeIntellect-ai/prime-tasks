#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import importlib.machinery
import importlib.metadata
import json
import os
import pathlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import Mock, patch

import pytest

PROJECT = pathlib.Path('/home/user/pricing_engine')


def test_ceval_module_importable_and_functional():
    sys.path.insert(0, str(PROJECT))
    try:
        import ceval
    except ImportError:
        pytest.fail("The 'ceval' module could not be imported. Did you fix setup.py and install the package?")

    try:
        result = ceval.eval_expr("MUL 3 4")
        assert result == 12, f"Expected ceval.eval_expr('MUL 3 4') to return 12, got {result}"
    except Exception as e:
        pytest.fail(f"Calling ceval.eval_expr failed: {e}")


def test_ceval_is_a_real_extension_and_handles_derived_inputs():
    sys.path.insert(0, str(PROJECT))
    sys.modules.pop('ceval', None)
    ceval = importlib.import_module('ceval')
    module_path = os.path.realpath(ceval.__file__)
    assert module_path.startswith(os.path.realpath(str(PROJECT)) + os.sep)
    assert any(module_path.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f'ceval must be a compiled Python extension, not {module_path}'

    a = secrets.randbelow(80) + 20
    b = secrets.randbelow(17) + 2
    cases = {
        f'ADD {a} {b}': a + b,
        f'SUB {a} {b}': a - b,
        f'MUL {a} {b}': a * b,
        f'DIV {a} {b}': a // b,
    }
    for expression, expected in cases.items():
        assert ceval.eval_expr(expression) == expected
    with pytest.raises(ZeroDivisionError):
        ceval.eval_expr(f'DIV {a} 0')
    with pytest.raises(ValueError):
        ceval.eval_expr(f'NOPE {a} {b}')
    with pytest.raises(ValueError):
        ceval.eval_expr('not an expression')


def test_setup_py_actually_builds_ceval_from_ceval_c():
    setup_py = PROJECT / 'setup.py'
    source = PROJECT / 'ceval.c'
    assert setup_py.is_file(), f'File {setup_py} does not exist'
    assert source.is_file(), f'File {source} does not exist'

    with tempfile.TemporaryDirectory() as td:
        td_path = pathlib.Path(td)
        shutil.copy2(setup_py, td_path / 'setup.py')
        shutil.copy2(source, td_path / 'ceval.c')
        proc = subprocess.run(
            [sys.executable, 'setup.py', 'build_ext', '--inplace'],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert proc.returncode == 0, f'setup.py could not build ceval.c:\n{proc.stdout}'
        built = [p for p in td_path.iterdir() if p.name.startswith('ceval') and
                 any(p.name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)]
        assert built, f'setup.py did not produce a ceval extension:\n{proc.stdout}'

        a = secrets.randbelow(40) + 3
        b = secrets.randbelow(12) + 2
        check = subprocess.run(
            [sys.executable, '-c',
             'import ceval,sys; a=int(sys.argv[1]); b=int(sys.argv[2]); '
             'assert ceval.eval_expr(f"ADD {a} {b}")==a+b; '
             'assert ceval.eval_expr(f"MUL {a} {b}")==a*b', str(a), str(b)],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert check.returncode == 0, f'freshly built extension failed:\n{check.stdout}'


def test_package_was_installed_editable():
    try:
        dist = importlib.metadata.distribution('pricing_engine')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail('pricing_engine is not installed')

    direct_url = dist.read_text('direct_url.json')
    if direct_url:
        info = json.loads(direct_url)
        assert info.get('dir_info', {}).get('editable') is True, 'pricing_engine is not installed editable'
        assert os.path.realpath(info['url'].replace('file://', '')) == os.path.realpath(str(PROJECT))
    else:
        egg_links = list(pathlib.Path('/usr/local/lib').rglob('pricing-engine.egg-link')) + \
                    list(pathlib.Path('/usr/local/lib').rglob('pricing_engine.egg-link'))
        assert any(os.path.realpath(p.read_text().splitlines()[0]) == os.path.realpath(str(PROJECT))
                   for p in egg_links), 'pricing_engine is not installed editable'


def test_engine_semantic_versions_requests_and_derived_expression():
    sys.path.insert(0, str(PROJECT))
    sys.modules.pop('engine', None)
    engine = importlib.import_module('engine')
    assert os.path.realpath(engine.__file__) == os.path.realpath(str(PROJECT / 'engine.py'))

    for low_version in ('1.4.9', '1.4.10', '0.99.99'):
        with patch.object(engine.requests, 'get') as get:
            assert engine.get_and_eval(low_version) == -1
            get.assert_not_called()

    a = secrets.randbelow(70) + 10
    b = secrets.randbelow(19) + 2
    response = Mock()
    response.json.return_value = {'expression': f'MUL {a} {b}'}
    with patch.object(engine.requests, 'get', return_value=response) as get:
        assert engine.get_and_eval('1.10.0') == a * b
        get.assert_called_once_with('http://api.internal/rules?v=1.10.0')
        response.json.assert_called_once_with()

    response = Mock()
    response.json.return_value = {'expression': f'ADD {a} {b}'}
    with patch.object(engine.requests, 'get', return_value=response) as get:
        assert engine.get_and_eval('1.5.0') == a + b
        get.assert_called_once_with('http://api.internal/rules?v=1.5.0')


def _call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return _call_name(node.value) + '.' + node.attr
    return ''


def _function_calls(fn):
    return [n for n in ast.walk(fn) if isinstance(n, ast.Call)]


def test_test_engine_py_exists_and_contains_tests():
    path = "/home/user/pricing_engine/test_engine.py"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "test_version_too_low" in content, "test_engine.py is missing 'test_version_too_low'"
    assert "test_evaluate_success" in content, "test_engine.py is missing 'test_evaluate_success'"
    assert "patch" in content, "test_engine.py does not seem to use 'patch' from unittest.mock"

    tree = ast.parse(content, filename=path)
    functions = {n.name: n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert set(functions) >= {'test_version_too_low', 'test_evaluate_success'}

    low = functions['test_version_too_low']
    low_calls = _function_calls(low)
    assert any(_call_name(c.func).endswith('get_and_eval') and
               len(c.args) == 1 and isinstance(c.args[0], ast.Constant) and c.args[0].value == '1.4.9'
               for c in low_calls), 'test_version_too_low must call get_and_eval("1.4.9")'
    assert any(_call_name(c.func).endswith('assert_not_called') for c in low_calls), \
        'test_version_too_low must assert that requests.get was not called'
    assert any(isinstance(n, ast.Constant) and n.value == -1 for n in ast.walk(low)), \
        'test_version_too_low must assert the -1 result'

    success = functions['test_evaluate_success']
    success_calls = _function_calls(success)
    assert any(_call_name(c.func).endswith('get_and_eval') and
               len(c.args) == 1 and isinstance(c.args[0], ast.Constant) and c.args[0].value == '2.0.0'
               for c in success_calls), 'test_evaluate_success must call get_and_eval("2.0.0")'
    assert any(isinstance(n, ast.Constant) and n.value == 'MUL 7 8' for n in ast.walk(success)), \
        'test_evaluate_success must mock the expression MUL 7 8'
    assert any(isinstance(n, ast.Constant) and n.value == 56 for n in ast.walk(success)), \
        'test_evaluate_success must assert the result 56'
    for fn in (low, success):
        assert any(_call_name(c.func).endswith('patch') and c.args and
                   isinstance(c.args[0], ast.Constant) and str(c.args[0].value).endswith('requests.get')
                   for c in _function_calls(fn)), f'{fn.name} must patch requests.get'


def test_agent_pytest_suite_really_passes_two_tests():
    proc = subprocess.run(
        [sys.executable, '-m', 'pytest', str(PROJECT / 'test_engine.py'), '-v'],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert proc.returncode == 0, f'test_engine.py failed:\n{proc.stdout}'
    assert re.search(r'\b2 passed\b', proc.stdout), f'Expected exactly two passing tests:\n{proc.stdout}'


def test_run_tests_sh_exists_and_executable():
    path = "/home/user/pricing_engine/run_tests.sh"
    assert os.path.isfile(path), f"Script {path} does not exist"
    assert os.access(path, os.X_OK), f"Script {path} is not executable"
    content = pathlib.Path(path).read_text()
    assert 'pytest' in content
    assert '/home/user/pricing_engine/test_engine.py' in content
    assert '-v' in content
    assert '/home/user/pricing_engine/test_results.log' in content
    assert '>' in content, 'run_tests.sh must redirect standard output to test_results.log'


def test_run_tests_script_executes_and_regenerates_log():
    script = PROJECT / 'run_tests.sh'
    log = PROJECT / 'test_results.log'
    if log.exists():
        log.unlink()
    proc = subprocess.run([str(script)], cwd=str(PROJECT), text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert proc.returncode == 0, f'run_tests.sh failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    assert log.is_file(), 'run_tests.sh did not generate test_results.log'


def test_test_results_log_contains_success():
    path = "/home/user/pricing_engine/test_results.log"
    assert os.path.isfile(path), f"Log file {path} does not exist. Did you run the tests and redirect output?"

    with open(path, "r") as f:
        content = f.read()

    assert "test_version_too_low" in content, "test_results.log does not mention 'test_version_too_low'"
    assert "test_evaluate_success" in content, "test_results.log does not mention 'test_evaluate_success'"
    assert "2 passed" in content or "2 successful" in content, "test_results.log does not indicate that 2 tests passed"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
