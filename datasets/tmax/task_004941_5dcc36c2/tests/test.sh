#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import datetime
import os
import py_compile
import random
import re
import subprocess
import time
import urllib.request
import uuid

APP_DATA = '/home/user/app_data'
PORTS = (8081, 8082, 8083)


def post(url, data, timeout=3):
    req = urllib.request.Request(url, data=data, method='POST')
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read().decode()


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def matching_pids(script, port=None):
    result = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        args = cmdline(name)
        has_script = any(arg == script or arg.endswith('/' + script) for arg in args)
        if has_script and (port is None or str(port) in args):
            result.append(int(name))
    return result


def wait_for_new_pid(script, old_pid, port=None, timeout=7):
    deadline = time.time() + timeout
    while time.time() < deadline:
        candidates = [p for p in matching_pids(script, port) if p != old_pid]
        if candidates:
            return candidates[0]
        time.sleep(0.2)
    return None


def test_directories_exist():
    assert os.path.isdir(APP_DATA), 'Directory /home/user/app_data does not exist'
    assert os.path.isdir('/home/user/supervisor_logs'), 'Directory /home/user/supervisor_logs does not exist'


def test_required_artifacts_are_scripts():
    for path in ('/home/user/backend.py', '/home/user/lb.py', '/home/user/monitor.py'):
        assert os.path.isfile(path), f'Missing required script: {path}'
        assert not os.path.islink(path), f'Required script must be a regular file: {path}'
        py_compile.compile(path, doraise=True)
    assert os.path.isfile('/home/user/supervisord.conf'), 'Missing supervisord.conf'


def test_processes_running():
    ps_output = subprocess.check_output(['ps', 'x']).decode()
    assert 'lb.py' in ps_output, 'Load balancer script (lb.py) is not running'
    assert 'monitor.py' in ps_output, 'Monitor script (monitor.py) is not running'
    assert 'backend.py' in ps_output, 'Backend scripts are not running'
    assert matching_pids('lb.py'), 'No actual lb.py process found'
    assert matching_pids('monitor.py'), 'No actual monitor.py process found'
    for port in PORTS:
        assert matching_pids('backend.py', port), f'Backend for port {port} is not running'


def test_supervisor_configuration():
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    assert cfg.read('/home/user/supervisord.conf'), 'Could not read supervisord.conf'
    assert cfg.has_section('supervisord'), 'Missing [supervisord] section'
    logfile = cfg.get('supervisord', 'logfile', fallback='')
    assert os.path.abspath(logfile).startswith('/home/user/supervisor_logs/'), \
        'Supervisor logfile must be in /home/user/supervisor_logs/'

    programs = [s for s in cfg.sections() if s.startswith('program:')]
    assert len(programs) >= 5, 'Supervisor must define the three backends, load balancer, and monitor'
    commands = {s: cfg.get(s, 'command', fallback='') for s in programs}

    selected = set()
    for port in PORTS:
        matches = [s for s, c in commands.items()
                   if re.search(r'(^|[ /])(?:/home/user/)?backend\.py(?:[ "\']|$)', c)
                   and re.search(rf'(?<!\d){port}(?!\d)', c)]
        assert matches, f'No supervised backend configured for port {port}'
        selected.add(matches[0])
    lb_sections = [s for s, c in commands.items() if re.search(r'(^|[ /])(?:/home/user/)?lb\.py(?:[ "\']|$)', c)]
    monitor_sections = [s for s, c in commands.items() if re.search(r'(^|[ /])(?:/home/user/)?monitor\.py(?:[ "\']|$)', c)]
    assert lb_sections, 'Load balancer is not configured in supervisor'
    assert monitor_sections, 'Monitor is not configured in supervisor'
    selected.update((lb_sections[0], monitor_sections[0]))
    assert len(selected) == 5, 'The five required services must have distinct supervisor program entries'
    for section in selected:
        policy = cfg.get(section, 'autorestart', fallback='').strip().lower()
        assert policy in ('true', 'unexpected'), f'{section} is not configured to restart after a crash'


def test_backends_directly_persist_uploads():
    os.makedirs(APP_DATA, exist_ok=True)
    for port in PORTS:
        path = f'{APP_DATA}/backend_{port}.dat'
        before = open(path, 'rb').read() if os.path.exists(path) else b''
        token = ('direct-' + uuid.uuid4().hex).encode()
        status, body = post(f'http://127.0.0.1:{port}/upload', token)
        assert status == 200, f'Backend {port} did not return HTTP 200'
        assert body == f'OK from {port}', f'Backend {port} returned an incorrect body: {body!r}'
        with open(path, 'rb') as f:
            after = f.read()
        assert after == before + token, f'Backend {port} did not append the exact request body'


def test_load_balancer_and_backends():
    count = random.SystemRandom().randint(7, 11)
    observed = []
    tokens = []
    for _ in range(count):
        token = ('lb-' + uuid.uuid4().hex).encode()
        status, body = post('http://127.0.0.1:8080/upload', token)
        assert status == 200, 'Load balancer did not return HTTP 200'
        assert body.startswith('OK from '), f'Unexpected response body: {body}'
        match = re.fullmatch(r'OK from (8081|8082|8083)', body)
        assert match, f'Load balancer did not return the exact backend response: {body!r}'
        port = int(match.group(1))
        observed.append(port)
        tokens.append((token, port))

    ports_hit = {f'OK from {p}' for p in observed}
    assert len(ports_hit) == 3, f'Load balancer did not hit all 3 backends. Hit: {ports_hit}'
    for previous, current in zip(observed, observed[1:]):
        assert current == PORTS[(PORTS.index(previous) + 1) % len(PORTS)], \
            f'Requests were not forwarded in round-robin order: {observed}'

    contents = {}
    for port in PORTS:
        with open(f'{APP_DATA}/backend_{port}.dat', 'rb') as f:
            contents[port] = f.read()
    for token, reported_port in tokens:
        assert token in contents[reported_port], \
            f'Upload reported as handled by {reported_port} was not persisted by that backend'
        assert all(token not in contents[p] for p in PORTS if p != reported_port), \
            'An upload was persisted by a backend other than the one whose response was returned'


def test_storage_monitor():
    for entry in os.scandir(APP_DATA):
        if entry.is_file() or entry.is_symlink():
            os.unlink(entry.path)

    marker = uuid.uuid4().hex
    large_name = f'backend_{marker}_large.dat'
    small_name = f'backend_{marker}_small.dat'
    other_name = f'quota_{marker}.bin'
    large_path = os.path.join(APP_DATA, large_name)
    small_path = os.path.join(APP_DATA, small_name)
    other_path = os.path.join(APP_DATA, other_name)

    with open(large_path, 'wb') as f:
        f.write(os.urandom(250000))
    with open(small_path, 'wb') as f:
        f.write(os.urandom(150000))

    # Below quota: neither .dat file may be deleted.
    time.sleep(2.7)
    assert os.path.exists(large_path) and os.path.exists(small_path), \
        'Monitor deleted a file while total storage was below quota'

    alert_path = '/home/user/alert.log'
    old_alert_size = os.path.getsize(alert_path) if os.path.exists(alert_path) else 0
    temp_path = f'/tmp/{other_name}'
    with open(temp_path, 'wb') as f:
        f.write(os.urandom(700000))
    os.replace(temp_path, other_path)
    started = datetime.datetime.now()

    deadline = time.time() + 7
    while time.time() < deadline and os.path.exists(large_path):
        time.sleep(0.2)

    assert not os.path.exists(large_path), 'Monitor did not delete the largest .dat file after total size exceeded quota'
    assert os.path.exists(small_path), 'Monitor deleted the wrong .dat file'
    assert os.path.exists(other_path), 'Monitor should select the largest .dat file, not a non-.dat file'
    assert os.path.exists(alert_path), 'Alert log (/home/user/alert.log) was not created'

    deadline = time.time() + 2
    new_log = ''
    while time.time() < deadline:
        with open(alert_path, 'r', errors='replace') as f:
            f.seek(old_alert_size)
            new_log = f.read()
        if large_name in new_log:
            break
        time.sleep(0.1)

    exact = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ALERT: Quota exceeded\. Deleted '
                       + re.escape(large_name) + r'$')
    matching = [exact.fullmatch(line) for line in new_log.splitlines()]
    matching = [m for m in matching if m]
    assert matching, 'Alert log format incorrect or missing entry for the dynamically selected largest file'
    timestamp = datetime.datetime.strptime(matching[-1].group(1), '%Y-%m-%d %H:%M:%S')
    assert started - datetime.timedelta(seconds=2) <= timestamp <= datetime.datetime.now() + datetime.timedelta(seconds=2), \
        'Alert timestamp is not the time of the quota event'


def test_supervisor_restart_policy():
    # Preserve the original lb.py crash/restart check and extend it to other managed services.
    lb_pids = matching_pids('lb.py')
    assert lb_pids, 'Could not find PID for lb.py to test restart policy'
    lb_pid = lb_pids[0]
    os.kill(lb_pid, 9)
    new_lb_pid = wait_for_new_pid('lb.py', lb_pid)
    assert new_lb_pid is not None, 'lb.py was not restarted by supervisor'
    assert new_lb_pid != lb_pid, 'lb.py PID did not change, kill might have failed'

    backend_pids = matching_pids('backend.py', 8082)
    assert backend_pids, 'Could not find backend 8082 PID to test restart policy'
    backend_pid = backend_pids[0]
    os.kill(backend_pid, 9)
    new_backend_pid = wait_for_new_pid('backend.py', backend_pid, 8082)
    assert new_backend_pid is not None, 'backend.py for port 8082 was not restarted by supervisor'

    monitor_pids = matching_pids('monitor.py')
    assert monitor_pids, 'Could not find monitor.py PID to test restart policy'
    monitor_pid = monitor_pids[0]
    os.kill(monitor_pid, 9)
    new_monitor_pid = wait_for_new_pid('monitor.py', monitor_pid)
    assert new_monitor_pid is not None, 'monitor.py was not restarted by supervisor'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
