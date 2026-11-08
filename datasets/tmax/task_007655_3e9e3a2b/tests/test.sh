#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
from urllib.parse import parse_qsl, urlsplit

import pytest

PROJECT = '/home/user/modern_project'
VENV_PY = os.path.join(PROJECT, 'venv', 'bin', 'python')
if not os.path.isfile(VENV_PY):
    VENV_PY = os.path.join(PROJECT, 'venv', 'bin', 'python3')


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_test_script():
    test_path = '/home/user/test_app.py'
    assert os.path.isfile(test_path), 'test_app.py script is missing'
    assert os.path.isfile(VENV_PY), 'Python executable not found in venv'

    log_path = '/home/user/results.log'
    trace_path = '/tmp/test_app_trace.json'
    for path in (log_path, trace_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    wrapper = r'''import json
import os
import runpy
import sys
from flask.testing import FlaskClient

trace = []
original_open = FlaskClient.open

def tracked_open(self, *args, **kwargs):
    url = args[0] if args and isinstance(args[0], str) else kwargs.get('path', '')
    query = kwargs.get('query_string')
    pairs = []
    if query is not None:
        try:
            pairs = list(query.items(multi=True))
        except TypeError:
            pairs = list(query.items())
        except AttributeError:
            pairs = list(query)
        pairs = [[str(k), str(v)] for k, v in pairs]
    trace.append({'url': url, 'query': pairs})
    return original_open(self, *args, **kwargs)

FlaskClient.open = tracked_open
sys.path.insert(0, '/home/user')
try:
    runpy.run_path('/home/user/test_app.py', run_name='__main__')
finally:
    with open('/tmp/test_app_trace.json', 'w') as f:
        json.dump(trace, f)
'''
    proc = subprocess.run(
        [VENV_PY, '-c', wrapper], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, 'test_app.py failed when executed:\n' + proc.stdout + proc.stderr
    assert os.path.isfile(trace_path), 'test_app.py execution trace was not produced'

    with open(trace_path) as f:
        trace = json.load(f)

    observed = []
    for entry in trace:
        parts = urlsplit(entry.get('url', ''))
        pairs = parse_qsl(parts.query, keep_blank_values=True)
        pairs.extend((str(k), str(v)) for k, v in entry.get('query', []))
        observed.append((parts.path, dict(pairs)))

    expected = [
        ('/evaluate', {'expr': 'a*b+2', 'a': '5', 'b': '3'}),
        ('/evaluate', {'expr': 'x/y-z', 'x': '10', 'y': '2', 'z': '1'}),
        ('/evaluate', {'expr': 'foo*bar', 'foo': '7'}),
    ]
    for wanted in expected:
        assert wanted in observed, f'test_app.py did not request required URL/query: {wanted}'


def test_modern_project_exists():
    assert os.path.isdir('/home/user/modern_project'), "Modern project directory is missing"


def test_venv_exists():
    assert os.path.isdir('/home/user/modern_project/venv'), "Virtual environment directory 'venv' is missing"
    assert os.path.isfile('/home/user/modern_project/venv/bin/python') or os.path.isfile('/home/user/modern_project/venv/bin/python3'), "Python executable not found in venv"


def test_requirements_file():
    req_path = '/home/user/modern_project/requirements.txt'
    assert os.path.isfile(req_path), "requirements.txt is missing in modern project"
    with open(req_path, 'r') as f:
        content = f.read()
    assert re.search(r'Flask\s*>=\s*2\.0\.0', content, re.IGNORECASE), "Flask>=2.0.0 not found in requirements.txt"
    assert re.search(r'Werkzeug\s*>=\s*2\.0\.0', content, re.IGNORECASE), "Werkzeug>=2.0.0 not found in requirements.txt"


def test_dependencies_installed_in_venv():
    code = r'''import importlib.metadata as m
import re

def version_tuple(name):
    nums = [int(x) for x in re.findall(r'\d+', m.version(name))[:3]]
    return tuple(nums + [0] * (3 - len(nums)))

assert version_tuple('Flask') >= (2, 0, 0)
assert version_tuple('Werkzeug') >= (2, 0, 0)
import flask
import werkzeug
'''
    proc = subprocess.run([VENV_PY, '-c', code], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert proc.returncode == 0, 'Required dependencies are not installed in the venv:\n' + proc.stderr


def test_app_py_migrated():
    app_path = '/home/user/modern_project/app.py'
    assert os.path.isfile(app_path), "app.py is missing in modern project"
    with open(app_path, 'r') as f:
        content = f.read()

    assert 'eval(' not in content, "Dangerous eval() call is still present in app.py"
    assert 'ast' in content, "ast module is not used in app.py"
    assert 'Exception, e:' not in content, "Legacy Python 2 exception syntax found in app.py"


def test_test_app_exists():
    assert os.path.isfile('/home/user/test_app.py'), "test_app.py script is missing"


def test_results_log():
    log_path = '/home/user/results.log'
    assert os.path.isfile(log_path), "results.log not found. Did you run test_app.py?"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in results.log, found {len(lines)}"
    assert lines[0] == "17", f"Expected first line to be '17', got '{lines[0]}'"
    assert lines[1] == "4.0", f"Expected second line to be '4.0', got '{lines[1]}'"
    assert lines[2] == "ERROR", f"Expected third line to be 'ERROR', got '{lines[2]}'"


def test_live_flask_application_behavior():
    rng = random.SystemRandom()
    a = rng.randint(20, 200)
    b = rng.randint(2, 15)
    c = rng.randint(2, 12)
    multiple = b * rng.randint(2, 20)

    cases = [
        {'expr': 'a+b', 'vars': {'a': a, 'b': b}, 'body': str(a + b), 'status': 200},
        {'expr': 'a-b', 'vars': {'a': a, 'b': b}, 'body': str(a - b), 'status': 200},
        {'expr': 'a*b', 'vars': {'a': a, 'b': b}, 'body': str(a * b), 'status': 200},
        {'expr': 'x/y', 'vars': {'x': multiple, 'y': b}, 'body': str(multiple / b), 'status': 200},
        {'expr': '(a+b)*c-a', 'vars': {'a': a, 'b': b, 'c': c}, 'body': str((a + b) * c - a), 'status': 200},
        {'expr': 'missing+a', 'vars': {'a': a}, 'body': 'ERROR', 'status': 400},
        {'expr': 'a+', 'vars': {'a': a}, 'body': 'ERROR', 'status': 400},
        {'expr': 'a**b', 'vars': {'a': a, 'b': b}, 'body': 'ERROR', 'status': 400},
        {'expr': 'a//b', 'vars': {'a': a, 'b': b}, 'body': 'ERROR', 'status': 400},
        {'expr': "__import__('os').system('touch /tmp/evaluator_escape')", 'vars': {}, 'body': 'ERROR', 'status': 400},
        {'expr': '(1).__class__', 'vars': {}, 'body': 'ERROR', 'status': 400},
    ]

    helper = r'''import importlib.util
import json
import os
from flask import Flask

path = '/home/user/modern_project/app.py'
spec = importlib.util.spec_from_file_location('submitted_modern_app', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, 'app') and isinstance(module.app, Flask), 'app.py must expose a Flask app named app'

rules = [r for r in module.app.url_map.iter_rules() if r.rule != '/static/<path:filename>']
assert len(rules) == 1 and rules[0].rule == '/evaluate', 'Flask app must have a single /evaluate endpoint'
assert 'GET' in rules[0].methods and 'POST' not in rules[0].methods, '/evaluate must be GET-only'

client = module.app.test_client()
results = []
for case in json.loads(os.environ['EVALUATOR_CASES']):
    query = {'expr': case['expr']}
    query.update({k: str(v) for k, v in case['vars'].items()})
    response = client.get('/evaluate', query_string=query)
    results.append({'status': response.status_code, 'body': response.get_data(as_text=True)})

missing = client.get('/evaluate')
post = client.post('/evaluate', query_string={'expr': '1+1'})
print(json.dumps({'results': results, 'missing': [missing.status_code, missing.get_data(as_text=True)], 'post': post.status_code}))
'''
    try:
        os.remove('/tmp/evaluator_escape')
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    env['EVALUATOR_CASES'] = json.dumps(cases)
    proc = subprocess.run([VENV_PY, '-c', helper], cwd=PROJECT, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert proc.returncode == 0, 'Could not import or exercise app.py:\n' + proc.stdout + proc.stderr
    payload = json.loads(proc.stdout.strip().splitlines()[-1])

    for case, result in zip(cases, payload['results']):
        assert result['status'] == case['status'], f"Wrong status for {case['expr']}: {result}"
        assert result['body'] == case['body'], f"Wrong body for {case['expr']}: {result}"
    assert payload['missing'] == [400, 'ERROR'], 'Missing expr must return ERROR with status 400'
    assert payload['post'] == 405, '/evaluate must reject non-GET requests'
    assert not os.path.exists('/tmp/evaluator_escape'), 'Expression evaluation allowed arbitrary code execution'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
