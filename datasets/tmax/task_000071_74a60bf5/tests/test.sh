#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest
import requests


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_build_script_and_artifacts():
    script = Path('/app/build_system.py')
    assert script.is_file(), 'Missing /app/build_system.py'
    for artifact in ('/app/bin/engine_cpp', '/app/bin/engine_go'):
        try:
            os.remove(artifact)
        except FileNotFoundError:
            pass

    result = subprocess.run([sys.executable, str(script)], cwd='/app', text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    assert result.returncode == 0, f'build_system.py failed:\n{result.stdout}'
    for artifact in ('/app/bin/engine_cpp', '/app/bin/engine_go'):
        assert os.path.isfile(artifact), f'Build artifact missing: {artifact}'
        assert os.access(artifact, os.X_OK), f'Build artifact is not executable: {artifact}'


def test_nginx_config():
    conf = Path('/app/nginx/nginx.conf')
    assert conf.is_file(), 'Nginx configuration missing'
    content = conf.read_text()
    assert '8080' in content, 'Nginx config does not seem to listen on port 8080'
    check = subprocess.run(['nginx', '-t', '-c', str(conf), '-p', '/app/nginx/'],
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert check.returncode == 0, check.stdout
    assert re.search(r'listen\s+[^;]*8080\s*;', content), 'Must listen on port 8080'
    assert re.search(r'location\s+(?:\^~\s+)?/api/math/\s*\{[^}]*proxy_pass\s+http://127\.0\.0\.1:8000/evaluate',
                     content, re.S), 'Missing /api/math/ proxy to Flask /evaluate'


def test_sanitizer_corpora_and_general_cases():
    sanitizer = load_module('submission_sanitizer', '/app/src/python/sanitizer.py')
    fn = getattr(sanitizer, 'is_safe_math', None)
    assert callable(fn), 'is_safe_math is missing'

    clean = [line.strip() for line in Path('/app/corpora/clean.txt').read_text().splitlines() if line.strip()]
    evil = [line.strip() for line in Path('/app/corpora/evil.txt').read_text().splitlines() if line.strip()]
    for expr in clean:
        assert fn(expr) is True, f'Clean corpus expression rejected: {expr!r}'
    for expr in evil:
        try:
            accepted = fn(expr)
        except Exception:
            accepted = False
        assert accepted is not True, f'Evil corpus expression accepted: {expr!r}'

    # Additional cases are deliberately independent of the shipped fixed corpora.
    safe = [
        '42', '-7.5 + 2', '((x + y) ** 2) / 4', 'pi*2 + e',
        'x^2 + y^2', '0.001 * (123 - 4)', '1 + +2', 'e',
    ]
    unsafe = [
        '', 'z + 1', 'pie + 1', 'exp(1)', 'x.__class__', '[x for x in y]',
        '{1:2}', '1;2', '1 and 2', 'not 1', 'True + 1', '0x10 + 1',
        '1e3', 'x = 2', 'abs(-1)', '().__class__', '2 // 1', '2 % 1',
        '2 @ 1', '2 << 1', '2 < 3', '"x"', '1\n+2',
        '__builtins__', 'globals()', 'getattr(x,"y")',
        '9' * 10001,
    ]
    for expr in safe:
        assert fn(expr) is True, f'Valid math expression rejected: {expr!r}'
    for expr in unsafe:
        try:
            accepted = fn(expr)
        except Exception:
            accepted = False
        assert accepted is not True, f'Unsafe/out-of-grammar expression accepted: {expr[:80]!r}'


def test_flask_routing_local_evaluation_and_proxying(monkeypatch):
    # Ensure app imports the submitted sanitizer, not a stale module.
    sys.path.insert(0, '/app/src/python')
    sys.modules.pop('sanitizer', None)
    appmod = load_module('submission_app', '/app/src/python/app.py')

    calls = []
    class FakeResponse:
        def __init__(self, text):
            self.text = text
            self.content = text.encode()
            self.status_code = 200
            self.headers = {'Content-Type': 'text/plain'}
    def fake_get(url, *args, **kwargs):
        calls.append((url, kwargs))
        return FakeResponse('BACKEND:' + url)
    monkeypatch.setattr(appmod.requests, 'get', fake_get)

    client = appmod.app.test_client()
    r = client.get('/evaluate', query_string={'expr': '2 + 3 * 4'})
    assert r.status_code == 200
    assert r.get_data(as_text=True).strip() in {'14', '14.0'}
    assert not calls, 'Numeric expression must be evaluated locally'

    r = client.get('/evaluate', query_string={'expr': 'x + pi'})
    assert r.status_code == 200
    assert calls and calls[-1][0].startswith('http://127.0.0.1:8082/eval'), 'x/y must route to C++'
    assert 'x' in calls[-1][0] or calls[-1][1].get('params', {}).get('expr') == 'x + pi'

    r = client.get('/evaluate', query_string={'expr': 'pi + e'})
    assert r.status_code == 200
    assert calls[-1][0].startswith('http://127.0.0.1:8081/eval'), 'pi/e must route to Go'

    before = len(calls)
    r = client.get('/evaluate', query_string={'expr': '__import__("os")'})
    assert r.status_code == 403
    assert len(calls) == before, 'Rejected expressions must not be proxied'


def wait_http(url, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=.5)
        except requests.RequestException:
            time.sleep(.1)
    raise AssertionError(f'Service did not start: {url}')


def test_compiled_backends_run_and_serve():
    procs = []
    try:
        for binary, port, marker in [('/app/bin/engine_go', 8081, 'Go:'),
                                     ('/app/bin/engine_cpp', 8082, 'C++:')]:
            p = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            procs.append(p)
            response = wait_http(f'http://127.0.0.1:{port}/eval?expr=7%2B8')
            assert response.status_code == 200
            assert marker in response.text and '7+8' in response.text
    finally:
        for p in procs:
            p.terminate()
        for p in procs:
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
