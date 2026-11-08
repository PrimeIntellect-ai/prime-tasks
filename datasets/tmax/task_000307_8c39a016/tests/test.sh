#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import subprocess
import time
import urllib.request
import pytest

DEPLOY = '/home/user/deploy.sh'
APP = '/home/user/app.py'
LOG = '/home/user/historical.log'
BLOCKED = '/home/user/blocked_ips.txt'
FIREWALL = '/home/user/firewall.conf'


def listening_inodes(port):
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != '0A':
                        continue
                    if int(fields[1].rsplit(':', 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listening_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_services():
    victims = listener_pids(8080) | listener_pids(9090)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    assert not listening_inodes(8080), 'Port 8080 was not clean before deployment.'
    assert not listening_inodes(9090), 'Port 9090 was not clean before deployment.'


def make_dynamic_log():
    nonce = random.SystemRandom().randrange(20, 220)
    ips = [
        f'10.{nonce}.4.9',
        f'172.20.{nonce}.7',
        f'192.168.{nonce}.15',
        f'11.{nonce}.1.200',
    ]
    counts = {ips[0]: 7, ips[1]: 5, ips[2]: 5, ips[3]: 3}
    rows = []
    second = 0
    for ip, count in counts.items():
        for n in range(count):
            rows.append(f'[2026-09-11 10:00:{second:02d}] ERROR {ip} GET /missing-{n} 404')
            second += 1
    # Decoys ensure matching is based on the status field, not a substring.
    rows.extend([
        f'[2026-09-11 11:00:00] INFO {ips[3]} GET /contains-404 200',
        f'[2026-09-11 11:00:01] INFO 203.0.113.{nonce} GET /ok 200',
        f'[2026-09-11 11:00:02] WARN 198.51.100.{nonce} POST /other 403',
    ])
    random.SystemRandom().shuffle(rows)
    with open(LOG, 'w') as f:
        f.write('\n'.join(rows) + '\n')
    expected = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:3]
    return [f'{ip} {count}' for ip, count in expected]


def run_deploy():
    try:
        return subprocess.run(
            [DEPLOY], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Running {DEPLOY} failed: {e.stderr}')
    except subprocess.TimeoutExpired:
        pytest.fail(f'Running {DEPLOY} timed out.')


def socat_9090_pids():
    found = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='replace')
        except (FileNotFoundError, PermissionError):
            continue
        if 'socat' in cmd and '9090' in cmd:
            found.add(int(name))
    return found


def request(path):
    url = 'http://127.0.0.1:9090' + path
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.getcode(), response.read().decode('utf-8').strip()
    except Exception as e:
        pytest.fail(f'Failed to connect to {url}: {e}')


def test_complete_deployment_from_clean_state_and_idempotency():
    assert os.path.isfile(DEPLOY), f'{DEPLOY} does not exist.'
    assert os.access(DEPLOY, os.X_OK), f'{DEPLOY} is not executable.'

    stop_existing_services()
    expected_blocked = make_dynamic_log()

    # Seed stale output so deployment must recreate both files from current data.
    with open(BLOCKED, 'w') as f:
        f.write('1.1.1.1 999\n')
    with open(FIREWALL, 'w') as f:
        f.write('DENY_IP 1.1.1.1\nSTALE LINE\n')

    run_deploy()
    time.sleep(1)

    assert os.path.isfile(APP), f'{APP} does not exist.'
    assert os.path.isfile(BLOCKED), f'{BLOCKED} does not exist.'
    with open(BLOCKED) as f:
        blocked = f.read().strip().splitlines()
    assert blocked == expected_blocked, 'blocked_ips.txt was not derived correctly from the current log.'

    assert os.path.isfile(FIREWALL), f'{FIREWALL} does not exist.'
    with open(FIREWALL) as f:
        firewall = f.read().strip().splitlines()
    expected_firewall = ['DENY_IP ' + line.rsplit(' ', 1)[0] for line in expected_blocked]
    assert firewall == expected_firewall, 'firewall.conf does not exactly match the currently blocked IPs.'

    assert len(listening_inodes(8080)) == 1, 'Expected exactly one listening socket on port 8080.'
    assert len(listening_inodes(9090)) == 1, 'Expected exactly one listening socket on port 9090.'
    assert len(socat_9090_pids()) == 1, 'Expected exactly one socat process forwarding port 9090.'

    for path in ('/', '/health/check', '/arbitrary/path?probe=1'):
        status, body = request(path)
        assert status == 200, f'Expected HTTP status 200 for GET {path}, got {status}.'
        assert body == 'Deploy Success', f'Incorrect response for GET {path}: {body!r}'

    before_8080 = listener_pids(8080)
    before_9090 = listener_pids(9090)
    before_socat = socat_9090_pids()
    assert len(before_8080) == 1
    assert len(before_9090) == 1
    assert len(before_socat) == 1

    run_deploy()
    time.sleep(1)

    assert len(listening_inodes(8080)) == 1, 'Idempotency failed on port 8080.'
    assert len(listening_inodes(9090)) == 1, 'Idempotency failed on port 9090.'
    assert listener_pids(8080) == before_8080, 'Second deployment replaced or duplicated the application.'
    assert listener_pids(9090) == before_9090, 'Second deployment replaced or duplicated the port forward.'
    assert socat_9090_pids() == before_socat, 'Second deployment replaced or duplicated socat.'

    status, body = request('/after-second-deploy')
    assert status == 200
    assert body == 'Deploy Success'

    with open(BLOCKED) as f:
        assert f.read().strip().splitlines() == expected_blocked
    with open(FIREWALL) as f:
        assert f.read().strip().splitlines() == expected_firewall
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
