#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc_dir in Path('/proc').iterdir():
        if not proc_dir.name.isdigit():
            continue
        try:
            for fd in (proc_dir / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc_dir.name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def process_info(pid):
    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        argv = [part.decode(errors='replace') for part in f.read().split(b'\0') if part]
    exe = os.path.basename(os.readlink(f'/proc/{pid}/exe'))
    return exe, argv


def test_port_forward_script():
    script_path = '/home/user/port_forward.sh'
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."

    with open(script_path, 'r') as f:
        content = f.read().strip()

    assert 'socat' in content, f"{script_path} does not contain 'socat' command."
    assert '8080' in content, f"{script_path} does not contain port 8080."
    assert '9000' in content, f"{script_path} does not contain port 9000."

    command_lines = [line.strip() for line in content.splitlines()
                     if line.strip() and not line.lstrip().startswith('#!')]
    assert len(command_lines) == 1, 'port_forward.sh must contain one socat command line.'
    argv = shlex.split(command_lines[0])
    if argv and argv[-1] == '&':
        argv.pop()
    assert argv and os.path.basename(argv[0]) == 'socat', 'The forwarding command must directly invoke socat.'

    matching = []
    for pid in listener_pids(8080):
        try:
            exe, live_argv = process_info(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if exe == 'socat' and live_argv and os.path.basename(live_argv[0]) == 'socat':
            matching.append(live_argv)

    assert matching, 'Port 8080 is not actually being listened to by socat.'
    assert any(
        len(live) == len(argv)
        and os.path.basename(live[0]) == os.path.basename(argv[0])
        and live[1:] == argv[1:]
        for live in matching
    ), 'The running socat listener does not match the command saved in port_forward.sh.'

    live = next(live for live in matching if len(live) == len(argv) and live[1:] == argv[1:])
    joined = ' '.join(live[1:])
    assert re.search(r'(?i)(?:tcp4?-listen|listen):8080(?:,|$)', joined), 'socat is not listening on TCP port 8080.'
    assert re.search(r'(?i)tcp(?:4)?(?:-connect)?:127\.0\.0\.1:9000(?:,|$)', joined), 'socat is not forwarding to 127.0.0.1:9000.'


def test_backend_direct_connection():
    pids = listener_pids(9000)
    assert pids, 'Nothing is listening on backend port 9000.'
    backend_owned = False
    for pid in pids:
        try:
            exe, argv = process_info(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if exe.startswith('python') and any(os.path.realpath(arg) == '/home/user/backend.py' for arg in argv[1:]):
            backend_owned = True
            break
    assert backend_owned, 'Port 9000 is not served by /home/user/backend.py.'

    url = 'http://127.0.0.1:9000/'
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected status 200 on port 9000, got {response.status}'
            body = response.read().decode('utf-8').strip()
            assert body == 'SYSTEM_OK', f"Expected 'SYSTEM_OK' from backend, got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to backend on port 9000: {e}')


def test_port_forwarding_connection():
    url = 'http://127.0.0.1:8080/'
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected status 200 on port 8080, got {response.status}'
            body = response.read().decode('utf-8').strip()
            assert body == 'SYSTEM_OK', f"Expected 'SYSTEM_OK' from forwarded port, got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to forwarded port 8080: {e}')


def test_supervisor_actively_polls_dependency_port():
    supervisor = '/home/user/supervisor.py'
    services_path = '/home/user/services.json'
    assert os.path.isfile(supervisor), f'File {supervisor} does not exist.'

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]

    work = Path(tempfile.mkdtemp(prefix='supervisor_probe_'))
    ready_file = work / 'ready'
    accepted_file = work / 'accepted'
    launched_file = work / 'launched'
    db_script = work / 'delayed_db.py'
    dependent_script = work / 'dependent.py'
    delay = 1.25 + (port % 50) / 100.0

    db_script.write_text(f'''import socket, time\nfrom pathlib import Path\ntime.sleep({delay!r})\ns = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\ns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\ns.bind(("127.0.0.1", {port}))\ns.listen(5)\nPath({str(ready_file)!r}).write_text(str(time.monotonic()))\nwhile True:\n    conn, _ = s.accept()\n    Path({str(accepted_file)!r}).write_text(str(time.monotonic()))\n    conn.close()\n''')
    dependent_script.write_text(f'''import time\nfrom pathlib import Path\nPath({str(launched_file)!r}).write_text(str(time.monotonic()))\nwhile True:\n    time.sleep(10)\n''')

    original = Path(services_path).read_bytes()
    config = {
        'probe_db': {'command': f'python3 {db_script}', 'depends_on_port': None},
        'probe_dependent': {'command': f'python3 {dependent_script}', 'depends_on_port': port},
    }
    proc = None
    try:
        Path(services_path).write_text(json.dumps(config))
        proc = subprocess.Popen(
            ['python3', supervisor],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )

        time.sleep(0.4)
        assert not launched_file.exists(), 'Supervisor launched the dependent service before its port could be ready.'

        deadline = time.monotonic() + delay + 6
        while time.monotonic() < deadline and not launched_file.exists():
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else ''
                pytest.fail(f'Supervisor exited before launching the dependent service. Output: {output}')
            time.sleep(0.05)

        assert ready_file.exists(), 'The dependency never reached its listening state.'
        assert launched_file.exists(), 'Supervisor never launched the dependent service after the port opened.'

        accept_deadline = time.monotonic() + 2
        while time.monotonic() < accept_deadline and not accepted_file.exists():
            time.sleep(0.05)
        assert accepted_file.exists(), 'No TCP connection reached the dependency port; the supervisor did not actively poll it.'

        ready_at = float(ready_file.read_text())
        launched_at = float(launched_file.read_text())
        assert launched_at >= ready_at, 'Supervisor launched the dependent service before the dependency was listening.'
    finally:
        Path(services_path).write_bytes(original)
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


def test_startup_log_order():
    log_path = '/home/user/startup.log'
    assert os.path.exists(log_path), f'File {log_path} does not exist.'

    with open(log_path, 'r') as f:
        log_content = f.read()

    db_msg = 'DB Mock listening on 5432'
    launch_backend_msg = 'Launching backend'
    backend_listen_msg = 'Backend service listening on 9000'

    assert db_msg in log_content, f"'{db_msg}' not found in {log_path}"
    db_idx = log_content.find(db_msg)
    launch_backend_idx = log_content.find(launch_backend_msg)
    backend_listen_idx = log_content.find(backend_listen_msg)

    assert launch_backend_idx != -1 or backend_listen_idx != -1, 'Backend launch/listen messages not found in log.'
    if launch_backend_idx != -1:
        assert db_idx < launch_backend_idx, f"Supervisor did not wait: '{db_msg}' appeared after '{launch_backend_msg}'"
    if backend_listen_idx != -1:
        assert db_idx < backend_listen_idx, f"Supervisor did not wait: '{db_msg}' appeared after '{backend_listen_msg}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
