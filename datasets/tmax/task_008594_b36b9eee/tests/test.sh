#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import select
import signal
import stat
import string
import subprocess
import time

DAEMON_PATH = '/home/user/app/daemon.py'
RUNNER_PATH = '/home/user/app/run_service.sh'
PROCESSED_PATH = '/home/user/app/processed_logs.txt'
BOUNCED_PATH = '/home/user/bounced_emails.txt'

EXPECTED_DAEMON = """#!/usr/bin/env python3
import os
import sys
import socket

if os.environ.get('TZ') != 'Europe/Berlin':
    print("CRITICAL: Invalid Timezone. Expected Europe/Berlin.")
    sys.exit(1)

if os.environ.get('LC_TIME') != 'de_DE.UTF-8':
    print("CRITICAL: Invalid Time Locale. Expected de_DE.UTF-8.")
    sys.exit(1)

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8080))
    data = s.recv(4096).decode('utf-8')
    s.close()

    with open('/home/user/app/processed_logs.txt', 'w') as f:
        f.write(data)
    print("Service completed successfully.")
except Exception as e:
    print(f"CRITICAL: Could not connect to internal metadata server on port 8080. Error: {e}")
    sys.exit(1)
""".encode()


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def test_original_final_state():
    assert os.path.isfile(BOUNCED_PATH), \
        f"File {BOUNCED_PATH} does not exist. Did you extract the emails and save them?"
    with open(BOUNCED_PATH, 'r') as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected = [
        'admin@nowhere.com',
        'charlie@bad-domain.net',
        'zack@bounced.org',
    ]
    assert lines == expected, \
        f"File {BOUNCED_PATH} does not contain the expected sorted list of bounced emails. Found: {lines}"

    assert os.path.isfile(PROCESSED_PATH), \
        f"File {PROCESSED_PATH} does not exist. The service may not have run successfully."
    with open(PROCESSED_PATH, 'r') as f:
        processed = f.read()
    assert 'STATUS: 250 Delivered' in processed and 'STATUS: 550 Bounced' in processed, \
        'The processed_logs.txt does not seem to contain the expected server output.'

    assert os.path.isfile(RUNNER_PATH), f"File {RUNNER_PATH} does not exist."
    with open(RUNNER_PATH, 'r') as f:
        runner = f.read()
    assert 'Europe/Berlin' in runner, \
        'TZ=Europe/Berlin does not appear to be exported in run_service.sh'
    assert 'de_DE.UTF-8' in runner, \
        'LC_TIME=de_DE.UTF-8 does not appear to be exported in run_service.sh'

    assert os.path.isfile(DAEMON_PATH), f"File {DAEMON_PATH} does not exist."
    daemon = read_bytes(DAEMON_PATH)
    assert b"if os.environ.get('TZ') != 'Europe/Berlin':" in daemon, \
        'daemon.py seems to have been modified. You were instructed not to modify it.'
    assert b'8080' in daemon, \
        'daemon.py seems to have been modified (the port should remain 8080).'
    assert daemon == EXPECTED_DAEMON, \
        'daemon.py was modified; it must remain the supplied artifact.'


def test_runner_really_exports_environment_and_launches_daemon():
    original = read_bytes(DAEMON_PATH)
    original_mode = stat.S_IMODE(os.stat(DAEMON_PATH).st_mode)
    token = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(24))
    probe_path = f'/tmp/daemon_probe_{token}.json'
    probe = f"""#!/usr/bin/env python3
import json
import os
with open({probe_path!r}, 'w') as f:
    json.dump({{'TZ': os.environ.get('TZ'), 'LC_TIME': os.environ.get('LC_TIME')}}, f)
""".encode()

    try:
        with open(DAEMON_PATH, 'wb') as f:
            f.write(probe)
        os.chmod(DAEMON_PATH, 0o755)
        env = os.environ.copy()
        env.pop('TZ', None)
        env.pop('LC_TIME', None)
        result = subprocess.run(
            [RUNNER_PATH], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        deadline = time.time() + 3
        while not os.path.exists(probe_path) and time.time() < deadline:
            time.sleep(0.05)
        assert result.returncode == 0, \
            f'run_service.sh failed while launching the service: {result.stdout}{result.stderr}'
        assert os.path.isfile(probe_path), \
            'run_service.sh did not actually launch /home/user/app/daemon.py.'
        with open(probe_path, 'r') as f:
            values = json.load(f)
        assert values.get('TZ') == 'Europe/Berlin', \
            'run_service.sh did not export TZ=Europe/Berlin to daemon.py.'
        assert values.get('LC_TIME') == 'de_DE.UTF-8', \
            'run_service.sh did not export LC_TIME=de_DE.UTF-8 to daemon.py.'
    finally:
        with open(DAEMON_PATH, 'wb') as f:
            f.write(original)
        os.chmod(DAEMON_PATH, original_mode)
        try:
            os.unlink(probe_path)
        except FileNotFoundError:
            pass

    assert read_bytes(DAEMON_PATH) == EXPECTED_DAEMON


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as f:
                rows = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[3] == '0A':
                if int(fields[1].rsplit(':', 1)[1], 16) == port:
                    inodes.add(fields[9])
    pids = set()
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
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_9090_server():
    for pid in listener_pids(9090):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listener_pids(9090) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def test_real_daemon_uses_the_configured_forwarding_route():
    assert read_bytes(DAEMON_PATH) == EXPECTED_DAEMON, \
        'daemon.py was modified before the execution test.'

    rng = random.SystemRandom()
    suffix = ''.join(rng.choice(string.ascii_lowercase + string.digits) for _ in range(20))
    payload = (
        f'[2026-01-02 08:00:00] STATUS: 250 Delivered | TO: delivered-{suffix}@example.test\n'
        f'[2026-01-02 08:01:00] STATUS: 550 Bounced | TO: bounce-a-{suffix}@invalid.test\n'
        f'[2026-01-02 08:02:00] STATUS: 450 Deferred | TO: deferred-{suffix}@example.test\n'
        f'[2026-01-02 08:03:00] STATUS: 550 Bounced | TO: bounce-z-{suffix}@invalid.test\n'
    ).encode()

    stop_existing_9090_server()
    server_code = r'''
import base64
import os
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 9090))
s.listen(1)
print('READY', flush=True)
s.settimeout(12)
c, _ = s.accept()
c.sendall(base64.b64decode(os.environ['VERIFY_PAYLOAD']))
c.close()
s.close()
'''
    server_env = os.environ.copy()
    server_env['VERIFY_PAYLOAD'] = base64.b64encode(payload).decode()
    server = subprocess.Popen(
        ['/usr/bin/python3', '-c', server_code], env=server_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        ready, _, _ = select.select([server.stdout], [], [], 5)
        assert ready and server.stdout.readline().strip() == 'READY', \
            'Could not start the verification metadata server on port 9090.'

        try:
            os.unlink(PROCESSED_PATH)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env['TZ'] = 'Europe/Berlin'
        env['LC_TIME'] = 'de_DE.UTF-8'
        result = subprocess.run(
            ['/usr/bin/python3', DAEMON_PATH], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12
        )
        assert result.returncode == 0, \
            'The real daemon could not reach the randomized server through localhost:8080. '
            f'Output: {(result.stdout + result.stderr).decode(errors="replace")}'
        assert os.path.isfile(PROCESSED_PATH), \
            'The real daemon did not create processed_logs.txt.'
        assert read_bytes(PROCESSED_PATH) == payload, \
            'processed_logs.txt was fabricated or did not contain the exact data sent through the forwarding route.'
        server.wait(timeout=3)
        assert server.returncode == 0, \
            f'The verification metadata server failed: {server.stderr.read()}'
        assert read_bytes(DAEMON_PATH) == EXPECTED_DAEMON, \
            'daemon.py was modified during execution.'
    finally:
        if server.poll() is None:
            server.kill()
            server.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
