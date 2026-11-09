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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import time

import pytest
import requests

SRC_DIR = '/home/user/src'
SOURCE = '/home/user/src/server.c'
MAKEFILE = '/home/user/src/Makefile'
SERVER = '/home/user/bin/metric_server'
WATCHDOG = '/home/user/bin/watchdog.sh'
PORT = 8085
TOKEN = 'secr3t-auth-77X'


def metric_server_pids():
    result = []
    expected = os.path.realpath(SERVER)
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            target = os.path.realpath(f'/proc/{name}/exe')
            if target == expected:
                result.append(int(name))
        except OSError:
            pass
    return result


def port_owner_pids(port):
    socket_inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    if not socket_inodes:
        return owners
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    owners.add(int(name))
                    break
        except OSError:
            pass
    return owners


def kill_and_wait(pids):
    pids = set(pids)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        alive = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            return
        time.sleep(0.1)


def wait_for_metric_server(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = metric_server_pids()
        if pids:
            return pids
        time.sleep(0.1)
    return []


def server_listens_on_all_ipv4(pid, port):
    inodes = set()
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
            except OSError:
                continue
            if target.startswith('socket:['):
                inodes.add(target[8:-1])
    except OSError:
        return False

    with open('/proc/net/tcp') as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) < 10 or fields[9] not in inodes or fields[3] != '0A':
                continue
            address, hex_port = fields[1].split(':')
            if address == '00000000' and int(hex_port, 16) == port:
                return True
    return False


def test_01_files_exist_and_permissions():
    assert os.path.isfile(MAKEFILE), 'Makefile is missing at /home/user/src/Makefile'
    assert os.path.isfile(SOURCE), 'server.c is missing at /home/user/src/server.c'
    assert os.path.isfile(SERVER), f'Executable missing at {SERVER}'
    assert os.access(SERVER, os.X_OK), f'{SERVER} is not executable'
    assert os.path.isfile(WATCHDOG), f'Watchdog script missing at {WATCHDOG}'
    assert os.access(WATCHDOG, os.X_OK), f'{WATCHDOG} is not executable'


def test_02_make_deploy_really_compiles_server_c():
    with open(SOURCE, 'rb') as f:
        original = f.read()
    original_mode = os.stat(SOURCE).st_mode

    # A deploy target that ignores server.c (for example, one that merely copies
    # a placeholder executable) must not succeed when server.c cannot compile.
    try:
        with open(SOURCE, 'wb') as f:
            f.write(b'#error verifier_requires_deploy_to_compile_server_c\n' + original)
        os.chmod(SOURCE, original_mode)
        if os.path.lexists(SERVER):
            os.remove(SERVER)
        bad = subprocess.run(
            ['make', '-B', 'deploy'], cwd=SRC_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
        )
        assert bad.returncode != 0, 'make deploy succeeded even though server.c was intentionally uncompilable'
    finally:
        with open(SOURCE, 'wb') as f:
            f.write(original)
        os.chmod(SOURCE, original_mode)
        if os.path.lexists(SERVER):
            os.remove(SERVER)

    dry = subprocess.run(
        ['make', '-B', '-n', 'deploy'], cwd=SRC_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15
    )
    assert dry.returncode == 0, f'make deploy dry run failed:\n{dry.stdout}'
    assert re.search(r'(^|[\s;/])(?:\S*/)?gcc(?:\s|$)', dry.stdout, re.MULTILINE), 'deploy target does not invoke gcc'
    assert re.search(r'(^|[\s;/])(?:\./)?server\.c(?:\s|$)', dry.stdout, re.MULTILINE), 'deploy target does not compile server.c'
    assert '/home/user/bin/metric_server' in dry.stdout, 'deploy target does not produce /home/user/bin/metric_server'

    built = subprocess.run(
        ['make', '-B', 'deploy'], cwd=SRC_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert built.returncode == 0, f'make deploy failed:\n{built.stdout}'
    assert os.path.isfile(SERVER), 'make deploy did not create /home/user/bin/metric_server'
    assert os.access(SERVER, os.X_OK), 'deployed metric_server is not executable'
    with open(SERVER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'deployed metric_server is not a compiled ELF executable'


def test_03_crontab():
    try:
        output = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail('Failed to read crontab. Is it configured?')

    lines = [line.strip() for line in output.split('\n') if line.strip() and not line.strip().startswith('#')]
    found = False
    for line in lines:
        if WATCHDOG in line:
            parts = line.split()
            if len(parts) >= 6 and parts[:5] == ['*', '*', '*', '*', '*']:
                found = True
                break
    assert found, 'Crontab does not contain a 1-minute cron entry for /home/user/bin/watchdog.sh'


def test_04_watchdog_starts_and_does_not_duplicate_server():
    # Remove both the expected executable and any unrelated process occupying
    # the fixed port, so a separately pre-launched service cannot satisfy tests.
    kill_and_wait(set(metric_server_pids()) | port_owner_pids(PORT))
    assert not metric_server_pids(), 'Could not stop the existing metric_server before watchdog test'
    assert not port_owner_pids(PORT), 'Port 8085 is still occupied before watchdog test'

    first = subprocess.run([WATCHDOG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    assert first.returncode == 0, 'watchdog.sh failed when metric_server was stopped'
    pids = wait_for_metric_server()
    assert pids, 'watchdog.sh did not start /home/user/bin/metric_server'

    deadline = time.time() + 5
    while time.time() < deadline and not any(server_listens_on_all_ipv4(pid, PORT) for pid in pids):
        time.sleep(0.1)
    assert any(server_listens_on_all_ipv4(pid, PORT) for pid in pids), 'metric_server is not listening on 0.0.0.0:8085'

    before = set(metric_server_pids())
    second = subprocess.run([WATCHDOG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    assert second.returncode == 0, 'watchdog.sh failed while metric_server was already running'
    time.sleep(1)
    after = set(metric_server_pids())
    assert after == before, 'watchdog.sh started a duplicate or replaced an already-running metric_server'


def test_05_http_server_responses():
    base_url = 'http://127.0.0.1:8085/status'

    try:
        r = requests.get(base_url, headers={'Authorization': f'Bearer {TOKEN}'}, timeout=5)
        assert r.status_code == 200, f'Expected 200 OK with valid token, got {r.status_code}'
        assert r.text == 'OK\n', f"Expected body 'OK\\n', got {repr(r.text)}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to metric_server: {e}')

    try:
        r = requests.get(base_url, timeout=5)
        assert r.status_code == 401, f'Expected 401 Unauthorized without token, got {r.status_code}'
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to metric_server: {e}')

    try:
        r = requests.get(base_url, headers={'Authorization': 'Bearer wrong-token'}, timeout=5)
        assert r.status_code == 401, f'Expected 401 Unauthorized with wrong token, got {r.status_code}'
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to metric_server: {e}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
