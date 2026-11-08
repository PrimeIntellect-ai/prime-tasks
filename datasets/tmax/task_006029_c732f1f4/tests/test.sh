#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib
import importlib.machinery
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

import pytest

ROOT = '/home/user/polymath'
JSON_PATH = os.path.join(ROOT, 'data/matrix.json')
HEADER_PATH = os.path.join(ROOT, 'src/constants.h')
GENERATOR_PATH = os.path.join(ROOT, 'generate_headers.py')
SETUP_PATH = os.path.join(ROOT, 'setup.py')
CI_PATH = os.path.join(ROOT, 'ci_build.sh')
RESULT_PATH = os.path.join(ROOT, 'ci_result.txt')
DIST_DIR = os.path.join(ROOT, 'dist')


def run(command, **kwargs):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
        **kwargs,
    )


def test_01_generator_exists_and_transforms_current_json():
    assert os.path.isfile(GENERATOR_PATH), f'Expected generator at {GENERATOR_PATH}.'
    assert os.path.isfile(JSON_PATH), f'Expected JSON file at {JSON_PATH}.'

    with open(JSON_PATH, 'rb') as f:
        original_json = f.read()
    original_header = None
    if os.path.isfile(HEADER_PATH):
        with open(HEADER_PATH, 'rb') as f:
            original_header = f.read()

    key = 'VERIFY_' + secrets.token_hex(8).upper()
    value = secrets.randbelow(800000000) + 100000001
    probe = {
        key: value,
        'PROBE_ZERO': 0,
        'PROBE_NEGATIVE': -17,
        'PROBE_LARGE': 987654321,
    }

    try:
        with open(JSON_PATH, 'w') as f:
            json.dump(probe, f)
        if os.path.exists(HEADER_PATH):
            os.remove(HEADER_PATH)

        proc = run([sys.executable, GENERATOR_PATH], cwd=ROOT)
        assert proc.returncode == 0, (
            f'generate_headers.py failed:\nstdout={proc.stdout}\nstderr={proc.stderr}'
        )
        assert os.path.isfile(HEADER_PATH), 'generate_headers.py did not create src/constants.h.'
        with open(HEADER_PATH) as f:
            content = f.read()
        for macro, macro_value in probe.items():
            assert f'#define {macro} {macro_value}' in content
    finally:
        with open(JSON_PATH, 'wb') as f:
            f.write(original_json)
        if original_header is None:
            if os.path.exists(HEADER_PATH):
                os.remove(HEADER_PATH)
        else:
            with open(HEADER_PATH, 'wb') as f:
                f.write(original_header)


def _call_name(call):
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def test_02_setup_py_uses_extension_for_fib_source():
    assert os.path.isfile(SETUP_PATH), f'File {SETUP_PATH} is missing.'
    with open(SETUP_PATH) as f:
        content = f.read()

    # Preserve the original assertions.
    assert 'fib_ext' in content, "setup.py does not define the extension module 'fib_ext'."
    assert 'fib.c' in content, "setup.py does not reference the source file 'fib.c'."

    tree = ast.parse(content, filename=SETUP_PATH)
    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value

    def resolve(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return resolve(assignments[node.id], seen | {node.id})
        return node

    def contains_extension(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            return contains_extension(assignments[node.id], seen | {node.id})
        if isinstance(node, ast.Call) and _call_name(node) == 'Extension':
            return True
        return any(contains_extension(child, seen) for child in ast.iter_child_nodes(node))

    extension_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and _call_name(node) == 'Extension'
    ]
    assert extension_calls, 'setup.py does not call setuptools.Extension.'

    correct_extension = False
    for call in extension_calls:
        strings = [n.value for n in ast.walk(call) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
        # Also resolve simple variables used for the extension name or source list.
        for arg in call.args:
            resolved = resolve(arg)
            strings.extend(
                n.value for n in ast.walk(resolved)
                if isinstance(n, ast.Constant) and isinstance(n.value, str)
            )
        for keyword in call.keywords:
            resolved = resolve(keyword.value)
            strings.extend(
                n.value for n in ast.walk(resolved)
                if isinstance(n, ast.Constant) and isinstance(n.value, str)
            )
        if 'fib_ext' in strings and any(s.replace('\\', '/').endswith('src/fib.c') for s in strings):
            correct_extension = True
            break
    assert correct_extension, "Extension must name 'fib_ext' and compile src/fib.c."

    setup_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and _call_name(node) == 'setup'
    ]
    assert setup_calls, 'setup.py does not call setup().'
    assert any(
        keyword.arg == 'ext_modules' and contains_extension(keyword.value)
        for call in setup_calls for keyword in call.keywords
    ), 'The Extension is not supplied to setup() through ext_modules.'


def test_03_ci_script_executes_complete_pipeline():
    assert os.path.isfile(CI_PATH), f'Expected CI script at {CI_PATH}.'
    assert os.stat(CI_PATH).st_mode & stat.S_IXUSR, 'ci_build.sh is not executable.'

    # Force the pipeline to recreate every required artifact rather than accepting
    # files left behind before verification.
    for path in (DIST_DIR, os.path.join(ROOT, 'build')):
        shutil.rmtree(path, ignore_errors=True)
    for path in (HEADER_PATH, RESULT_PATH):
        if os.path.exists(path):
            os.remove(path)

    proc = run(['bash', '-x', './ci_build.sh'], cwd=ROOT)
    trace = proc.stderr
    assert proc.returncode == 0, f'ci_build.sh failed:\nstdout={proc.stdout}\nstderr={trace}'

    traced_commands = [line[2:] for line in trace.splitlines() if line.startswith('+ ')]
    assert any('generate_headers.py' in line and ('python' in line) for line in traced_commands), \
        'ci_build.sh did not execute generate_headers.py.'
    assert any('setup.py' in line and 'bdist_wheel' in line for line in traced_commands), \
        'ci_build.sh did not execute setup.py bdist_wheel.'
    assert any(re.search(r'\bpip(?:3)?\b', line) and ' install ' in f' {line} ' and '.whl' in line
               for line in traced_commands), \
        'ci_build.sh did not execute pip install for the built wheel.'
    assert any('python' in line and '-c' in line and 'import fib_ext' in line and 'fib_ext.fib(10)' in line
               for line in traced_commands), \
        'ci_build.sh did not execute the required fib_ext test command.'

    # Preserve and strengthen the original generated-header assertion.
    assert os.path.isfile(HEADER_PATH), 'The CI run did not generate src/constants.h.'
    with open(JSON_PATH) as f:
        data = json.load(f)
    with open(HEADER_PATH) as f:
        header_content = f.read()
    for key, value in data.items():
        expected_macro = f'#define {key} {value}'
        assert expected_macro in header_content, f"Expected macro '{expected_macro}' not found."

    # Preserve the original wheel assertion.
    assert os.path.isdir(DIST_DIR), f'Distribution directory {DIST_DIR} is missing.'
    wheels = glob.glob(os.path.join(DIST_DIR, '*.whl'))
    assert wheels, f'No wheel files found in {DIST_DIR}.'
    for wheel in wheels:
        assert zipfile.is_zipfile(wheel), f'{wheel} is not a valid wheel/ZIP archive.'

    # Preserve the exact ci_result.txt assertion.
    assert os.path.isfile(RESULT_PATH), 'ci_result.txt is missing after the CI run.'
    with open(RESULT_PATH) as f:
        result = f.read()
    assert result == '55\n', f"Expected ci_result.txt to contain exactly '55\\n', got {result!r}."


def _expected_fib(n, modulus=1000000007):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, (a + b) % modulus
    return a


def test_04_wheel_contains_and_runs_real_native_extension():
    wheels = glob.glob(os.path.join(DIST_DIR, '*.whl'))
    assert wheels, 'No built wheel is available for behavioral testing.'
    wheel = max(wheels, key=os.path.getmtime)

    with zipfile.ZipFile(wheel) as archive:
        names = archive.namelist()
    suffixes = tuple(importlib.machinery.EXTENSION_SUFFIXES)
    assert any(os.path.basename(name).startswith('fib_ext') and name.endswith(suffixes) for name in names), \
        'The wheel does not contain a native fib_ext extension module.'

    target = tempfile.mkdtemp(prefix='polymath-wheel-')
    try:
        install = run([
            sys.executable, '-m', 'pip', 'install', '--no-deps', '--force-reinstall',
            '--target', target, wheel,
        ], cwd='/tmp')
        assert install.returncode == 0, f'Could not install built wheel:\n{install.stdout}\n{install.stderr}'

        random_inputs = [secrets.randbelow(20000) for _ in range(12)]
        inputs = [0, 1, 2, 3, 5, 10, 50, 100, 1000, 10000] + random_inputs
        expected = [_expected_fib(n) for n in inputs]
        code = (
            'import fib_ext, json, os; '
            'print(json.dumps({"origin": fib_ext.__file__, '
            '"values": [fib_ext.fib(n) for n in ' + repr(inputs) + ']}))'
        )
        env = os.environ.copy()
        env['PYTHONPATH'] = target
        env['PYTHONNOUSERSITE'] = '1'
        check = run([sys.executable, '-c', code], cwd='/tmp', env=env)
        assert check.returncode == 0, f'Installed fib_ext failed:\n{check.stdout}\n{check.stderr}'
        payload = json.loads(check.stdout.strip())
        origin = os.path.realpath(payload['origin'])
        assert os.path.commonpath([origin, os.path.realpath(target)]) == os.path.realpath(target), \
            f'fib_ext was not imported from the freshly installed wheel: {origin}'
        assert origin.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)), \
            f'fib_ext is not a native extension: {origin}'
        assert payload['values'] == expected, 'fib_ext returned incorrect Fibonacci values.'
    finally:
        shutil.rmtree(target, ignore_errors=True)


def test_05_fib_ext_installed_by_ci():
    # Preserve the original installed-module check, while exercising more than fib(10).
    importlib.invalidate_caches()
    try:
        import fib_ext
    except ImportError:
        pytest.fail('Failed to import fib_ext after ci_build.sh installed the wheel.')
    assert fib_ext.fib(10) == 55
    assert fib_ext.fib(0) == 0
    assert fib_ext.fib(50) == _expected_fib(50)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
