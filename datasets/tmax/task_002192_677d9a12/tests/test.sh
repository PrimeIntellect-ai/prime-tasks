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
import time
import uuid
import requests
import pytest

LOG_DIR = '/home/user/logs'
BASE_LOG = os.path.join(LOG_DIR, 'dashboard.log')


def proc_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def proc_ppid(pid):
    try:
        with open(f'/proc/{pid}/stat') as f:
            return int(f.read().split()[3])
    except (OSError, ValueError, IndexError):
        return None


def supervisor_pid():
    matches = []
    for name in os.listdir('/proc'):
        if name.isdigit() and '/home/user/supervisor.py' in proc_cmdline(int(name)):
            matches.append(int(name))
    assert matches, 'No running /home/user/supervisor.py process found'
    return max(matches)


def direct_children(pid):
    result = []
    for name in os.listdir('/proc'):
        if name.isdigit() and proc_ppid(int(name)) == pid:
            result.append(int(name))
    return result


def dashboard_child(pid, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        children = direct_children(pid)
        if children:
            return max(children)
        time.sleep(0.05)
    pytest.fail('Supervisor has no dashboard subprocess')


def inject_fd(pid, fd, payload):
    path = f'/proc/{pid}/fd/{fd}'
    try:
        out = os.open(path, os.O_WRONLY)
    except OSError as e:
        pytest.fail(f'Could not write test output through dashboard fd {fd}: {e}')
    try:
        view = memoryview(payload)
        while view:
            written = os.write(out, view[:4096])
            assert written > 0
            view = view[written:]
    finally:
        os.close(out)


def log_files():
    paths = [BASE_LOG]
    paths.extend(os.path.join(LOG_DIR, f'dashboard.log.{i}') for i in range(1, 10))
    return [p for p in paths if os.path.isfile(p)]


def logs_contain(marker):
    needle = marker.encode()
    for path in log_files():
        try:
            with open(path, 'rb') as f:
                if needle in f.read():
                    return True
        except OSError:
            pass
    return False


def rotation_fingerprint():
    path = BASE_LOG + '.1'
    try:
        st = os.stat(path)
        return (st.st_ino, st.st_mtime_ns, st.st_size)
    except OSError:
        return None


def wait_for_rotation(previous, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = rotation_fingerprint()
        if current is not None and current != previous:
            return current
        time.sleep(0.05)
    pytest.fail('Log did not rotate after exceeding 10240 bytes')


def test_supervisor_exists():
    assert os.path.isfile('/home/user/supervisor.py'), 'Supervisor script not found at /home/user/supervisor.py'
    assert supervisor_pid(), 'Supervisor script is not running'


def test_log_dir_exists():
    assert os.path.isdir('/home/user/logs'), 'Logs directory not found at /home/user/logs'


def test_health_endpoint():
    try:
        resp = requests.get('http://127.0.0.1:8080/health', timeout=2)
        assert resp.status_code == 200, f'Expected 200, got {resp.status_code}'
        assert resp.json() == {'status': 'ok'}, f"Expected {{'status': 'ok'}}, got {resp.json()}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to /health: {e}')


def test_costs_endpoint():
    try:
        resp = requests.get('http://127.0.0.1:8080/costs', timeout=2)
        assert resp.status_code == 200, f'Expected 200, got {resp.status_code}'
        data = resp.json()
        assert 'total_optimized_cost' in data, "Missing 'total_optimized_cost' in response"
        assert float(data['total_optimized_cost']) == 1245.0, f"Expected 1245.0, got {data['total_optimized_cost']}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to /costs: {e}')


def test_crash_and_restart():
    sup = supervisor_pid()
    old_child = dashboard_child(sup)
    started = time.monotonic()
    try:
        requests.get('http://127.0.0.1:8080/crash', timeout=0.7)
    except requests.exceptions.RequestException:
        pass

    deadline = started + 3.0
    last_error = None
    while time.monotonic() < deadline:
        try:
            resp = requests.get('http://127.0.0.1:8080/health', timeout=0.15)
            children = direct_children(sup)
            if (resp.status_code == 200 and resp.json() == {'status': 'ok'} and
                    children and old_child not in children):
                return
        except (requests.exceptions.RequestException, ValueError) as e:
            last_error = e
        time.sleep(0.05)
    pytest.fail(f'Service did not restart with a new subprocess within 3 seconds: {last_error}')


def test_log_rotation_and_capture():
    sup = supervisor_pid()
    child = dashboard_child(sup)

    # Remove any pre-created evidence and begin from an empty active log.
    os.makedirs(LOG_DIR, exist_ok=True)
    if not os.path.exists(BASE_LOG):
        open(BASE_LOG, 'ab').close()
    with open(BASE_LOG, 'wb'):
        pass
    for i in range(1, 10):
        try:
            os.unlink(os.path.join(LOG_DIR, f'dashboard.log.{i}'))
        except FileNotFoundError:
            pass
    time.sleep(0.3)
    for i in range(1, 10):
        try:
            os.unlink(os.path.join(LOG_DIR, f'dashboard.log.{i}'))
        except FileNotFoundError:
            pass

    stdout_marker = 'STDOUT_' + uuid.uuid4().hex
    stderr_marker = 'STDERR_' + uuid.uuid4().hex
    inject_fd(child, 1, (stdout_marker + '\n').encode())
    inject_fd(child, 2, (stderr_marker + '\n').encode())
    inject_fd(child, 1, (('A' * 8000) + '\n').encode())

    # Output below 10 KB must not rotate merely because a backup was pre-created.
    time.sleep(0.6)
    assert not os.path.exists(BASE_LOG + '.1'), 'Log rotated before reaching the 10240-byte threshold'

    first = rotation_fingerprint()
    inject_fd(child, 1, (('B' * 3000) + '\n').encode())
    first = wait_for_rotation(first)

    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and not (logs_contain(stdout_marker) and logs_contain(stderr_marker)):
        time.sleep(0.05)
    assert logs_contain(stdout_marker), 'Dashboard standard output was not captured in dashboard logs'
    assert logs_contain(stderr_marker), 'Dashboard standard error was not captured in dashboard logs'

    # Force three more genuine rotations and verify that only three backups survive.
    previous = first
    for n in range(3):
        marker = f'ROTATION_{n}_{uuid.uuid4().hex}'
        inject_fd(child, 1, ((marker + '_') * 450 + '\n').encode())
        previous = wait_for_rotation(previous)
        assert logs_contain(marker), f'Injected output for rotation {n + 2} was not logged'

    assert os.path.isfile(BASE_LOG), 'Base log file /home/user/logs/dashboard.log not found'
    assert os.path.isfile(BASE_LOG + '.1'), 'Log rotation failed, dashboard.log.1 was not created'
    backups = [p for p in log_files() if p != BASE_LOG]
    assert len(backups) <= 3, f'Expected at most 3 backup logs, found {backups}'
    assert not any(os.path.exists(BASE_LOG + f'.{i}') for i in range(4, 10)), 'Log rotation retained more than 3 backups'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
