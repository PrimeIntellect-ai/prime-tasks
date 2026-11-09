#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.util
import json
import os
import random
import re
import secrets
import signal
import socket
import ssl
import string
import subprocess
import sys
import tempfile
import time

import pytest

WAF_PATH = "/home/user/waf_filter.py"
START_PATH = "/home/user/start_services.sh"
DAEMON_PATH = "/app/legacy_auth_daemon"
IMAGE_PATH = "/app/backend_vm.qcow2"


def _processes():
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                argv = [x.decode('utf-8', 'replace') for x in f.read().split(b'\0') if x]
            exe = os.path.realpath(f'/proc/{entry}/exe')
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        yield int(entry), exe, argv


def _qemu_processes():
    matches = []
    forward_re = re.compile(r'(?:hostfwd=tcp:[^,\s]*:8080-[^,\s]*:80(?:,|$)|tcp:8080::80(?:,|$))')
    for pid, exe, argv in _processes():
        base = os.path.basename(exe).lower()
        if not base.startswith('qemu-system'):
            continue
        joined = ' '.join(argv)
        has_image = any(arg == IMAGE_PATH or IMAGE_PATH in arg for arg in argv)
        has_forward = bool(forward_re.search(joined))
        if has_image and has_forward:
            matches.append((pid, exe, argv))
    return matches


def _listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r', encoding='ascii') as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for pid, _, _ in _processes():
        try:
            for fd in os.listdir(f'/proc/{pid}/fd'):
                try:
                    target = os.readlink(f'/proc/{pid}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(pid)
        except OSError:
            pass
    return pids


def _stop_existing_services():
    pids = {pid for pid, _, _ in _qemu_processes()} | _listener_pids(8443)
    pids.discard(os.getpid())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while pids and time.time() < deadline:
        pids = {pid for pid in pids if os.path.exists(f'/proc/{pid}')}
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def _port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex(('127.0.0.1', port)) == 0


def _load_waf():
    assert os.path.isfile(WAF_PATH), f'WAF script not found at {WAF_PATH}'
    spec = importlib.util.spec_from_file_location('waf_filter', WAF_PATH)
    assert spec is not None and spec.loader is not None, 'Failed to load WAF script specification.'
    module = importlib.util.module_from_spec(spec)
    try:
        sys.path.insert(0, '/home/user')
        spec.loader.exec_module(module)
    except Exception as e:
        pytest.fail(f'Failed to execute/import {WAF_PATH}: {e}')
    finally:
        if '/home/user' in sys.path:
            sys.path.remove('/home/user')
    assert hasattr(module, 'filter_request'), f"Function 'filter_request' not found in {WAF_PATH}"
    assert callable(module.filter_request), 'filter_request is not callable'
    return module


def _daemon_says_safe(payload):
    try:
        result = subprocess.run(
            [DAEMON_PATH, payload],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def test_00_start_services_script_actually_starts_services():
    assert os.path.isfile(START_PATH), f'Start script not found at {START_PATH}'
    assert os.access(START_PATH, os.X_OK), f'Start script is not executable: {START_PATH}'
    syntax = subprocess.run(['/bin/bash', '-n', START_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f'Start script has invalid shell syntax: {syntax.stderr}'

    # Remove pre-existing instances so a no-op script cannot receive credit.
    _stop_existing_services()
    try:
        result = subprocess.run([START_PATH], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        pytest.fail('start_services.sh did not return after starting background services')
    assert result.returncode == 0, (
        f'start_services.sh exited with {result.returncode}:\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if _qemu_processes() and _port_open(8443):
            break
        time.sleep(0.2)
    assert _qemu_processes(), 'start_services.sh did not start the required QEMU process'
    assert _port_open(8443), 'start_services.sh did not start the service on port 8443'


def test_qemu_running_with_port_forwarding():
    """Validates that QEMU is running and forwarding host port 8080 to guest port 80."""
    try:
        result = subprocess.run(['ps', 'aux'], capture_output=True, text=True, check=True)
        processes = result.stdout.lower()
        qemu_running = 'qemu' in processes and 'backend_vm.qcow2' in processes
        assert qemu_running, 'QEMU does not appear to be running with the backend_vm.qcow2 image.'
        port_forwarding_found = '8080' in processes and '80' in processes
        assert port_forwarding_found, 'QEMU is running, but host port 8080 to guest port 80 forwarding was not found in the process arguments.'
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute 'ps aux' to check running processes.")

    matches = _qemu_processes()
    assert matches, 'No qemu-system process has both the required disk image and an exact TCP 8080-to-80 hostfwd argument.'
    valid_qemu = False
    errors = []
    for _, exe, _ in matches:
        try:
            version = subprocess.run([exe, '--version'], capture_output=True, text=True, timeout=3)
            text = (version.stdout + version.stderr).lower()
            if version.returncode == 0 and 'qemu emulator version' in text:
                valid_qemu = True
                break
        except (OSError, subprocess.TimeoutExpired) as e:
            errors.append(str(e))
    assert valid_qemu, f'The matching process executable did not identify itself as QEMU: {errors}'
    assert _port_open(8080), 'QEMU user networking is not actually listening on forwarded host port 8080.'


def test_tls_proxy_listening():
    """Validates that a service is listening on host port 8443 and speaks HTTPS."""
    port = 8443
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        is_listening = s.connect_ex(('127.0.0.1', port)) == 0
    assert is_listening, f'No service is listening on port {port} (expected TLS proxy).'

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(('127.0.0.1', port), timeout=3) as raw:
        with context.wrap_socket(raw, server_hostname='localhost') as tls:
            cert_der = tls.getpeercert(binary_form=True)
            assert cert_der, 'TLS service did not present a certificate.'
            tls.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n')
            response = tls.recv(4096)
            assert response.startswith(b'HTTP/'), 'Port 8443 completed TLS but did not serve an HTTPS response.'

    pem = ssl.DER_cert_to_PEM_cert(cert_der)
    cert_path = None
    try:
        with tempfile.NamedTemporaryFile('w', suffix='.pem', delete=False) as f:
            f.write(pem)
            cert_path = f.name
        decoded = ssl._ssl._test_decode_cert(cert_path)
        assert decoded.get('subject') == decoded.get('issuer'), 'The TLS certificate is not self-signed/self-issued.'
    finally:
        if cert_path:
            os.unlink(cert_path)


def test_waf_filter_adversarial_corpus():
    """Retains validation against the supplied evil and clean corpora."""
    waf_filter = _load_waf()
    evil_corpus_path = '/app/tests/corpus/evil/'
    clean_corpus_path = '/app/tests/corpus/clean/'
    evil_files = glob.glob(os.path.join(evil_corpus_path, '*.json'))
    clean_files = glob.glob(os.path.join(clean_corpus_path, '*.json'))
    assert len(evil_files) > 0, f'No test files found in evil corpus: {evil_corpus_path}'
    assert len(clean_files) > 0, f'No test files found in clean corpus: {clean_corpus_path}'

    evil_bypassed = []
    clean_rejected = []
    for filepath in evil_files:
        with open(filepath, 'r', encoding='utf-8') as f:
            payload = f.read()
        try:
            if waf_filter.filter_request(payload) is not False:
                evil_bypassed.append(os.path.basename(filepath))
        except Exception as e:
            evil_bypassed.append(f'{os.path.basename(filepath)} (Exception: {e})')
    for filepath in clean_files:
        with open(filepath, 'r', encoding='utf-8') as f:
            payload = f.read()
        try:
            if waf_filter.filter_request(payload) is not True:
                clean_rejected.append(os.path.basename(filepath))
        except Exception as e:
            clean_rejected.append(f'{os.path.basename(filepath)} (Exception: {e})')

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if errors:
        pytest.fail('WAF filter failed adversarial testing:\n' + '\n'.join(errors))


def test_waf_filter_runtime_generated_against_daemon():
    """Exercise unpredictable payloads, deriving every expected answer from the daemon."""
    waf_filter = _load_waf()
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '_'

    def word(n):
        return ''.join(secrets.choice(alphabet) for _ in range(n))

    def mixed_case(value):
        return ''.join(ch.upper() if rng.randrange(2) else ch.lower() for ch in value)

    payloads = []
    triggers = ['union', 'select', 'drop', '--']
    for _ in range(35):
        username_len = rng.choice([0, 1, 7, 30, 31, 32, 33, 34, rng.randint(35, 90)])
        username = word(username_len)
        benign_token = word(rng.randint(0, 45))
        pairs = [('username', username), ('token', benign_token), ('nonce', word(12))]
        rng.shuffle(pairs)
        obj = dict(pairs)
        separators = (',', ':') if rng.randrange(2) else (', ', ': ')
        payloads.append(json.dumps(obj, separators=separators))

        trigger = mixed_case(rng.choice(triggers))
        token = word(rng.randint(0, 12)) + trigger + word(rng.randint(0, 12))
        pairs = [('token', token), ('username', word(rng.randint(1, 32))), ('nonce', word(10))]
        rng.shuffle(pairs)
        payloads.append(json.dumps(dict(pairs)))

        # Trigger words without a token key, decoy keys, and raw malformed inputs
        # distinguish the daemon's actual behavior from a four-payload lookup table.
        payloads.append(json.dumps({'username': word(rng.randint(1, 32)), 'comment': trigger, 'nonce': word(8)}))
        payloads.append(json.dumps({'user_token': token, 'username_extra': word(rng.randint(33, 55))}))
        payloads.append(word(rng.randint(3, 20)) + trigger + word(rng.randint(3, 20)))

    payloads.extend([
        '{}',
        '[]',
        '',
        '{"token":"safe","username":"' + word(32) + '"}',
        '{"token":"safe","username":"' + word(33) + '"}',
        '{"token":"' + mixed_case('select') + '","username":"x"}',
    ])
    rng.shuffle(payloads)

    failures = []
    for index, payload in enumerate(payloads):
        expected = _daemon_says_safe(payload)
        try:
            actual = waf_filter.filter_request(payload)
        except Exception as e:
            failures.append(f'case {index}: raised {type(e).__name__}: {e}')
            continue
        if actual is not expected:
            failures.append(f'case {index}: expected {expected}, got {actual!r}')
        if len(failures) >= 10:
            break
    assert not failures, 'WAF disagreed with the legacy daemon:\n' + '\n'.join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
