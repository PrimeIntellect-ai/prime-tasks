#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import signal
import subprocess
import time
import urllib.request
import pytest

NGINX_CONF = '/home/user/deploy/nginx.conf'
NGINX_PREFIX = '/home/user/deploy/'
NGINX_PIDFILE = '/home/user/deploy/nginx.pid'
WATCHDOG = '/home/user/watchdog.py'
STATUS_LOG = '/home/user/status.log'


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def process_ppid(pid):
    try:
        with open(f'/proc/{pid}/stat') as f:
            fields = f.read().split()
        return int(fields[3])
    except (OSError, ValueError, IndexError):
        return -1


def descendants(root_pid):
    result = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir('/proc'):
            if not name.isdigit():
                continue
            pid = int(name)
            if pid not in result and process_ppid(pid) in result:
                result.add(pid)
                changed = True
    return result


def listening_inodes(port):
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                        result.add(fields[9])
        except OSError:
            pass
    return result


def process_socket_inodes(pids):
    result = set()
    for pid in pids:
        fd_dir = f'/proc/{pid}/fd'
        try:
            names = os.listdir(fd_dir)
        except OSError:
            continue
        for name in names:
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            if target.startswith('socket:[') and target.endswith(']'):
                result.add(target[8:-1])
    return result


def wait_http(url, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f'{url} did not become ready: {last_error}')


def nginx_master_pid():
    assert os.path.isfile(NGINX_PIDFILE), 'Local Nginx pid file is missing.'
    with open(NGINX_PIDFILE) as f:
        pid = int(f.read().strip())
    command = cmdline(pid)
    assert command, 'The Nginx master process from the local pid file is not running.'
    assert 'nginx' in command and NGINX_CONF in command and NGINX_PREFIX in command, \
        f'Nginx was not started with the specified local configuration and prefix: {command!r}'
    return pid


def stop_local_nginx():
    pid = nginx_master_pid()
    os.kill(pid, signal.SIGQUIT)
    deadline = time.time() + 5
    while time.time() < deadline and os.path.exists(f'/proc/{pid}'):
        time.sleep(0.1)
    if os.path.exists(f'/proc/{pid}'):
        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 3
        while time.time() < deadline and os.path.exists(f'/proc/{pid}'):
            time.sleep(0.1)
    assert not os.path.exists(f'/proc/{pid}'), 'Could not stop local Nginx for watchdog failure tests.'


def start_local_nginx():
    subprocess.run(
        ['nginx', '-c', NGINX_CONF, '-p', NGINX_PREFIX],
        check=True, capture_output=True, text=True
    )
    wait_http('http://127.0.0.1:8080/')


def run_watchdog(expected):
    initial_size = os.path.getsize(STATUS_LOG) if os.path.exists(STATUS_LOG) else 0
    try:
        result = subprocess.run(
            ['python3', WATCHDOG], capture_output=True, text=True, timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Watchdog did not apply a finite HTTP timeout and exit promptly.')
    assert result.returncode == 0, f'Watchdog script failed to execute: {result.stderr}'
    assert os.path.isfile(STATUS_LOG), f'{STATUS_LOG} was not created by the watchdog script.'
    with open(STATUS_LOG, 'rb') as f:
        f.seek(initial_size)
        new_content = f.read()
    assert new_content == expected.encode(), \
        f'Watchdog appended {new_content!r}; expected {expected.encode()!r}.'


def start_mock_server(mode):
    code = r'''
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
mode = sys.argv[1]
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if mode == 'error':
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b'unavailable')
        else:
            time.sleep(60)
    def log_message(self, *args):
        pass
server = ThreadingHTTPServer(('127.0.0.1', 8080), Handler)
server.serve_forever()
'''
    proc = subprocess.Popen(
        ['python3', '-c', code, mode], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True
    )
    time.sleep(0.3)
    assert proc.poll() is None, f'Mock HTTP server failed to start: {proc.stderr.read()}'
    return proc


def test_nginx_conf_updated():
    conf_path = NGINX_CONF
    assert os.path.isfile(conf_path), f'{conf_path} is missing.'
    with open(conf_path, 'r') as f:
        content = f.read()
    assert 'proxy_pass http://127.0.0.1:5001;' in content, \
        'nginx.conf was not updated to proxy to port 5001.'
    result = subprocess.run(
        ['nginx', '-t', '-c', NGINX_CONF, '-p', NGINX_PREFIX],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f'The local Nginx configuration is invalid: {result.stderr}'


def test_config_json_created():
    config_path = '/home/user/deploy/config.json'
    assert os.path.isfile(config_path), f'{config_path} is missing.'
    with open(config_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{config_path} does not contain valid JSON.')
    assert data == {'status': 'ok'}, \
        f'{config_path} does not contain the expected JSON payload.'


def test_services_running():
    backend_pids = set()
    for name in os.listdir('/proc'):
        if name.isdigit() and '/home/user/deploy/app.py' in cmdline(int(name)):
            backend_pids.add(int(name))
    assert backend_pids, 'The specified backend application is not running.'
    backend_listeners = listening_inodes(5001)
    assert backend_listeners & process_socket_inodes(backend_pids), \
        'The specified app.py process is not the service listening on port 5001.'

    master = nginx_master_pid()
    nginx_listeners = listening_inodes(8080)
    assert nginx_listeners & process_socket_inodes(descendants(master)), \
        'The locally configured Nginx process is not the service listening on port 8080.'

    try:
        with urllib.request.urlopen('http://127.0.0.1:5001/', timeout=2) as response:
            assert response.status == 200, 'Backend app on port 5001 did not return HTTP 200.'
    except Exception as exc:
        pytest.fail(f'Could not connect to backend app on port 5001: {exc}')

    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/', timeout=2) as response:
            assert response.status == 200, 'Nginx on port 8080 did not return HTTP 200.'
    except Exception as exc:
        pytest.fail(f'Could not connect to Nginx on port 8080: {exc}')


def test_watchdog_script():
    assert os.path.isfile(WATCHDOG), f'{WATCHDOG} is missing.'

    cron = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    saved_crontab = cron.stdout if cron.returncode == 0 else None
    if saved_crontab is not None:
        subprocess.run(['crontab', '-r'], capture_output=True)

    nginx_stopped = False
    mock = None
    try:
        run_watchdog('UP\n')
        stop_local_nginx()
        nginx_stopped = True

        scenarios = ['error', 'timeout', 'refused']
        random.SystemRandom().shuffle(scenarios)
        for scenario in scenarios:
            if scenario in ('error', 'timeout'):
                mock = start_mock_server(scenario)
            else:
                time.sleep(0.2)
            try:
                run_watchdog('DOWN\n')
            finally:
                if mock is not None:
                    mock.terminate()
                    try:
                        mock.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        mock.kill()
                        mock.wait(timeout=3)
                    mock = None
                    time.sleep(0.2)
    finally:
        if mock is not None:
            mock.kill()
            mock.wait(timeout=3)
        if nginx_stopped:
            start_local_nginx()
        if saved_crontab is not None:
            subprocess.run(['crontab', '-'], input=saved_crontab, text=True, check=True)


def test_crontab_configured():
    result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert result.returncode == 0, \
        'Failed to read crontab. Ensure crontab is configured for the user.'

    crontab_content = result.stdout
    assert 'watchdog.py' in crontab_content, \
        "watchdog.py is not scheduled in the user's crontab."

    valid_cron_found = False
    for line in crontab_content.splitlines():
        if not line.strip().startswith('#') and 'watchdog.py' in line:
            parts = line.split()
            if len(parts) >= 6 and parts[:5] == ['*', '*', '*', '*', '*'] and 'python3' in line:
                valid_cron_found = True
                break

    assert valid_cron_found, \
        'Crontab does not contain a valid entry to run watchdog.py every minute using python3.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
