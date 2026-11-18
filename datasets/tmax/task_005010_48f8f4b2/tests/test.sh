#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import importlib.util
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import time
from functools import cmp_to_key
from pathlib import Path

import pytest
import requests
from packaging.version import parse

PACKAGE_DIR = Path('/app/semver_fast-1.0.0')
SERVER_PATH = Path('/home/user/semver_server.py')
TEST_PATH = Path('/home/user/test_semver.py')
URL = 'http://127.0.0.1:8888'


def expected_cmp(a, b):
    return (parse(a) > parse(b)) - (parse(a) < parse(b))


def make_versions(count=24):
    rng = secrets.SystemRandom()
    labels = ['alpha', 'beta', 'rc', 'dev', 'preview']
    versions = set()
    while len(versions) < count:
        major = rng.randrange(0, 30)
        minor = rng.randrange(0, 100)
        patch = rng.randrange(0, 1000)
        kind = rng.randrange(4)
        if kind == 0:
            value = f'{major}.{minor}.{patch}'
        elif kind == 1:
            value = f'{major}.{minor}.{patch}-{rng.choice(labels)}.{rng.randrange(0, 500)}'
        elif kind == 2:
            value = f'{major}.{minor}.{patch}-alpha.beta.{rng.randrange(0, 500)}'
        else:
            token = ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(70))
            value = f'{major}.{minor}.{patch}-alpha.{token}.{rng.randrange(0, 500)}'
        versions.add(value)
    return list(versions)


def post(path, payload):
    try:
        response = requests.post(URL + path, json=payload, timeout=8)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to {URL + path} or request failed: {exc}')
    assert response.status_code == 200, (
        f'Expected status code 200, got {response.status_code}. Response: {response.text}'
    )
    return response.json()


def test_source_and_compiled_extension_are_repaired():
    setup_path = PACKAGE_DIR / 'setup.py'
    source_path = PACKAGE_DIR / 'semver_fast.c'
    assert setup_path.is_file()
    assert source_path.is_file()

    setup_text = setup_path.read_text()
    assert 'semver_fast.c' in setup_text, 'setup.py must compile the actual C source'
    assert 'semver_fas.c' not in setup_text, 'setup.py still names the nonexistent source'

    source = source_path.read_text()
    without_comments = re.sub(r'/\\*.*?\\*/|//[^\\n]*', '', source, flags=re.S)
    assert not re.search(r'\\b(?:strcpy|strcat|sprintf|gets)\\s*\\(', without_comments), (
        'The C source still uses an unbounded string-copy operation'
    )

    spec = importlib.util.find_spec('semver_fast')
    assert spec is not None and spec.origin
    assert any(spec.origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f'semver_fast is not the installed compiled extension: {spec.origin}'
    )

    import semver_fast
    values = make_versions(35)
    values += [
        '1.0.0-alpha.beta.reallylongstring.1234567890',
        '1.0.0-super.long.prerelease.string.that.overflows.buffer.and.tests.the.fix',
        '999.888.777-rc.123456789012345678901234567890',
    ]
    for a in values:
        for b in values:
            result = semver_fast.compare(a, b)
            assert result in (-1, 0, 1)
            assert result == expected_cmp(a, b), (a, b, result, expected_cmp(a, b))


def test_hypothesis_script_exists():
    path = '/home/user/test_semver.py'
    assert os.path.isfile(path), f'File {path} does not exist'
    content = Path(path).read_text()
    assert 'hypothesis' in content, f'File {path} does not seem to use the hypothesis library'

    tree = ast.parse(content, filename=path)
    property_tests = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        has_given = any(
            isinstance(dec, ast.Call)
            and ((isinstance(dec.func, ast.Name) and dec.func.id == 'given')
                 or (isinstance(dec.func, ast.Attribute) and dec.func.attr == 'given'))
            and bool(dec.args or dec.keywords)
            for dec in node.decorator_list
        )
        calls_compare = any(
            isinstance(child, ast.Call)
            and isinstance(child.func, ast.Attribute)
            and child.func.attr == 'compare'
            for child in ast.walk(node)
        )
        calls_parse = any(
            isinstance(child, ast.Call)
            and ((isinstance(child.func, ast.Name) and child.func.id == 'parse')
                 or (isinstance(child.func, ast.Attribute) and child.func.attr == 'parse'))
            for child in ast.walk(node)
        )
        if has_given and calls_compare and calls_parse:
            property_tests.append(node.name)
    assert property_tests, 'No @given property test compares semver_fast.compare with packaging.parse'

    run = subprocess.run(
        [sys.executable, '-m', 'pytest', path, '-q', '--disable-warnings'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert run.returncode == 0, run.stdout
    assert re.search(r'\\b[1-9][0-9]* passed\\b', run.stdout), (
        'The Hypothesis script did not execute a passing test:\n' + run.stdout
    )


def test_server_sort_endpoint():
    long_version = '1.0.0-super.long.prerelease.string.that.overflows.buffer.and.tests.the.fix'
    payload = {
        'versions': ['3.0.0', '1.0.0-rc.1', '1.0.0-beta', '2.0.0', long_version]
    }
    data = post('/sort', payload)
    assert 'sorted' in data, f"Expected 'sorted' key in response, got: {data}"
    expected_sorted = ['1.0.0-beta', '1.0.0-rc.1', long_version, '2.0.0', '3.0.0']
    assert data['sorted'] == expected_sorted, (
        f"Expected sorted versions {expected_sorted}, got {data['sorted']}"
    )


def test_server_diff_endpoint():
    payload = {
        'base': ['1.2.3', '2.0.0'],
        'target': ['1.2.3', '3.0.0-alpha', '2.0.0', '4.0.0']
    }
    data = post('/diff', payload)
    assert 'diff' in data, f"Expected 'diff' key in response, got: {data}"
    expected_diff = ['3.0.0-alpha', '4.0.0']
    assert data['diff'] == expected_diff, f"Expected diff {expected_diff}, got {data['diff']}"


def test_server_on_unpredictable_inputs():
    versions = make_versions(31)
    secrets.SystemRandom().shuffle(versions)
    data = post('/sort', {'versions': versions})
    assert set(data) == {'sorted'}
    assert data['sorted'] == sorted(versions, key=parse)

    base = make_versions(18)
    additions = make_versions(13)
    target = list(base[:9]) + additions
    secrets.SystemRandom().shuffle(target)
    data = post('/diff', {'base': base, 'target': target})
    expected = sorted([v for v in target if v not in set(base)], key=parse)
    assert set(data) == {'diff'}
    assert data['diff'] == expected


def listener_pids(port=8888):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and int(fields[1].rsplit(':', 1)[1], 16) == port and fields[3] == '0A':
                inodes.add(fields[9])
    found = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    found.add(int(proc.name))
        except OSError:
            pass
    return found


def stop_listener():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids():
            return
        time.sleep(0.1)
    raise AssertionError('Server did not begin listening on 127.0.0.1:8888')


def test_server_sorting_actually_calls_semver_fast():
    assert SERVER_PATH.is_file()
    shim_dir = Path('/tmp/semver_instrument')
    shim_dir.mkdir(exist_ok=True)
    log_path = Path('/tmp/semver_compare_calls.jsonl')
    log_path.unlink(missing_ok=True)
    (shim_dir / 'semver_fast.py').write_text(
        "import json, os\n"
        "from packaging.version import parse\n"
        "def compare(a, b):\n"
        "    with open(os.environ['SEMVER_COMPARE_LOG'], 'a') as f:\n"
        "        f.write(json.dumps([a, b]) + '\\n')\n"
        "    return (parse(a) > parse(b)) - (parse(a) < parse(b))\n"
    )

    stop_listener()
    instrumented = None
    restored = None
    try:
        env = os.environ.copy()
        env['PYTHONPATH'] = str(shim_dir)
        env['SEMVER_COMPARE_LOG'] = str(log_path)
        env['PYTHONUNBUFFERED'] = '1'
        instrumented = subprocess.Popen(
            [sys.executable, str(SERVER_PATH)], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for_server()

        versions = make_versions(17)
        secrets.SystemRandom().shuffle(versions)
        result = post('/sort', {'versions': versions})
        assert result['sorted'] == sorted(versions, key=parse)
        assert log_path.is_file(), 'The server never invoked semver_fast.compare while sorting'
        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        assert calls, 'The server never invoked semver_fast.compare while sorting'
        assert all(len(pair) == 2 and pair[0] in versions and pair[1] in versions for pair in calls)
    finally:
        stop_listener()
        if instrumented is not None and instrumented.poll() is None:
            instrumented.kill()
            instrumented.wait(timeout=5)
        clean_env = os.environ.copy()
        clean_env.pop('PYTHONPATH', None)
        clean_env.pop('SEMVER_COMPARE_LOG', None)
        restored = subprocess.Popen(
            [sys.executable, str(SERVER_PATH)], env=clean_env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        wait_for_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
