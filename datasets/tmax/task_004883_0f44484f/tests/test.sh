#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import socket
import string
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import bcrypt


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


NO_REDIRECT = urllib.request.build_opener(NoRedirectHandler)
ALPHANUM = string.ascii_letters + string.digits


def token(n=18):
    return ''.join(secrets.choice(ALPHANUM) for _ in range(n))


def request_status(url, timeout=4):
    try:
        response = NO_REDIRECT.open(urllib.request.Request(url), timeout=timeout)
        try:
            return response.status, dict(response.headers), response.read()
        finally:
            response.close()
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read()


def validator_status(payload):
    encoded = urllib.parse.quote(payload, safe='')
    return request_status(f"http://127.0.0.1:8080/validate?next={encoded}")[0]


def nginx_result(payload):
    encoded = urllib.parse.quote(payload, safe='')
    return request_status(f"http://127.0.0.1:8000/login?next={encoded}")


def corpus_payloads(path):
    with open(path, 'r') as handle:
        return [line.strip() for line in handle if line.strip()]


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == '0A':
                        local_port = int(fields[1].rsplit(':', 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_validator(payload, expected=200, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if validator_status(payload) == expected:
                return True
        except Exception:
            pass
        time.sleep(0.15)
    return False


def test_cracked_password():
    cracked_path = '/home/user/cracked_password.txt'
    assert os.path.exists(cracked_path), f'{cracked_path} is missing.'
    with open(cracked_path, 'r') as handle:
        password = handle.read().strip()
    assert password == 'password', 'The cracked password is incorrect.'


def test_auth_config_updated():
    config_path = '/app/auth_config.json'
    assert os.path.exists(config_path), f'{config_path} is missing.'
    with open(config_path, 'r') as handle:
        data = json.load(handle)

    assert 'admin_hash' in data, 'admin_hash key missing in auth_config.json'
    admin_hash = data['admin_hash']

    # Preserve the original assertions.
    assert isinstance(admin_hash, str)
    assert admin_hash.startswith('$2') and len(admin_hash) == 60, \
        'admin_hash does not appear to be a valid bcrypt hash.'
    assert admin_hash != '5f4dcc3b5aa765d61d8327deb882cf99', \
        'admin_hash was not updated from the original MD5 hash.'

    match = re.fullmatch(r'\$2[aby]\$(\d{2})\$[./A-Za-z0-9]{53}', admin_hash)
    assert match, 'admin_hash is not a structurally valid bcrypt hash.'
    assert int(match.group(1)) >= 10, 'bcrypt work factor is too weak.'

    # Validate the bcrypt encoding with the installed implementation without
    # allowing an attacker-selected extreme cost to stall verification.
    probe_hash = admin_hash[:4] + '04' + admin_hash[6:]
    try:
        bcrypt.checkpw(b'verifier-format-probe', probe_hash.encode('ascii'))
    except (ValueError, TypeError) as exc:
        raise AssertionError(f'admin_hash is rejected by bcrypt: {exc}')

    # The replacement must not merely bcrypt the compromised old password.
    if int(match.group(1)) <= 15:
        assert not bcrypt.checkpw(b'password', admin_hash.encode('ascii')), \
            'admin_hash still authenticates the compromised password.'

    # If a plaintext is voluntarily retained in the configuration, enforce the
    # stated policy and consistency as well.
    if 'admin_password' in data:
        new_password = data['admin_password']
        assert isinstance(new_password, str)
        assert len(new_password) >= 16 and new_password.isalnum(), \
            'The configured new password is not at least 16 alphanumeric characters.'
        assert bcrypt.checkpw(new_password.encode(), admin_hash.encode()), \
            'admin_password does not match admin_hash.'


def test_artifacts_and_services_are_real():
    validator_path = '/home/user/validator.py'
    assert os.path.isfile(validator_path), f'{validator_path} is missing or not a regular file.'
    with open(validator_path, 'rb') as handle:
        assert handle.read(2), 'validator.py is empty.'

    pids = listener_pids(8080)
    assert pids, 'No service is listening on validator port 8080.'
    command_lines = []
    for pid in pids:
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as handle:
                command_lines.append(handle.read().replace(b'\0', b' ').decode(errors='replace'))
        except OSError:
            pass
    assert any('validator.py' in command for command in command_lines), \
        'Port 8080 is not being served by validator.py.'

    nginx_check = subprocess.run(
        ['nginx', '-t', '-c', '/app/nginx.conf'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert nginx_check.returncode == 0, f'/app/nginx.conf is invalid: {nginx_check.stdout}'

    status, _, body = request_status('http://127.0.0.1:5000/login')
    assert status == 200 and b'Login Page' in body, 'Flask is not operating on port 5000.'


def test_redis_operation():
    key = f'verifier:{token(20)}'
    value = token(30)
    with socket.create_connection(('127.0.0.1', 6379), timeout=4) as connection:
        stream = connection.makefile('rb')

        def command(*parts):
            request = f'*{len(parts)}\r\n'.encode()
            for part in parts:
                raw = part.encode()
                request += f'${len(raw)}\r\n'.encode() + raw + b'\r\n'
            connection.sendall(request)
            first = stream.readline()
            assert first, 'Redis closed the connection.'
            if first.startswith(b'+'):
                return first[1:-2]
            if first.startswith(b':'):
                return int(first[1:-2])
            if first.startswith(b'$'):
                length = int(first[1:-2])
                if length == -1:
                    return None
                data = stream.read(length)
                assert stream.read(2) == b'\r\n'
                return data
            raise AssertionError(f'Unexpected Redis response: {first!r}')

        assert command('PING') == b'PONG'
        assert command('SET', key, value) == b'OK'
        assert command('GET', key) == value.encode()
        assert command('DEL', key) == 1


def test_validator_direct_corpus():
    clean_payloads = corpus_payloads('/app/corpus/clean/safe.txt')
    evil_payloads = corpus_payloads('/app/corpus/evil/payloads.txt')

    clean_failures = [payload for payload in clean_payloads if validator_status(payload) != 200]
    evil_failures = [payload for payload in evil_payloads if validator_status(payload) != 403]

    error_msgs = []
    if evil_failures:
        error_msgs.append(f'{len(evil_failures)} of {len(evil_payloads)} evil bypassed direct validator: {evil_failures}')
    if clean_failures:
        error_msgs.append(f'{len(clean_failures)} of {len(clean_payloads)} clean modified/rejected by direct validator: {clean_failures}')
    assert not error_msgs, ' | '.join(error_msgs)


def test_validator_randomized_policy():
    safe = ['/']
    for _ in range(12):
        safe.append('/' + '/'.join(token(secrets.choice(range(6, 17))) for _ in range(secrets.choice(range(1, 4)))))

    hosts = [f'{token(12)}.example', f'{token(10)}.invalid']
    evil = [
        f'http://{hosts[0]}/{token()}',
        f'https://{hosts[1]}/{token()}',
        f'HTTP://{hosts[0]}/{token()}',
        f'//{hosts[1]}/{token()}',
        f'javascript:alert({token(8)})',
        f'JaVaScRiPt:alert({token(8)})',
        f'data:text/html,{token()}',
        f'ftp://{hosts[0]}/{token()}',
    ]

    assert all(validator_status(payload) == 200 for payload in safe), \
        'Validator rejected a generated safe local path.'
    assert all(validator_status(payload) == 403 for payload in evil), \
        'Validator accepted a generated absolute or dangerous URL.'


def test_nginx_integration_corpus():
    clean_payloads = corpus_payloads('/app/corpus/clean/safe.txt')
    evil_payloads = corpus_payloads('/app/corpus/evil/payloads.txt')

    clean_failures = []
    for payload in clean_payloads:
        status, _, _ = nginx_result(payload)
        if status not in (200, 302):
            clean_failures.append(payload)

    evil_failures = []
    for payload in evil_payloads:
        status, _, _ = nginx_result(payload)
        if status != 403:
            evil_failures.append(payload)

    error_msgs = []
    if evil_failures:
        error_msgs.append(f'{len(evil_failures)} of {len(evil_payloads)} evil bypassed NGINX integration: {evil_failures}')
    if clean_failures:
        error_msgs.append(f'{len(clean_failures)} of {len(clean_payloads)} clean modified/rejected by NGINX integration: {clean_failures}')
    assert not error_msgs, ' | '.join(error_msgs)


def test_nginx_randomized_integration():
    safe = ['/' + token(14) + '/' + token(11) for _ in range(8)]
    evil = []
    for _ in range(6):
        host = token(14) + '.invalid'
        evil.extend((f'https://{host}/{token(9)}', f'//{host}/{token(9)}'))
    evil.extend((f'javascript:alert({token(9)})', f'data:text/plain,{token(15)}'))

    for payload in safe:
        status, headers, _ = nginx_result(payload)
        assert status in (200, 302), f'NGINX rejected generated safe path {payload!r} with {status}.'
        if status == 302:
            assert headers.get('Location') == payload, 'A safe redirect was modified before reaching Flask.'

    for payload in evil:
        status, _, _ = nginx_result(payload)
        assert status == 403, f'NGINX allowed generated malicious redirect {payload!r} with {status}.'


def test_nginx_actually_depends_on_validator_and_restart_artifact():
    probe = '/' + token(24)
    assert validator_status(probe) == 200
    assert nginx_result(probe)[0] in (200, 302)

    pids = listener_pids(8080)
    assert pids, 'Validator listener disappeared before dependency test.'
    for pid in pids:
        os.kill(pid, 15)

    deadline = time.time() + 5
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.1)
    for pid in listener_pids(8080):
        os.kill(pid, 9)
    time.sleep(0.2)

    restarted = None
    try:
        outage_probe = '/' + token(25)
        outage_status, _, _ = nginx_result(outage_probe)
        assert outage_status not in (200, 302), \
            'NGINX still allowed a login request while the validator was unavailable.'
    finally:
        restarted = subprocess.Popen(
            ['python3', '/home/user/validator.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        recovery_probe = '/' + token(26)
        assert wait_for_validator(recovery_probe), 'validator.py could not be executed after restart.'

    deadline = time.time() + 5
    while time.time() < deadline:
        if nginx_result(recovery_probe)[0] in (200, 302):
            break
        time.sleep(0.15)
    else:
        raise AssertionError('NGINX did not recover after validator.py restarted.')

    assert restarted is not None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
