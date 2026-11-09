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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time

import pytest
import requests

MONITOR = None


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return []


def ppid(pid):
    try:
        with open(f'/proc/{pid}/status') as f:
            for line in f:
                if line.startswith('PPid:'):
                    return int(line.split()[1])
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
    return None


def all_pids():
    return [int(x) for x in os.listdir('/proc') if x.isdigit() and int(x) > 1]


def is_backend(pid):
    c = cmdline(pid)
    return len(c) >= 2 and os.path.basename(c[0]).startswith('python3') and c[1] == '/app/app.py'


def is_monitor(pid):
    c = cmdline(pid)
    return len(c) >= 2 and os.path.basename(c[0]).startswith('python3') and c[1] == '/app/monitor.py'


def is_required_nginx(pid):
    c = cmdline(pid)
    if not c or os.path.basename(c[0]) != 'nginx':
        return False
    try:
        ci = c.index('-c')
        gi = c.index('-g')
        return c[ci + 1] == '/app/nginx.conf' and c[gi + 1] == 'daemon off;'
    except (ValueError, IndexError):
        return False


def direct_children(parent, predicate):
    return [pid for pid in all_pids() if ppid(pid) == parent and predicate(pid)]


def listener_pids(port):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(':', 1)[1], 16) == port and state == '0A':
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for pid in all_pids():
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    owners.add(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def nginx_family(master):
    family = {master}
    changed = True
    while changed:
        changed = False
        for pid in all_pids():
            if pid not in family and ppid(pid) in family:
                family.add(pid)
                changed = True
    return family


def kill_pids(pids):
    pids = {p for p in pids if p > 1 and p != os.getpid()}
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pids.discard(pid)
        deadline = time.time() + 2
        while pids and time.time() < deadline:
            pids = {p for p in pids if os.path.exists(f'/proc/{p}')}
            time.sleep(0.05)
        if not pids:
            break


def wait_for(fn, timeout=15, message='condition was not met'):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = fn()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    if last_error:
        raise AssertionError(f'{message}: {last_error}')
    raise AssertionError(message)


def healthy_response():
    try:
        r = requests.get('http://127.0.0.1:8080/health', timeout=2)
        return r if r.status_code == 200 and r.json() == {'health': 'good'} else None
    except Exception:
        return None


@pytest.fixture(scope='session', autouse=True)
def run_submitted_monitor():
    global MONITOR

    victims = set(listener_pids(8080)) | set(listener_pids(5000))
    for pid in all_pids():
        if is_monitor(pid) or is_backend(pid) or is_required_nginx(pid):
            victims.add(pid)
    kill_pids(victims)
    try:
        os.unlink('/run/nginx.pid')
    except FileNotFoundError:
        pass

    assert os.path.isfile('/app/monitor.py'), '/app/monitor.py is missing'
    MONITOR = subprocess.Popen(
        ['python3', '/app/monitor.py'],
        cwd='/app',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        wait_for(lambda: MONITOR.poll() is None, 2, '/app/monitor.py exited immediately')
        wait_for(lambda: direct_children(MONITOR.pid, is_backend), 15,
                 'the submitted monitor did not start python3 /app/app.py')
        wait_for(lambda: direct_children(MONITOR.pid, is_required_nginx), 15,
                 'the submitted monitor did not start nginx with the required command')
        wait_for(healthy_response, 15, 'the stack started by /app/monitor.py did not become healthy')
        yield
    finally:
        victims = set()
        if MONITOR is not None:
            victims.add(MONITOR.pid)
            victims.update(pid for pid in all_pids() if ppid(pid) == MONITOR.pid)
        victims |= set(listener_pids(8080)) | set(listener_pids(5000))
        kill_pids(victims)


def test_backups_exist():
    nginx_backup = '/app/backups/nginx.conf'
    app_backup = '/app/backups/app.py'

    assert os.path.isfile(nginx_backup), f'Backup {nginx_backup} is missing'
    assert os.path.isfile(app_backup), f'Backup {app_backup} is missing'

    with open(nginx_backup, 'r') as f:
        nginx_content = f.read()
    assert 'proxy_pass http://127.0.0.1:5001;' in nginx_content, 'Backup nginx.conf does not contain the original intentional error'

    with open(app_backup, 'r') as f:
        app_content = f.read()
    assert 'por=5000' in app_content, 'Backup app.py does not contain the original intentional typo'


def test_monitor_script_exists_and_is_running():
    assert os.path.isfile('/app/monitor.py'), '/app/monitor.py is missing'
    assert MONITOR.poll() is None, '/app/monitor.py is not continuously running'
    assert is_monitor(MONITOR.pid), 'the running monitor is not python3 /app/monitor.py'


def test_nginx_is_the_reverse_proxy_on_8080():
    masters = direct_children(MONITOR.pid, is_required_nginx)
    assert masters, 'nginx was not started by the submitted monitor with /app/nginx.conf and daemon off;'
    owners = listener_pids(8080)
    assert owners, 'nothing is listening on port 8080'
    assert any(owners & nginx_family(master) for master in masters), 'port 8080 is not being served by the monitored nginx process'


def test_web_application_responses():
    try:
        res = requests.get('http://127.0.0.1:8080/', timeout=5)
        assert res.status_code == 200, f'Expected status 200, got {res.status_code}'
        assert res.json() == {'status': 'ok'}, f"Expected {{'status': 'ok'}}, got {res.json()}"
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to http://127.0.0.1:8080/: {e}')

    try:
        res = requests.get('http://127.0.0.1:8080/health', timeout=5)
        assert res.status_code == 200, f'Expected status 200, got {res.status_code}'
        assert res.json() == {'health': 'good'}, f"Expected {{'health': 'good'}}, got {res.json()}"
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to http://127.0.0.1:8080/health: {e}')


def test_monitor_restarts_backend():
    old = direct_children(MONITOR.pid, is_backend)
    assert old, 'no backend child of the monitor was found'
    kill_pids(old)

    new_pid = wait_for(
        lambda: next((p for p in direct_children(MONITOR.pid, is_backend) if p not in old), None),
        10,
        'monitor did not restart the backend process',
    )
    assert new_pid not in old
    try:
        res = wait_for(healthy_response, 10, 'health endpoint did not recover after killing backend')
        assert res.status_code == 200
        assert res.json() == {'health': 'good'}
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect after killing backend: {e}')


def test_monitor_restarts_nginx():
    old = direct_children(MONITOR.pid, is_required_nginx)
    assert old, 'no required nginx child of the monitor was found'
    kill_pids(old)

    new_master = wait_for(
        lambda: next((p for p in direct_children(MONITOR.pid, is_required_nginx) if p not in old), None),
        10,
        'monitor did not restart nginx after it exited',
    )
    wait_for(lambda: listener_pids(8080) & nginx_family(new_master), 10,
             'restarted nginx did not take ownership of port 8080')
    wait_for(healthy_response, 10, 'application did not recover after nginx restart')


def test_non_200_health_check_restarts_backend():
    app_path = '/app/app.py'
    with open(app_path, 'rb') as f:
        original = f.read()
    original_mode = os.stat(app_path).st_mode

    unhealthy_app = b'''from http.server import BaseHTTPRequestHandler, HTTPServer\n\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        body = b'{"health":"bad"}'\n        self.send_response(503 if self.path == "/health" else 200)\n        self.send_header("Content-Type", "application/json")\n        self.send_header("Content-Length", str(len(body)))\n        self.end_headers()\n        self.wfile.write(body)\n    def log_message(self, *args):\n        pass\n\nHTTPServer.allow_reuse_address = True\nHTTPServer(("127.0.0.1", 5000), Handler).serve_forever()\n'''

    try:
        with open(app_path, 'wb') as f:
            f.write(unhealthy_app)
        os.chmod(app_path, original_mode)

        kill_pids(direct_children(MONITOR.pid, is_backend))
        seen = set()
        deadline = time.time() + 14
        while time.time() < deadline and len(seen) < 2:
            seen.update(direct_children(MONITOR.pid, is_backend))
            time.sleep(0.1)

        assert len(seen) >= 2, (
            'backend returned a persistent HTTP 503 health response, but the monitor '
            'did not kill and restart it'
        )
    finally:
        with open(app_path, 'wb') as f:
            f.write(original)
        os.chmod(app_path, original_mode)
        kill_pids(direct_children(MONITOR.pid, is_backend))
        wait_for(lambda: direct_children(MONITOR.pid, is_backend), 10,
                 'monitor did not restart the restored backend')
        wait_for(healthy_response, 12, 'stack did not recover after the health-check test')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
