#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pathlib
import pwd
import random
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import time
import uuid

import pytest

HOME = pathlib.Path('/home/user')
USER = pwd.getpwnam('user')


def run_as_user(argv, timeout=15):
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['USER'] = 'user'
    env['LOGNAME'] = 'user'

    def demote():
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    return subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        env=env,
        preexec_fn=demote,
    )


def proc_cmdline(pid):
    return pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ')


def proc_state(pid):
    try:
        for line in pathlib.Path(f'/proc/{pid}/status').read_text().splitlines():
            if line.startswith('State:'):
                return line.split()[1]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None
    return None


def direct_http_over_socket():
    sock_path = '/home/user/app.sock'
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect(sock_path)
        s.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
        chunks = []
        while True:
            data = s.recv(4096)
            if not data:
                break
            chunks.append(data)
        response = b''.join(chunks)
    finally:
        s.close()
    assert b'HTTP/1.1 200 OK' in response
    assert response.endswith(b'Hello World!')
    return response


def child_webapp_pids(supervisor_pid):
    result = []
    for entry in pathlib.Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            status = (entry / 'status').read_text()
            ppid = None
            for line in status.splitlines():
                if line.startswith('PPid:'):
                    ppid = int(line.split()[1])
                    break
            cmd = (entry / 'cmdline').read_bytes().replace(b'\0', b' ')
            if ppid == supervisor_pid and b'/home/user/webapp.py' in cmd and proc_state(int(entry.name)) != 'Z':
                result.append(int(entry.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return result


def test_nginx_conf_fixed():
    nginx_conf_path = '/home/user/nginx/nginx.conf'
    assert os.path.isfile(nginx_conf_path), f'File missing: {nginx_conf_path}'
    with open(nginx_conf_path, 'r') as f:
        content = f.read()
    assert 'proxy_pass http://unix:/home/user/app.sock;' in content, 'Nginx config not updated to point to correct socket.'


def test_bgp_enabled_log():
    log_path = '/home/user/bgp_enabled.log'
    assert os.path.isfile(log_path), 'Router CLI automation failed: bgp_enabled.log not created.'
    with open(log_path, 'r') as f:
        content = f.read()
    assert 'BGP is UP' in content, 'bgp_enabled.log does not contain the expected text.'


def test_auto_login_exists_uses_pexpect_and_drives_router():
    script = HOME / 'auto_login.py'
    assert script.is_file(), 'auto_login.py is missing.'
    source = script.read_text()
    tree = ast.parse(source, filename=str(script))

    pexpect_modules = set()
    spawn_names = set()
    imports_pexpect = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'pexpect':
                    imports_pexpect = True
                    pexpect_modules.add(alias.asname or 'pexpect')
        elif isinstance(node, ast.ImportFrom) and node.module == 'pexpect':
            imports_pexpect = True
            for alias in node.names:
                if alias.name == 'spawn':
                    spawn_names.add(alias.asname or alias.name)

    calls_spawn = False
    calls_expect = False
    calls_sendline = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in spawn_names:
            calls_spawn = True
        elif isinstance(func, ast.Attribute):
            if func.attr == 'spawn' and isinstance(func.value, ast.Name) and func.value.id in pexpect_modules:
                calls_spawn = True
            elif func.attr == 'expect':
                calls_expect = True
            elif func.attr == 'sendline':
                calls_sendline = True

    assert imports_pexpect and calls_spawn and calls_expect and calls_sendline, \
        'auto_login.py must use pexpect spawn/expect/sendline for the interaction.'

    router = HOME / 'router_cli.py'
    original = router.read_bytes()
    original_mode = stat.S_IMODE(router.stat().st_mode)
    token = uuid.uuid4().hex
    instrumented = f'''import pathlib
import sys


def prompt(text):
    sys.stdout.write(text)
    sys.stdout.flush()
    line = sys.stdin.readline()
    if not line:
        raise SystemExit(20)
    return line.strip()


if prompt("Username: ") != "admin":
    raise SystemExit(21)
if prompt("Password: ") != "secret":
    raise SystemExit(22)
enabled = False
while True:
    cmd = prompt("Router> ")
    if cmd == "enable bgp" and not enabled:
        enabled = True
    elif cmd == "exit" and enabled:
        pathlib.Path("/home/user/bgp_enabled.log").write_text("BGP is UP {token}\\n")
        raise SystemExit(0)
    else:
        raise SystemExit(23)
'''
    try:
        router.write_text(instrumented)
        os.chmod(router, 0o755)
        try:
            (HOME / 'bgp_enabled.log').unlink()
        except FileNotFoundError:
            pass
        result = run_as_user([sys.executable, str(script)], timeout=12)
        assert result.returncode == 0, f'auto_login.py failed: {result.stdout}\n{result.stderr}'
        assert (HOME / 'bgp_enabled.log').read_text() == f'BGP is UP {token}\n', \
            'auto_login.py did not complete the required interactive sequence.'
    finally:
        router.write_bytes(original)
        os.chmod(router, original_mode)


def test_supervisor_running():
    pid_path = '/home/user/supervisor.pid'
    assert os.path.isfile(pid_path), 'Supervisor PID file not found.'
    with open(pid_path, 'r') as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f'PID file contains invalid PID: {pid_str}'
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f'Supervisor process with PID {pid} is not running.')


def test_supervisor_restarts_webapp():
    script = HOME / 'supervisor.py'
    assert script.is_file(), 'supervisor.py is missing.'
    pid_text = (HOME / 'supervisor.pid').read_text().strip()
    assert pid_text.isdigit()
    supervisor_pid = int(pid_text)
    os.kill(supervisor_pid, 0)
    assert b'/home/user/supervisor.py' in proc_cmdline(supervisor_pid), \
        'supervisor.pid does not identify the submitted supervisor.py process.'

    deadline = time.time() + 5
    old_children = []
    while time.time() < deadline:
        old_children = child_webapp_pids(supervisor_pid)
        if old_children:
            break
        time.sleep(0.1)
    assert old_children, 'Supervisor has no python3 /home/user/webapp.py child.'
    direct_http_over_socket()

    old_set = set(old_children)
    for child in old_children:
        os.kill(child, signal.SIGKILL)

    new_children = []
    deadline = time.time() + 8
    while time.time() < deadline:
        os.kill(supervisor_pid, 0)
        candidates = child_webapp_pids(supervisor_pid)
        new_children = [pid for pid in candidates if pid not in old_set]
        if new_children:
            try:
                direct_http_over_socket()
                break
            except (AssertionError, OSError, socket.timeout):
                pass
        time.sleep(0.1)
    else:
        pytest.fail('Supervisor did not restart webapp.py after the child was killed.')
    assert new_children


def test_app_sock_exists():
    sock_path = '/home/user/app.sock'
    assert os.path.exists(sock_path), 'Web application socket app.sock not created.'
    assert stat.S_ISSOCK(os.stat(sock_path).st_mode), 'app.sock is not a Unix domain socket.'
    direct_http_over_socket()


def test_backup_tarball():
    tar_path = '/home/user/backups/nginx_backup.tar.gz'
    assert os.path.isfile(tar_path), f'Backup tarball missing at {tar_path}'
    assert tarfile.is_tarfile(tar_path), 'Backup file is not a valid tar archive.'
    with tarfile.open(tar_path, 'r:gz') as tar:
        names = tar.getnames()
        assert any('nginx.conf' in name for name in names), 'Backup tarball does not contain nginx.conf.'


def test_backup_script_parses_current_fstab_and_archives_current_nginx():
    script = HOME / 'backup.py'
    assert script.is_file(), 'backup.py is missing.'
    fstab = HOME / 'fake_fstab'
    original_fstab = fstab.read_bytes()
    nonce = uuid.uuid4().hex
    mount = HOME / f'verifier_backup_{nonce}'
    marker = HOME / 'nginx' / f'verifier_{nonce}.txt'
    marker.write_text(nonce)
    try:
        fstab.write_text(
            '# verifier fstab\n'
            '/dev/sda1 / ext4 defaults 1 1\n'
            f'backup_drive {mount} ext4 defaults 0 0\n'
            'tmpfs /tmp tmpfs defaults 0 0\n'
        )
        result = run_as_user([sys.executable, str(script)], timeout=20)
        assert result.returncode == 0, f'backup.py failed: {result.stdout}\n{result.stderr}'
        archive = mount / 'nginx_backup.tar.gz'
        assert archive.is_file(), 'backup.py did not use the backup_drive mount point from fake_fstab.'
        assert tarfile.is_tarfile(archive)
        with tarfile.open(archive, 'r:gz') as tar:
            members = [m for m in tar.getmembers() if pathlib.PurePosixPath(m.name).name == marker.name]
            assert members, 'Backup does not contain a file added to the nginx directory before execution.'
            extracted = tar.extractfile(members[0])
            assert extracted is not None and extracted.read().decode() == nonce
    finally:
        fstab.write_bytes(original_fstab)
        try:
            marker.unlink()
        except FileNotFoundError:
            pass


def test_curl_result():
    curl_log_path = '/home/user/curl_result.log'
    assert os.path.isfile(curl_log_path), 'curl_result.log was not created.'
    with open(curl_log_path, 'r') as f:
        content = f.read()
    assert 'Hello World!' in content, 'curl_result.log does not contain the successful web app response.'


def test_live_nginx_request():
    subprocess.run(
        ['nginx', '-t', '-c', '/home/user/nginx/nginx.conf', '-p', '/home/user/nginx/'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
    )
    pid_file = HOME / 'nginx' / 'nginx.pid'
    assert pid_file.is_file(), 'Nginx PID file is missing.'
    pid_text = pid_file.read_text().strip()
    assert pid_text.isdigit()
    nginx_pid = int(pid_text)
    os.kill(nginx_pid, 0)
    cmd = proc_cmdline(nginx_pid)
    assert b'nginx' in cmd and b'/home/user/nginx/nginx.conf' in cmd, \
        'The configured Nginx master process is not running.'

    live = subprocess.run(
        ['curl', '--fail', '--silent', '--show-error', '--max-time', '5', 'http://127.0.0.1:8080'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
    ).stdout
    assert live == b'Hello World!', 'A live request through Nginx did not return the web application response.'
    assert (HOME / 'curl_result.log').read_bytes().strip() == live, \
        'curl_result.log does not match the live Nginx response.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
