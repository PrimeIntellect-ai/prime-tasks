#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import time
from collections import Counter

import pytest

HOME = '/home/user'
APPS = f'{HOME}/restored_apps'
RUN = f'{HOME}/run'


def proc_running(pid):
    try:
        with open(f'/proc/{pid}/stat') as f:
            state = f.read().split()[2]
        os.kill(pid, 0)
        return state != 'Z'
    except (OSError, ValueError, IndexError):
        return False


def read_pid(path):
    with open(path) as f:
        value = f.read().strip()
    assert value.isdigit(), f'{path} does not contain a numeric PID.'
    return int(value)


def wait_until(predicate, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


def curl(url, body=False):
    args = ['/usr/bin/curl', '-sS', '--max-time', '3']
    if not body:
        args += ['-o', '/dev/null', '-w', '%{http_code}']
    args.append(url)
    return subprocess.run(args, capture_output=True, text=True)


def test_db_sqlite_exists():
    path = '/home/user/restored_apps/db.sqlite'
    assert os.path.isfile(path), f'File {path} does not exist. App2 requires this to pass health checks.'


def test_manage_services_script():
    script_path = '/home/user/manage_services.sh'
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'

    # Preserve the original status assertion.
    result = subprocess.run(['bash', script_path, 'status'], capture_output=True)
    assert result.returncode == 0, f'{script_path} status returned non-zero exit code {result.returncode}. Ensure all apps are running and PID files exist.'

    original_pids = []
    for n in range(1, 4):
        pid_path = f'{RUN}/app{n}.pid'
        assert os.path.isfile(pid_path), f'Missing PID file {pid_path}.'
        pid = read_pid(pid_path)
        assert proc_running(pid), f'PID {pid} from {pid_path} is not running.'
        cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
        assert f'app{n}.py' in cmdline and 'python' in cmdline.lower(), f'{pid_path} does not identify the app{n} Python process: {cmdline!r}'
        original_pids.append(pid)

    stopped = subprocess.run(['bash', script_path, 'stop'], capture_output=True, text=True, timeout=15)
    assert stopped.returncode == 0, f'stop failed: {stopped.stdout}\n{stopped.stderr}'
    assert wait_until(lambda: all(not proc_running(pid) for pid in original_pids)), 'stop did not terminate all three app processes.'
    for n in range(1, 4):
        assert not os.path.exists(f'{RUN}/app{n}.pid'), f'stop did not remove app{n}.pid.'
    assert subprocess.run(['bash', script_path, 'status'], capture_output=True).returncode == 1, 'status must fail while the apps are stopped.'

    started = subprocess.run(['bash', script_path, 'start'], capture_output=True, text=True, timeout=15)
    assert started.returncode == 0, f'start failed: {started.stdout}\n{started.stderr}'
    assert wait_until(lambda: subprocess.run(['bash', script_path, 'status'], capture_output=True).returncode == 0), 'status did not succeed after start.'

    new_pids = set()
    for n in range(1, 4):
        pid_path = f'{RUN}/app{n}.pid'
        assert os.path.isfile(pid_path), f'start did not create {pid_path}.'
        pid = read_pid(pid_path)
        assert proc_running(pid), f'PID {pid} from {pid_path} is not running after start.'
        cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
        assert f'app{n}.py' in cmdline and 'python' in cmdline.lower(), f'{pid_path} does not identify app{n}: {cmdline!r}'
        new_pids.add(pid)
    assert len(new_pids) == 3, 'The three PID files must identify three distinct processes.'

    for n, port in enumerate((9001, 9002, 9003), 1):
        result = curl(f'http://127.0.0.1:{port}/ping', body=True)
        assert result.returncode == 0, f'app{n} is not reachable on port {port}: {result.stderr}'
        assert result.stdout == f'app{n} ok\n', f'Unexpected response from port {port}: {result.stdout!r}'


def test_haproxy_running():
    # Preserve the original process assertion.
    result = subprocess.run(['pgrep', 'haproxy'], capture_output=True)
    assert result.returncode == 0, 'haproxy process is not running.'

    cfg = '/home/user/haproxy.cfg'
    assert os.path.isfile(cfg), f'{cfg} does not exist.'
    valid = subprocess.run(['haproxy', '-c', '-f', cfg], capture_output=True, text=True)
    assert valid.returncode == 0, f'Invalid HAProxy configuration:\n{valid.stdout}\n{valid.stderr}'

    text = open(cfg).read()
    cleaned = '\n'.join(line.split('#', 1)[0].strip() for line in text.splitlines())
    assert re.search(r'(?mi)^\s*frontend\s+\S+', cleaned), 'HAProxy config has no frontend.'
    assert re.search(r'(?mi)^\s*bind\s+127\.0\.0\.1:8080(?:\s|$)', cleaned), 'Frontend must bind 127.0.0.1:8080.'
    assert re.search(r'(?mi)^\s*balance\s+roundrobin(?:\s|$)', cleaned), 'Backend must use roundrobin.'
    assert re.search(r'(?mi)^\s*(?:option\s+httpchk(?:\s+GET)?\s+/ping|http-check\s+send\s+.*\buri\s+/ping)', cleaned), 'Backend must perform HTTP health checks on /ping.'
    for n, port in enumerate((9001, 9002, 9003), 1):
        pattern = rf'(?mi)^\s*server\s+\S+\s+127\.0\.0\.1:{port}\s+[^\n]*\bcheck\b'
        assert re.search(pattern, cleaned), f'No checked backend server is configured for 127.0.0.1:{port}.'

    pid_path = f'{RUN}/haproxy.pid'
    assert os.path.isfile(pid_path), f'{pid_path} does not exist.'
    pid = read_pid(pid_path)
    assert proc_running(pid), f'HAProxy PID {pid} is not running.'
    cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
    assert 'haproxy' in cmdline and cfg in cmdline, f'PID file does not identify HAProxy running {cfg}: {cmdline!r}'

    # Reload the submitted configuration using the command required by the task,
    # so behavior is tested against the file currently on disk rather than stale state.
    os.kill(pid, signal.SIGTERM)
    if not wait_until(lambda: not proc_running(pid), timeout=5):
        os.kill(pid, signal.SIGKILL)
        assert wait_until(lambda: not proc_running(pid), timeout=3)
    launch = subprocess.run(['haproxy', '-f', cfg, '-p', pid_path, '-D'], capture_output=True, text=True)
    assert launch.returncode == 0, f'HAProxy could not start in daemon mode: {launch.stdout}\n{launch.stderr}'
    assert wait_until(lambda: os.path.isfile(pid_path) and proc_running(read_pid(pid_path))), 'HAProxy did not remain running.'

    def proxy_ready():
        r = curl('http://127.0.0.1:8080/ping', body=True)
        return r.returncode == 0 and r.stdout in {'app1 ok\n', 'app2 ok\n', 'app3 ok\n'}
    assert wait_until(proxy_ready, timeout=12), 'The proxy did not become healthy on 127.0.0.1:8080.'

    bodies = []
    for _ in range(12):
        r = curl('http://127.0.0.1:8080/ping', body=True)
        assert r.returncode == 0, f'Proxy request failed: {r.stderr}'
        bodies.append(r.stdout.strip())
    assert Counter(bodies) == Counter({'app1 ok': 4, 'app2 ok': 4, 'app3 ok': 4}), f'Proxy did not round-robin over all three healthy apps: {bodies}'


def test_proxy_results_log():
    log_path = '/home/user/proxy_results.log'
    script_path = '/home/user/verify_restore.sh'
    assert os.path.isfile(script_path), f'Verification script {script_path} does not exist.'

    # Instrument curl while executing the submitted script. This proves that the
    # twelve log entries are produced by twelve real requests to the proxy.
    real_curl = '/usr/bin/curl.verifier-real'
    curl_path = '/usr/bin/curl'
    calls = '/tmp/verify_restore_curl_calls'
    if os.path.exists(calls):
        os.unlink(calls)
    if os.path.exists(log_path):
        os.unlink(log_path)
    assert not os.path.exists(real_curl), f'Unexpected file {real_curl}.'
    os.rename(curl_path, real_curl)
    try:
        with open(curl_path, 'w') as f:
            f.write("#!/bin/bash\nprintf '%s\\034' \"$@\" >> /tmp/verify_restore_curl_calls\nprintf '\\n' >> /tmp/verify_restore_curl_calls\nexec /usr/bin/curl.verifier-real \"$@\"\n")
        os.chmod(curl_path, 0o755)
        run = subprocess.run(['bash', script_path], capture_output=True, text=True, timeout=30)
        assert run.returncode == 0, f'{script_path} failed: {run.stdout}\n{run.stderr}'
    finally:
        if os.path.exists(curl_path):
            os.unlink(curl_path)
        os.rename(real_curl, curl_path)

    assert os.path.isfile(calls), 'verify_restore.sh did not invoke curl.'
    invocations = []
    with open(calls) as f:
        for line in f:
            invocations.append([arg for arg in line.rstrip('\n').split('\x1c') if arg])
    assert len(invocations) == 12, f'Expected exactly 12 curl invocations, found {len(invocations)}.'
    target = 'http://127.0.0.1:8080/ping'
    for i, args in enumerate(invocations, 1):
        assert args.count(target) == 1, f'curl invocation {i} did not request exactly the proxy /ping URL: {args}'

    assert os.path.isfile(log_path), f'Log file {log_path} does not exist.'
    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]
    assert len(lines) == 12, f'Expected exactly 12 lines in {log_path}, found {len(lines)}.'
    for i, line in enumerate(lines):
        assert line == '200', f"Line {i+1} in {log_path} is '{line}', expected '200'."


def test_verify_restore_script_exists():
    script_path = '/home/user/verify_restore.sh'
    assert os.path.isfile(script_path), f'Verification script {script_path} does not exist.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
