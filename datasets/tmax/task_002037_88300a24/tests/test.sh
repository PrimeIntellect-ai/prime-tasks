#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import glob
import importlib.util
import inspect
import json
import math
import os
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

import pytest

LIB1 = '/home/user/libs/libmathops.so.1.0.0'
LIB2 = '/home/user/libs/libmathops.so.2.1.0'


def load_trajectory(path):
    lib = ctypes.CDLL(path)
    fn = lib.calculate_trajectory
    fn.argtypes = [ctypes.c_double, ctypes.c_double]
    fn.restype = ctypes.c_double
    return fn


def test_shared_libraries_exist():
    for path in (LIB1, LIB2):
        assert os.path.isfile(path), f'Shared library {path} is missing.'
        with open(path, 'rb') as f:
            assert f.read(4) == b'\x7fELF', f'{path} is not a valid ELF file.'

    fn1 = load_trajectory(LIB1)
    fn2 = load_trajectory(LIB2)
    rng = secrets.SystemRandom()
    for _ in range(4):
        velocity = rng.uniform(2.0, 90.0)
        angle = rng.uniform(0.08, 1.45)
        base = velocity * velocity * math.sin(2.0 * angle) / 9.81
        assert math.isclose(fn1(velocity, angle), base, rel_tol=1e-10, abs_tol=1e-10)
        assert math.isclose(fn2(velocity, angle), base * 0.95, rel_tol=1e-10, abs_tol=1e-10)


def test_deployment_summary():
    summary_path = '/home/user/deployment_summary.json'
    assert os.path.isfile(summary_path), f'File {summary_path} is missing.'
    with open(summary_path) as f:
        data = json.load(f)
    assert data.get('selected_version') == '2.1.0'
    assert data.get('library_path') == LIB2
    assert data.get('api_port') == 8080
    assert set(data) == {'selected_version', 'library_path', 'api_port'}, 'Deployment summary has an incorrect structure.'


def request_trajectory(v, theta):
    payload = json.dumps({'v': v, 'theta': theta}).encode()
    req = urllib.request.Request(
        'http://127.0.0.1:8080/api/trajectory',
        data=payload,
        headers={'Content-Type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200
            return json.loads(response.read().decode())
    except urllib.error.URLError as exc:
        pytest.fail(f'Failed to connect to API on port 8080: {exc}')


def test_api_running_and_correct():
    rng = secrets.SystemRandom()
    cases = [(10.0, math.pi / 4)]
    cases.extend((rng.uniform(1.5, 120.0), rng.uniform(0.05, 1.5)) for _ in range(5))
    for velocity, angle in cases:
        result = request_trajectory(velocity, angle)
        assert 'distance' in result
        assert 'version_used' in result
        assert result['version_used'] == '2.1.0'
        expected = velocity * velocity * math.sin(2.0 * angle) / 9.81 * 0.95
        assert isinstance(result['distance'], (int, float))
        assert math.isclose(result['distance'], expected, rel_tol=1e-7, abs_tol=1e-8), (
            f'Incorrect distance for v={velocity}, theta={angle}: {result["distance"]}'
        )


def test_api_uses_mockable_ctypes_function(monkeypatch):
    api_path = '/home/user/api.py'
    assert os.path.isfile(api_path)

    loaded_paths = []
    calls = []

    class FakeFunction:
        def __init__(self):
            self.argtypes = None
            self.restype = None

        def __call__(self, *args):
            calls.append(args)
            return 999.99

    fake_function = FakeFunction()

    class FakeLibrary:
        calculate_trajectory = fake_function

    def fake_cdll(path, *args, **kwargs):
        loaded_paths.append(os.fspath(path))
        return FakeLibrary()

    monkeypatch.setattr(ctypes, 'CDLL', fake_cdll)
    monkeypatch.setattr(ctypes.cdll, 'LoadLibrary', fake_cdll)

    module_name = 'api_verifier_import'
    spec = importlib.util.spec_from_file_location(module_name, api_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
        app = getattr(module, 'app', None)
        assert app is not None, 'api.py does not expose a FastAPI app.'
        route = next((r for r in app.routes if getattr(r, 'path', None) == '/api/trajectory' and 'POST' in getattr(r, 'methods', set())), None)
        assert route is not None, 'POST /api/trajectory is missing.'

        endpoint = route.endpoint
        signature = inspect.signature(endpoint)
        parameters = list(signature.parameters.values())
        if len(parameters) == 1:
            annotation = parameters[0].annotation
            if isinstance(annotation, type):
                argument = annotation(v=7.25, theta=0.41)
            else:
                argument = {'v': 7.25, 'theta': 0.41}
            result = endpoint(argument)
        else:
            result = endpoint(v=7.25, theta=0.41)
        if inspect.isawaitable(result):
            result = asyncio.run(result)
        if hasattr(result, 'model_dump'):
            result = result.model_dump()
        elif hasattr(result, 'dict') and not isinstance(result, dict):
            result = result.dict()

        assert loaded_paths, 'api.py did not load a shared library through ctypes.'
        assert any(path.endswith('libmathops.so.2.1.0') for path in loaded_paths), loaded_paths
        assert calls, 'The endpoint did not call calculate_trajectory.'
        assert isinstance(result, dict)
        assert math.isclose(result['distance'], 999.99, rel_tol=0, abs_tol=1e-9)
        assert result['version_used'] == '2.1.0'
    finally:
        sys.modules.pop(module_name, None)


def selection_signal(script, timeout=5):
    runner = r'''
import inspect, json, runpy
path = __import__('sys').argv[1]
ns = runpy.run_path(path, run_name='__main__')
signals = []
for key, value in ns.items():
    low = key.lower()
    if any(word in low for word in ('selected', 'chosen', 'best', 'resolved')):
        try:
            signals.append(str(value))
        except Exception:
            pass
for key, value in list(ns.items()):
    low = key.lower()
    if callable(value) and any(word in low for word in ('select', 'determine', 'resolve')):
        try:
            sig = inspect.signature(value)
            args = []
            usable = True
            for p in sig.parameters.values():
                if p.kind in (p.VAR_POSITIONAL, p.VAR_KEYWORD):
                    continue
                n = p.name.lower()
                if 'manifest' in n:
                    args.append('/home/user/release_manifest.json')
                elif 'lib' in n or 'dir' in n or 'path' in n:
                    args.append('/home/user/libs')
                elif p.default is inspect.Parameter.empty:
                    usable = False
            if usable:
                signals.append(str(value(*args)))
        except Exception:
            pass
print('__SELECTION_SIGNALS__' + json.dumps(signals))
'''
    proc = subprocess.run(
        [sys.executable, '-c', runner, script],
        cwd='/home/user', text=True, capture_output=True, timeout=timeout
    )
    output = proc.stdout + '\n' + proc.stderr
    summary_path = '/home/user/deployment_summary.json'
    if os.path.isfile(summary_path):
        try:
            output += '\n' + str(json.load(open(summary_path)).get('selected_version', ''))
        except Exception:
            pass
    return proc.returncode, output


def test_semantic_version_selection_script():
    candidates = [
        p for p in glob.glob('/home/user/*.py')
        if os.path.basename(p) not in {'api.py', 'test_api.py'}
    ]
    assert candidates, 'No separate semantic-version selection script was created.'

    manifest_path = '/home/user/release_manifest.json'
    summary_path = '/home/user/deployment_summary.json'
    original_manifest = open(manifest_path, 'rb').read()
    original_summary = open(summary_path, 'rb').read() if os.path.exists(summary_path) else None
    scenarios = [('<2.0.0', '1.0.0', '2.1.0'), ('>=1.0.0', '2.1.0', '1.0.0')]
    successful = []
    try:
        for candidate in candidates:
            passed = True
            for constraint, expected, wrong in scenarios:
                with open(manifest_path, 'w') as f:
                    json.dump({'release_name': 'Verifier', 'dependencies': {'mathops': constraint}}, f)
                with open(summary_path, 'w') as f:
                    json.dump({'selected_version': '__unset__'}, f)
                try:
                    code, signal = selection_signal(candidate)
                except subprocess.TimeoutExpired:
                    passed = False
                    break
                if code != 0 or expected not in signal or wrong in signal:
                    passed = False
                    break
            if passed:
                successful.append(candidate)
        assert successful, 'No selection script correctly handled changing semantic-version constraints.'
    finally:
        with open(manifest_path, 'wb') as f:
            f.write(original_manifest)
        if original_summary is None:
            try:
                os.remove(summary_path)
            except FileNotFoundError:
                pass
        else:
            with open(summary_path, 'wb') as f:
                f.write(original_summary)


def test_test_results_xml():
    xml_path = '/home/user/test_results.xml'
    assert os.path.isfile(xml_path), f'File {xml_path} is missing.'
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        pytest.fail(f'File {xml_path} is not valid XML.')
    assert list(root.iter('testcase')), 'No test cases found in test_results.xml.'
    assert not list(root.iter('failure')) and not list(root.iter('error'))


def test_mocked_pytest_suite_really_runs():
    test_path = '/home/user/test_api.py'
    assert os.path.isfile(test_path), 'test_api.py is missing.'
    source = open(test_path, encoding='utf-8').read()
    assert 'mock' in source.lower(), 'test_api.py does not use mocking.'
    assert '999.99' in source, 'test_api.py does not test the required mocked return value.'
    assert 'trajectory' in source and ('ctypes' in source or 'calculate_trajectory' in source)

    fresh_xml = '/tmp/user_test_results.xml'
    proc = subprocess.run(
        [sys.executable, '-m', 'pytest', test_path, '-q', '--junitxml=' + fresh_xml],
        cwd='/home/user', text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, proc.stdout + '\n' + proc.stderr
    root = ET.parse(fresh_xml).getroot()
    assert list(root.iter('testcase'))
    assert not list(root.iter('failure')) and not list(root.iter('error'))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
