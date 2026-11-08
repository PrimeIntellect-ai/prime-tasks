#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
import pytest


def load_sanitizer():
    sys.path.insert(0, '/home/user/app/gateway')
    try:
        from sanitizer import is_safe_payload
        return is_safe_payload
    except ImportError:
        pytest.fail('Could not import is_safe_payload from /home/user/app/gateway/sanitizer.py')


def post_json(url, payload, expected_status=200):
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode('utf-8')
            assert response.status == expected_status, f'Expected status {expected_status}, got {response.status}'
            return response, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        if e.code == expected_status:
            return e, None
        pytest.fail(f'Expected HTTP {expected_status}, got {e.code}: {e.reason}')
    except Exception as e:
        pytest.fail(f'HTTP request to {url} failed: {e}')


def result_from(body):
    assert isinstance(body, dict), f'Expected JSON object, got {body!r}'
    assert 'result' in body, "Response missing 'result' key"
    return float(body['result'])


def socket_owners(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as fp:
                next(fp)
                for line in fp:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    owners = []
    for proc in glob.glob('/proc/[0-9]*'):
        pid = os.path.basename(proc)
        try:
            cmdline = open(f'{proc}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
            cwd = os.readlink(f'{proc}/cwd')
            environ = open(f'{proc}/environ', 'rb').read().replace(b'\0', b'\n').decode(errors='replace')
            for fd in glob.glob(f'{proc}/fd/*'):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    owners.append((int(pid), cmdline, cwd, environ))
                    break
        except (OSError, ProcessLookupError):
            continue
    return owners


def test_sanitizer_corpus():
    is_safe_payload = load_sanitizer()
    clean_dir = '/home/user/app/corpora/clean'
    evil_dir = '/home/user/app/corpora/evil'
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    if not clean_files:
        pytest.fail(f'No clean files found in {clean_dir}')
    if not evil_files:
        pytest.fail(f'No evil files found in {evil_dir}')

    modified_clean = []
    for f in clean_files:
        with open(os.path.join(clean_dir, f)) as fp:
            content = fp.read()
        try:
            if not is_safe_payload(content):
                modified_clean.append(f)
        except Exception:
            modified_clean.append(f)

    bypassed_evil = []
    for f in evil_files:
        with open(os.path.join(evil_dir, f)) as fp:
            content = fp.read()
        try:
            if is_safe_payload(content):
                bypassed_evil.append(f)
        except Exception:
            pass

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")
    if errors:
        pytest.fail(' | '.join(errors))


def test_sanitizer_generated_inputs():
    is_safe_payload = load_sanitizer()
    rng = random.Random(secrets.randbits(64))

    for _ in range(12):
        rows, cols = rng.randint(1, 100), rng.randint(1, 100)
        payload = {
            'type': 'polynomial',
            'coefficients': [rng.uniform(-20, 20) for _ in range(rng.randint(1, 8))],
            'depth': rng.randint(1, 10),
            'metadata_' + secrets.token_hex(4): {'type': 'matrix', 'dims': [rows, cols]},
        }
        assert is_safe_payload(json.dumps(payload)) is True, f'Valid generated AST was rejected: {payload}'

    for _ in range(8):
        payload = {
            'type': 'polynomial',
            'coefficients': [rng.uniform(-5, 5)],
            'depth': rng.randint(11, 40),
            'nonce': secrets.token_hex(8),
        }
        assert is_safe_payload(json.dumps(payload)) is False, f'Excessive declared depth was accepted: {payload}'

    for _ in range(8):
        dims = [rng.randint(101, 250), rng.randint(1, 100)]
        if rng.choice([True, False]):
            dims.reverse()
        payload = {
            'type': 'polynomial',
            'depth': rng.randint(1, 8),
            'coefficients': [1.0],
            'child': {'type': 'matrix', 'dims': dims, 'nonce': secrets.token_hex(5)},
        }
        assert is_safe_payload(json.dumps(payload)) is False, f'Oversized matrix was accepted: {payload}'

    nested = {'type': 'polynomial', 'coefficients': [1.0]}
    cursor = nested
    for i in range(14):
        cursor['child'] = {'type': 'expression', 'tag': secrets.token_hex(3)}
        cursor = cursor['child']
    assert is_safe_payload(json.dumps(nested)) is False, 'Structurally deep AST was accepted'

    for malformed in ('not json', '{"type":', 'null', '42', '[]'):
        try:
            accepted = is_safe_payload(malformed)
        except Exception as e:
            pytest.fail(f'Sanitizer raised instead of returning False for invalid payload {malformed!r}: {e}')
        assert accepted is False, f'Invalid/non-AST JSON was accepted: {malformed!r}'


def test_service_configuration_and_process_split():
    for path in ('/home/user/app/compute/engine.py', '/home/user/app/gateway/app.py',
                 '/home/user/app/gateway/sanitizer.py', '/home/user/app/compute/libpoly.so',
                 '/home/user/app/start_services.sh', '/etc/nginx/sites-available/math-app'):
        assert os.path.isfile(path), f'Missing required artifact: {path}'

    assert os.path.exists('/etc/nginx/sites-enabled/math-app'), 'The math-app Nginx site is not enabled'
    rendered = subprocess.run(['nginx', '-T'], text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=5)
    assert rendered.returncode == 0, rendered.stdout
    conf = rendered.stdout
    assert re.search(r'\blisten\s+(?:127\.0\.0\.1:)?8080\b', conf), 'Nginx does not listen on port 8080'
    assert re.search(r'\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;', conf), 'Nginx does not proxy to the gateway on 5000'

    start = open('/home/user/app/start_services.sh').read()
    assert 'ENGINE_URL' in start and 'http://127.0.0.1:5001' in start, 'start_services.sh does not configure ENGINE_URL'
    assert 'engine.py' in start and ('gateway/app.py' in start or 'app.py' in start), 'start_services.sh does not start both Python services'
    assert os.access('/home/user/app/start_services.sh', os.X_OK), 'start_services.sh is not executable'

    engine_src = open('/home/user/app/compute/engine.py').read()
    for token in ('ctypes', 'libpoly.so', 'evaluate_polynomial', 'argtypes', 'restype'):
        assert token in engine_src, f'Compute engine is missing required ctypes binding element: {token}'
    assert re.search(r'evaluate_polynomial\s*\(', engine_src), 'Compute engine never calls evaluate_polynomial'

    gateway_src = open('/home/user/app/gateway/app.py').read()
    assert 'ENGINE_URL' in gateway_src and '/compute' in gateway_src, 'Gateway does not use ENGINE_URL to address /compute'
    assert ('requests' in gateway_src or 'urllib' in gateway_src), 'Gateway does not contain an HTTP client for forwarding to the engine'
    assert 'is_safe_payload' in gateway_src, 'Gateway does not invoke the sanitizer'

    p8080, p5000, p5001 = socket_owners(8080), socket_owners(5000), socket_owners(5001)
    assert p8080, 'Nothing is listening on port 8080'
    assert p5000, 'Nothing is listening on gateway port 5000'
    assert p5001, 'Nothing is listening on engine port 5001'
    assert any('nginx' in cmd.lower() for _, cmd, _, _ in p8080), f'Port 8080 is not owned by Nginx: {p8080}'
    assert any('python' in cmd.lower() and ('gateway' in (cmd + cwd).lower() or 'flask' in cmd.lower()) for _, cmd, cwd, _ in p5000), f'Port 5000 is not a Python gateway process: {p5000}'
    assert any('python' in cmd.lower() and ('compute' in (cmd + cwd).lower() or 'engine.py' in cmd.lower()) for _, cmd, cwd, _ in p5001), f'Port 5001 is not a Python compute process: {p5001}'
    assert {p[0] for p in p5000}.isdisjoint({p[0] for p in p5001}), 'Gateway and compute engine are not separate processes'
    assert any('ENGINE_URL=http://127.0.0.1:5001' in env for _, _, _, env in p5000), 'Running gateway lacks the required ENGINE_URL'


def test_compute_engine_and_full_pipeline_varied_inputs():
    rng = random.Random(secrets.randbits(64))
    for _ in range(6):
        coefficients = [rng.uniform(-8, 8) for _ in range(rng.randint(1, 7))]
        x = rng.uniform(-2.5, 2.5)
        expected = sum(c * (x ** i) for i, c in enumerate(coefficients))

        _, engine_body = post_json('http://127.0.0.1:5001/compute', {'coefficients': coefficients, 'x': x})
        assert math.isclose(result_from(engine_body), expected, rel_tol=1e-8, abs_tol=1e-7)

        payload = {
            'type': 'polynomial',
            'coefficients': coefficients,
            'depth': rng.randint(1, 6),
            'nonce': secrets.token_hex(7),
        }
        poly_id = 'poly-' + secrets.token_hex(5)
        query = f'/api/v1/evaluate/{poly_id}?x={x!r}'
        _, gateway_body = post_json('http://127.0.0.1:5000' + query, payload)
        assert math.isclose(result_from(gateway_body), expected, rel_tol=1e-8, abs_tol=1e-7)

        nginx_response, proxy_body = post_json('http://127.0.0.1:8080' + query, payload)
        assert math.isclose(result_from(proxy_body), expected, rel_tol=1e-8, abs_tol=1e-7)
        assert 'nginx' in (nginx_response.headers.get('Server') or '').lower(), 'Port 8080 response was not served through Nginx'

    bad = {'type': 'polynomial', 'coefficients': [2.0], 'depth': 2,
           'child': {'type': 'matrix', 'dims': [100, 101], 'nonce': secrets.token_hex(8)}}
    post_json('http://127.0.0.1:5000/api/v1/evaluate/bad?x=1.25', bad, 400)
    post_json('http://127.0.0.1:8080/api/v1/evaluate/bad?x=1.25', bad, 400)


def test_e2e_clean_payload():
    url = 'http://127.0.0.1:8080/api/v1/evaluate/test?x=2.0'
    payload = {'type': 'polynomial', 'coefficients': [1.0, 2.0, 3.0], 'depth': 1}
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f'Expected status 200, got {response.status}'
            resp_json = json.loads(response.read().decode('utf-8'))
            assert 'result' in resp_json, "Response missing 'result' key"
            assert abs(resp_json['result'] - 17.0) < 1e-6, f"Expected result 17.0, got {resp_json['result']}"
    except urllib.error.HTTPError as e:
        pytest.fail(f'HTTPError on clean payload: {e.code} {e.reason}')
    except Exception as e:
        pytest.fail(f'Exception during clean payload E2E test: {e}')


def test_e2e_evil_payload():
    url = 'http://127.0.0.1:8080/api/v1/evaluate/test?x=2.0'
    payload = {'type': 'polynomial', 'coefficients': [1.0], 'depth': 11}
    curr = payload
    for _ in range(15):
        curr['child'] = {}
        curr = curr['child']
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            pytest.fail(f'Expected 400 Bad Request for evil payload, got {response.status}')
    except urllib.error.HTTPError as e:
        assert e.code == 400, f'Expected 400 Bad Request, got {e.code}'
    except Exception as e:
        pytest.fail(f'Exception during evil payload E2E test: {e}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
