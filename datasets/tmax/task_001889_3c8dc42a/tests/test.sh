#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import json
import os
import re
import subprocess
import time
from pathlib import Path

import psutil
import requests

APP = Path('/home/user/app')


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def executable_name(pid):
    try:
        return os.path.basename(os.readlink(f'/proc/{pid}/exe'))
    except OSError:
        return ''


def expected_encoding(text):
    return ''.join(chr(ord(char) + 1) for char in text)


def test_load_test_metrics():
    load_test_script = '/home/user/app/load_test.py'
    assert os.path.exists(load_test_script), f'Load test script missing: {load_test_script}'

    try:
        output = subprocess.check_output(
            ['python3', load_test_script], stderr=subprocess.STDOUT, timeout=90
        ).decode('utf-8')
    except subprocess.CalledProcessError as e:
        assert False, f'Load test script failed to execute. Output:\n{e.output.decode("utf-8", errors="replace")}'

    start_idx = output.find('{')
    end_idx = output.rfind('}') + 1
    assert start_idx != -1 and end_idx != 0, 'No JSON object found in load test output.'
    try:
        data = json.loads(output[start_idx:end_idx])
    except json.JSONDecodeError as e:
        assert False, f'Failed to parse JSON from load test output. Output was:\n{output}\nError: {e}'

    assert 'requests_per_second' in data, "JSON output missing 'requests_per_second' key."
    assert 'memory_growth_mb' in data, "JSON output missing 'memory_growth_mb' key."
    assert data['requests_per_second'] >= 500.0, f"Throughput too low: {data['requests_per_second']} req/s (expected >= 500.0 req/s)"
    assert data['memory_growth_mb'] < 5.0, f"Memory growth too high: {data['memory_growth_mb']} MB (expected < 5.0 MB)"


def test_nginx_config_proxy_pass():
    nginx_conf_path = '/home/user/app/nginx.conf'
    assert os.path.exists(nginx_conf_path), f'Nginx configuration missing: {nginx_conf_path}'
    content = Path(nginx_conf_path).read_text()
    has_proxy_pass = 'proxy_pass http://127.0.0.1:5000' in content or 'proxy_pass http://localhost:5000' in content
    assert has_proxy_pass, "Nginx configuration is missing the 'proxy_pass' directive to http://127.0.0.1:5000"


def test_api_tests_pass():
    test_file = '/home/user/app/tests/test_api.py'
    assert os.path.exists(test_file), f'Test API file missing: {test_file}'
    try:
        subprocess.check_output(['pytest', test_file], stderr=subprocess.STDOUT, timeout=60)
    except subprocess.CalledProcessError as e:
        assert False, f'Tests in {test_file} failed. Output:\n{e.output.decode("utf-8", errors="replace")}'


def test_c_source_and_compiled_extension_are_real():
    source = APP / 'src/fast_encode.c'
    assert source.is_file(), 'fast_encode.c is missing'
    text = source.read_text()

    # Reject the concrete allocation defects in the supplied implementation.
    if re.search(r'\bmalloc\s*\(', text):
        assert re.search(r'\bfree\s*\(', text), 'malloc allocation is still not released'
        assert re.search(r'if\s*\(\s*(?:!\s*copy|copy\s*==\s*NULL|NULL\s*==\s*copy)', text), 'malloc failure is not handled'

    script = r'''
import importlib.machinery, json, os, resource, sys
os.chdir('/home/user/app')
sys.path.insert(0, '/home/user/app')
import fast_encode
assert any(fast_encode.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), fast_encode.__file__
assert fast_encode.process('abcXYZ019') == 'bcdYZ[12:'
assert fast_encode.process('') == ''
payload = 'Abcdefghijklmnop' * 1024
before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
for _ in range(4000):
    result = fast_encode.process(payload)
    if len(result) != len(payload) or result[:4] != 'Bcde':
        raise AssertionError('incorrect extension result')
after = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
print(json.dumps({'module': fast_encode.__file__, 'growth_kb': after - before}))
'''
    output = subprocess.check_output(['python3', '-c', script], cwd='/tmp', stderr=subprocess.STDOUT, timeout=60).decode()
    data = json.loads(output.strip().splitlines()[-1])
    module = Path(data['module'])
    assert module.is_file(), 'compiled extension artifact is missing'
    assert module.stat().st_mtime >= source.stat().st_mtime, 'compiled extension is older than fast_encode.c; recompile it'
    assert data['growth_kb'] < 12 * 1024, f"C extension retained excessive memory: {data['growth_kb'] / 1024:.2f} MB"


def test_fixture_actually_uses_unittest_mock():
    test_file = APP / 'tests/test_api.py'
    tree = ast.parse(test_file.read_text(), filename=str(test_file))

    imports_mock = False
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module in ('unittest', 'unittest.mock'):
            if node.module == 'unittest.mock' or any(alias.name == 'mock' for alias in node.names):
                imports_mock = True
        if isinstance(node, ast.Import) and any(alias.name == 'unittest.mock' for alias in node.names):
            imports_mock = True

    mock_names = {'patch', 'Mock', 'MagicMock', 'mock_open', 'create_autospec'}
    uses_mock = False
    has_assertion = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in mock_names:
                uses_mock = True
            elif isinstance(func, ast.Attribute) and func.attr in mock_names:
                uses_mock = True
            if isinstance(func, ast.Attribute) and func.attr.startswith('assert'):
                has_assertion = True
            elif isinstance(func, ast.Name) and func.id == 'assert':
                has_assertion = True
        elif isinstance(node, ast.Assert):
            has_assertion = True

    assert imports_mock, 'tests/test_api.py must import unittest.mock'
    assert uses_mock, 'tests/test_api.py does not construct or apply a unittest.mock mock/patch'
    assert has_assertion, 'tests/test_api.py contains no substantive assertion'


def test_real_services_and_proxy_behavior():
    subprocess.check_output(
        ['nginx', '-t', '-c', '/home/user/app/nginx.conf'],
        stderr=subprocess.STDOUT,
        timeout=10,
    )

    flask_pids = listener_pids(5000)
    assert flask_pids, 'no persistent service is listening on Flask port 5000'
    assert any('app.py' in cmdline(pid) and executable_name(pid).startswith('python') for pid in flask_pids), \
        'port 5000 is not served by the Python app.py process'

    nginx_pids = listener_pids(8080)
    assert nginx_pids, 'no persistent service is listening on Nginx port 8080'
    assert any('nginx' in executable_name(pid) or 'nginx' in cmdline(pid) for pid in nginx_pids), \
        'port 8080 is not owned by Nginx'

    cases = ['abc', 'ProxyTest018', 'helloWorld7', 'ZYX987']
    for text in cases:
        response = requests.get('http://127.0.0.1:8080/encode', params={'text': text}, timeout=2)
        assert response.status_code == 200
        assert response.headers.get('Server', '').lower().startswith('nginx'), 'response did not traverse Nginx'
        assert response.json() == {'result': expected_encoding(text)}


def test_independent_10000_request_load_and_memory():
    flask_candidates = [
        pid for pid in listener_pids(5000)
        if 'app.py' in cmdline(pid) and executable_name(pid).startswith('python')
    ]
    assert flask_candidates, 'Flask app.py service stopped before load testing'
    process = psutil.Process(flask_candidates[0])

    start_mem = process.memory_info().rss
    request_seconds = 0.0
    for i in range(10000):
        text = f'loadTest{i % 1000:03d}'
        started = time.perf_counter()
        response = requests.get('http://127.0.0.1:8080/encode', params={'text': text}, timeout=2)
        request_seconds += time.perf_counter() - started
        assert response.status_code == 200, f'request {i} returned HTTP {response.status_code}'
        assert response.json() == {'result': expected_encoding(text)}, f'incorrect response for request {i}'

    end_mem = process.memory_info().rss
    throughput = 10000 / request_seconds if request_seconds else 0.0
    growth_mb = (end_mem - start_mem) / (1024 * 1024)
    assert throughput >= 500.0, f'Independently measured throughput too low: {throughput:.2f} req/s'
    assert growth_mb < 5.0, f'Independently measured Flask memory growth too high: {growth_mb:.2f} MB'

    assert listener_pids(5000), 'Flask service did not remain running after load'
    assert listener_pids(8080), 'Nginx service did not remain running after load'
TEST_EOF

if cd /tmp && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
