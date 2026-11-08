#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import subprocess
import time
import urllib.error
import urllib.request

CONFIG = '/home/user/nginx/nginx.conf'
PREFIX = '/home/user/nginx'
APP = '/home/user/backend/app.py'
EXPECT_SCRIPT = '/home/user/start_backend.exp'
MONITOR = '/home/user/monitor.py'
HEALTH = '/home/user/health.log'


def proc_info():
    result = {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f'/proc/{name}/exe')
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='replace')
            result[int(name)] = (exe, cmd)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def nginx_pids(require_master=True):
    found = set()
    master = False
    for pid, (exe, cmd) in proc_info().items():
        if os.path.basename(exe) == 'nginx':
            found.add(pid)
            if ('master process' in cmd and '-p /home/user/nginx' in cmd
                    and '/home/user/nginx/nginx.conf' in cmd):
                master = True
    if require_master:
        assert master, 'A real nginx master using the requested prefix and configuration is not running'
    return found


def backend_pids():
    found = set()
    for pid, (exe, cmd) in proc_info().items():
        if (os.path.basename(exe).startswith('python') and
                APP in cmd.split()):
            found.add(pid)
    return found


def listener_inodes(port):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == '0A':
                        local_port = int(fields[1].rsplit(':', 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def process_owns_listener(pids, port):
    wanted = {f'socket:[{inode}]' for inode in listener_inodes(port)}
    if not wanted:
        return False
    for pid in pids:
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        return True
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def wait_until(predicate, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.15)
    return False


def stop_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if not wait_until(lambda: not any(os.path.exists(f'/proc/{p}') for p in pids), 4):
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    assert wait_until(lambda: not process_owns_listener(pids, 9001), 4)


def launch_with_expect():
    launcher = subprocess.Popen(
        ['expect', EXPECT_SCRIPT],
        cwd='/home/user',
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    assert wait_until(lambda: bool(backend_pids()) and
                      process_owns_listener(backend_pids(), 9001), 12), \
        'Executing start_backend.exp did not start app.py listening on port 9001'
    return launcher


def fetch(url, timeout=5):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, dict(response.headers.items()), response.read()


def assert_expected_json(body):
    data = json.loads(body.decode('utf-8'))
    assert data.get('status') == 'ok', f"Expected status 'ok', got {data.get('status')}"
    assert data.get('timezone') == 'Europe/Paris', \
        f"Expected timezone 'Europe/Paris', got {data.get('timezone')}"


def run_monitor(expected):
    before = b''
    if os.path.exists(HEALTH):
        with open(HEALTH, 'rb') as f:
            before = f.read()
    proc = subprocess.run(['python3', MONITOR], cwd='/home/user',
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=15)
    assert proc.returncode == 0, \
        f'monitor.py did not handle the condition gracefully: {proc.stderr.decode(errors="replace")}'
    assert os.path.exists(HEALTH), f'{HEALTH} does not exist. Did the monitor script run?'
    with open(HEALTH, 'rb') as f:
        after = f.read()
    assert after.startswith(before), 'monitor.py replaced health.log instead of appending to it'
    appended = after[len(before):]
    assert appended in ((expected + '\n').encode(), expected.encode()), \
        f'monitor.py must append exactly {expected}; appended {appended!r}'


def start_nginx():
    proc = subprocess.run(
        ['nginx', '-p', PREFIX, '-c', CONFIG],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert proc.returncode == 0, f'Could not restart nginx: {proc.stderr}'
    assert wait_until(lambda: bool(nginx_pids(False)) and
                      process_owns_listener(nginx_pids(False), 8080), 8)
    nginx_pids(True)


def stop_nginx():
    subprocess.run(['nginx', '-p', PREFIX, '-c', CONFIG, '-s', 'stop'],
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert wait_until(lambda: not listener_inodes(8080), 8), \
        'nginx did not stop listening on port 8080'


def test_complete_workflow():
    # Preserve the original file/configuration assertions.
    assert os.path.exists(CONFIG), f'{CONFIG} does not exist'
    with open(CONFIG) as f:
        config = f.read()
    assert 'proxy_pass http://127.0.0.1:9001;' in config, \
        'Nginx config was not updated to proxy requests to 127.0.0.1:9001'
    assert 'listen 8080;' in config, 'Nginx must continue to listen on port 8080'

    real_nginx = nginx_pids(True)
    assert process_owns_listener(real_nginx, 8080), \
        'Port 8080 is not owned by the real nginx process'

    initial_backend = backend_pids()
    assert initial_backend, 'The Python backend (app.py) is not running'
    assert process_owns_listener(initial_backend, 9001), \
        'The app.py process is not the listener on port 9001'

    assert os.path.exists(EXPECT_SCRIPT), f'{EXPECT_SCRIPT} does not exist'
    with open(EXPECT_SCRIPT) as f:
        expect_content = f.read()
    assert '8374' in expect_content, \
        "The expect script does not contain the required pin code '8374'"
    assert 'Europe/Paris' in expect_content, \
        "The expect script does not set the timezone to 'Europe/Paris'"
    assert 'spawn' in expect_content or 'app.py' in expect_content, \
        'The expect script does not appear to spawn the backend'
    syntax = subprocess.run(['expect', '-n', EXPECT_SCRIPT],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, 'start_backend.exp is not valid Expect/Tcl syntax'

    assert os.path.exists(MONITOR), f'{MONITOR} does not exist'
    with open(MONITOR) as f:
        monitor_content = f.read()
    assert 'try' in monitor_content and 'except' in monitor_content, \
        'monitor.py does not appear to handle exceptions gracefully (missing try/except blocks)'

    # Execute the submitted Expect artifact after removing the old backend.
    stop_pids(initial_backend)
    launch_with_expect()

    direct_status, direct_headers, direct_body = fetch('http://127.0.0.1:9001/direct-check')
    assert direct_status == 200
    assert_expected_json(direct_body)
    assert 'BaseHTTP' in direct_headers.get('Server', ''), \
        'The process on port 9001 is not the supplied Python HTTP backend'

    marker = f'verifier-{random.getrandbits(64):016x}'
    proxy_status, proxy_headers, proxy_body = fetch(f'http://127.0.0.1:8080/{marker}')
    assert proxy_status == 200, f'Expected HTTP 200, got {proxy_status}'
    assert_expected_json(proxy_body)
    assert 'nginx' in proxy_headers.get('Server', '').lower(), \
        'The response on port 8080 was not served through nginx'
    with open('/home/user/nginx/logs/access.log', errors='replace') as f:
        access_log = f.read()
    assert marker in access_log, 'The verification request did not pass through nginx'

    # Exercise the monitor in its success case.
    run_monitor('SUCCESS')

    # A live nginx with no backend produces an HTTP error (normally 502).
    current_backend = backend_pids()
    stop_pids(current_backend)
    try:
        fetch('http://127.0.0.1:8080/backend-down', timeout=5)
        assert False, 'nginx unexpectedly returned success while the backend was stopped'
    except urllib.error.HTTPError as exc:
        assert exc.code != 200
    run_monitor('ERROR')

    # Restore the backend by executing Expect again, then test connection failure.
    launch_with_expect()
    stop_nginx()
    run_monitor('ERROR')

    # Leave the required final state running and verify it once more.
    start_nginx()
    status, headers, body = fetch('http://127.0.0.1:8080/final-check')
    assert status == 200
    assert 'nginx' in headers.get('Server', '').lower()
    assert_expected_json(body)
    assert process_owns_listener(nginx_pids(True), 8080)
    assert process_owns_listener(backend_pids(), 9001)
    run_monitor('SUCCESS')

    with open(HEALTH) as f:
        health_content = f.read()
    assert 'SUCCESS' in health_content, "health.log does not contain the 'SUCCESS' string"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
