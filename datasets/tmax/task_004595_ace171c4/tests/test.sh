#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

HOME = Path('/home/user')
MANAGE = HOME / 'manage_service.sh'
DEPLOY = HOME / 'deploy.sh'
PIDFILE = HOME / 'app.pid'
SOCKET = HOME / 'app.sock'
NGINX_PID = HOME / 'nginx/nginx.pid'
USER_UID = pwd.getpwnam('user').pw_uid


def run_user(argv, timeout=20, env=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        ['runuser', '-u', 'user', '--'] + list(argv),
        cwd='/home/user', env=merged, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )


def read_pid(path):
    try:
        return int(Path(path).read_text().strip())
    except Exception:
        return None


def alive(pid):
    if not pid or not Path(f'/proc/{pid}').exists():
        return False
    try:
        state = Path(f'/proc/{pid}/stat').read_text().split()[2]
        return state != 'Z'
    except Exception:
        return False


def wait_dead(pid, timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        if not alive(pid):
            return True
        time.sleep(0.05)
    return not alive(pid)


def stop_existing_backend():
    pids = set()
    old = read_pid(PIDFILE)
    if old:
        pids.add(old)
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / 'cmdline').read_bytes().replace(b'\0', b' ')
            if b'/home/user/app/backend.py' in cmd:
                pids.add(int(entry.name))
        except Exception:
            pass
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for pid in pids:
        wait_dead(pid)
    PIDFILE.unlink(missing_ok=True)
    SOCKET.unlink(missing_ok=True)


def stop_existing_nginx():
    pids = set()
    pid = read_pid(NGINX_PID)
    if pid:
        pids.add(pid)
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / 'cmdline').read_bytes().replace(b'\0', b' ')
            if b'nginx: master process' in cmd and b'/home/user/nginx' in cmd:
                pids.add(int(entry.name))
        except Exception:
            pass
    for pid in pids:
        try:
            os.kill(pid, signal.SIGQUIT)
        except ProcessLookupError:
            pass
    for pid in pids:
        wait_dead(pid)
    NGINX_PID.unlink(missing_ok=True)


def unix_http_get(path='/api'):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    client.connect(str(SOCKET))
    client.sendall(f'GET {path} HTTP/1.0\r\nHost: localhost\r\n\r\n'.encode())
    chunks = []
    while True:
        data = client.recv(4096)
        if not data:
            break
        chunks.append(data)
    client.close()
    raw = b''.join(chunks)
    head, body = raw.split(b'\r\n\r\n', 1)
    assert b' 200 ' in head.splitlines()[0], head
    return json.loads(body.decode())


def assert_backend_process(pid):
    assert alive(pid), f'Backend PID {pid} is not running.'
    assert os.stat(f'/proc/{pid}').st_uid == USER_UID, 'Backend was not run as the standard user.'
    cmd = Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ')
    assert b'python3' in cmd and b'/home/user/app/backend.py' in cmd, 'PID file does not identify the required Python backend.'
    env = Path(f'/proc/{pid}/environ').read_bytes().split(b'\0')
    assert b'APP_SOCK=/home/user/app.sock' in env, 'Backend was not launched with the required APP_SOCK value.'
    assert SOCKET.exists() and stat.S_ISSOCK(SOCKET.stat().st_mode), 'The backend did not create the required UNIX socket.'
    data = unix_http_get()
    assert data.get('status') == 'ok'
    assert data.get('message') == 'Migration Complete'


def test_nginx_config_updated():
    config_path = '/home/user/nginx/nginx.conf'
    assert os.path.isfile(config_path), f'Nginx configuration {config_path} is missing.'
    content = Path(config_path).read_text()
    assert 'server unix:/home/user/app.sock;' in content, 'Nginx config was not updated to point to unix:/home/user/app.sock.'
    assert 'server unix:/tmp/legacy.sock;' not in content, 'Nginx config still contains the legacy socket path.'

    expected = '''worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;
events { worker_connections 1024; }
http {
 client_body_temp_path /home/user/nginx/client_body_temp;
 proxy_temp_path /home/user/nginx/proxy_temp;
 fastcgi_temp_path /home/user/nginx/fastcgi_temp;
 uwsgi_temp_path /home/user/nginx/uwsgi_temp;
 scgi_temp_path /home/user/nginx/scgi_temp;
 access_log /home/user/nginx/logs/access.log;
 upstream backend { server unix:/home/user/app.sock; }
 server {
  listen 8080;
  server_name localhost;
  location / {
   proxy_pass http://backend;
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
  }
 }
}'''
    def tokens(text):
        text = re.sub(r'#.*', '', text)
        return re.findall(r'[{};]|[^\s{};]+', text)
    assert tokens(content) == tokens(expected), 'Nginx settings other than the required socket replacement were modified.'
    checked = run_user(['nginx', '-t', '-p', '/home/user/nginx', '-c', '/home/user/nginx/nginx.conf'])
    assert checked.returncode == 0, checked.stderr


def test_manage_service_script_exists_and_executable():
    script_path = '/home/user/manage_service.sh'
    assert os.path.isfile(script_path), f'Service manager script {script_path} is missing.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Service manager script {script_path} is not executable.'


def test_manage_service_lifecycle():
    stop_existing_backend()
    for args in ([], ['bogus'], ['start', 'extra']):
        result = run_user([str(MANAGE)] + args)
        assert result.returncode != 0, f'manage_service.sh accepted invalid arguments: {args}'

    started = run_user([str(MANAGE), 'start'])
    assert started.returncode == 0, started.stdout + started.stderr
    first_pid = read_pid(PIDFILE)
    assert first_pid, 'start did not write /home/user/app.pid.'
    assert_backend_process(first_pid)

    restarted = run_user([str(MANAGE), 'restart'])
    assert restarted.returncode == 0, restarted.stdout + restarted.stderr
    second_pid = read_pid(PIDFILE)
    assert second_pid and second_pid != first_pid, 'restart did not replace the backend process.'
    assert wait_dead(first_pid), 'restart did not terminate the old backend process.'
    assert_backend_process(second_pid)

    stopped = run_user([str(MANAGE), 'stop'])
    assert stopped.returncode == 0, stopped.stdout + stopped.stderr
    assert wait_dead(second_pid), 'stop did not terminate the backend process.'
    assert not PIDFILE.exists(), 'stop did not remove /home/user/app.pid.'
    assert not SOCKET.exists(), 'stop did not remove /home/user/app.sock.'


def test_deploy_script_exists_and_executable():
    script_path = '/home/user/deploy.sh'
    assert os.path.isfile(script_path), f'Deployment script {script_path} is missing.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Deployment script {script_path} is not executable.'


def test_deploy_executes_pipeline_in_order_and_supports_reload():
    stop_existing_backend()
    stop_existing_nginx()
    log = HOME / 'migration.log'
    log.write_text('preserve-existing-log\n')
    os.chown(log, USER_UID, pwd.getpwnam('user').pw_gid)

    original = MANAGE.read_bytes()
    original_mode = stat.S_IMODE(MANAGE.stat().st_mode)
    backup = HOME / '.manage_service.verifier_original'
    trace = Path(tempfile.mktemp(prefix='deploy-trace-', dir='/tmp'))
    wrappers = Path(tempfile.mkdtemp(prefix='deploy-path-', dir='/tmp'))
    os.chmod(wrappers, 0o755)

    backup.write_bytes(original)
    os.chmod(backup, original_mode)
    os.chown(backup, USER_UID, pwd.getpwnam('user').pw_gid)
    MANAGE.write_text(f'''#!/bin/bash
printf 'manage:%s\\n' "$*" >> {trace}
exec {backup} "$@"
''')
    os.chmod(MANAGE, 0o755)

    real_commands = {'nginx': '/usr/sbin/nginx', 'sleep': '/usr/bin/sleep', 'curl': '/usr/bin/curl'}
    for name, real in real_commands.items():
        wrapper = wrappers / name
        wrapper.write_text(f'''#!/bin/bash
printf '{name}:%s\\n' "$*" >> {trace}
exec {real} "$@"
''')
        os.chmod(wrapper, 0o755)

    env = {'PATH': str(wrappers) + ':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'}
    try:
        first = run_user([str(DEPLOY)], timeout=30, env=env)
        assert first.returncode == 0, first.stdout + first.stderr
        first_master = read_pid(NGINX_PID)
        assert first_master and alive(first_master), 'deploy.sh did not start Nginx.'

        second = run_user([str(DEPLOY)], timeout=30, env=env)
        assert second.returncode == 0, second.stdout + second.stderr
        second_master = read_pid(NGINX_PID)
        assert second_master == first_master and alive(second_master), 'deploy.sh did not reload the already-running Nginx master.'
    finally:
        MANAGE.write_bytes(original)
        os.chmod(MANAGE, original_mode)
        backup.unlink(missing_ok=True)

    lines = trace.read_text().splitlines() if trace.exists() else []
    manage_positions = [i for i, line in enumerate(lines) if line == 'manage:restart']
    assert len(manage_positions) >= 2, 'deploy.sh did not call /home/user/manage_service.sh restart on each deployment.'

    start_cmd = 'nginx:-p /home/user/nginx -c /home/user/nginx/nginx.conf'
    reload_cmd = 'nginx:-p /home/user/nginx -s reload'
    assert start_cmd in lines, 'deploy.sh did not use the required Nginx start command.'
    assert reload_cmd in lines, 'deploy.sh did not use the required Nginx reload command when Nginx was running.'

    for manage_pos, nginx_cmd in ((manage_positions[0], start_cmd), (manage_positions[1], reload_cmd)):
        nginx_pos = lines.index(nginx_cmd, manage_pos + 1)
        sleep_pos = next((i for i in range(nginx_pos + 1, len(lines)) if lines[i] == 'sleep:2'), None)
        assert sleep_pos is not None, 'deploy.sh did not sleep for 2 seconds after starting or reloading Nginx.'
        curl_pos = next((i for i in range(sleep_pos + 1, len(lines)) if lines[i].startswith('curl:') and 'http://localhost:8080/api' in lines[i]), None)
        assert curl_pos is not None, 'deploy.sh did not run the required curl health check after the sleep.'

    content = log.read_text()
    assert content.startswith('preserve-existing-log\n'), 'deploy.sh overwrote migration.log instead of appending.'
    assert content.count('Migration Complete') >= 2, 'The deployment health checks were not appended to migration.log.'


def test_migration_log_contains_success_message():
    log_path = '/home/user/migration.log'
    assert os.path.isfile(log_path), f'Log file {log_path} is missing. Did you execute deploy.sh?'
    content = Path(log_path).read_text()
    assert 'Migration Complete' in content, f'Log file {log_path} does not contain the expected success message.'


def test_services_are_running_and_accessible():
    assert SOCKET.exists(), f'Socket {SOCKET} is missing. The backend service may not be running.'
    assert PIDFILE.is_file(), f'PID file {PIDFILE} is missing. The backend service may not have been started correctly.'
    assert_backend_process(read_pid(PIDFILE))
    try:
        req = urllib.request.Request('http://localhost:8080/api')
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.status == 200, f'Expected HTTP 200, got {response.status}'
            assert 'nginx' in response.headers.get('Server', '').lower(), 'Port 8080 is not being served through Nginx.'
            data = json.loads(response.read().decode())
            assert data.get('status') == 'ok', 'API did not return status: ok'
            assert data.get('message') == 'Migration Complete', 'API did not return the expected message'
    except Exception as e:
        assert False, f'Failed to access the API via Nginx at http://localhost:8080/api. Error: {e}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
