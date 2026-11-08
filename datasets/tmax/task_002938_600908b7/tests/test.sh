#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import urllib.request
import urllib.error
import re
import subprocess
import signal
import socket
import stat
import pytest

LOG_RE = re.compile(r'^(\d+)\s*\|\s*9001:(UP|DOWN)\s*\|\s*9002:(UP|DOWN)\s*\|\s*9003:(UP|DOWN)$')


def read_log_entries():
    path = '/home/user/uptime.log'
    if not os.path.exists(path):
        return []
    with open(path, 'r') as f:
        lines = f.read().splitlines()
    entries = []
    for line in lines:
        match = LOG_RE.fullmatch(line)
        if match:
            entries.append((int(match.group(1)), match.group(2), match.group(3), match.group(4)))
    return entries


def monitor_pids():
    result = []
    expected = os.path.realpath('/home/user/sre_monitor')
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            if os.path.realpath(f'/proc/{name}/exe') == expected:
                result.append(int(name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return result


def test_nginx_running():
    """Ensure Nginx is running and pid file exists."""
    pid_file = '/home/user/nginx/nginx.pid'
    assert os.path.exists(pid_file), f"Nginx PID file missing at {pid_file}"
    with open(pid_file) as f:
        pid = int(f.read().strip())
    os.kill(pid, 0)

    # Check if port 8080 is listening
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(('127.0.0.1', 8080))
        assert result == 0, "Nginx is not listening on port 8080."


def test_nginx_configuration_files():
    nginx_conf = '/home/user/nginx/nginx.conf'
    upstream_conf = '/home/user/nginx/upstream.conf'
    assert os.path.isfile(nginx_conf), f"Missing {nginx_conf}"
    assert os.path.isfile(upstream_conf), f"Missing {upstream_conf}"
    with open(nginx_conf) as f:
        content = f.read()
    assert re.search(r'\blisten\s+8080\s*;', content), "nginx.conf does not listen on port 8080"
    assert '/home/user/nginx/upstream.conf' in content, "nginx.conf does not include the required upstream.conf"
    assert re.search(r'\bpid\s+/home/user/nginx/nginx\.pid\s*;', content), "nginx.conf does not use the required PID path"
    subprocess.run(['nginx', '-t', '-c', nginx_conf], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_nginx_proxy():
    """Ensure Nginx reverse proxy is working and loading the upstream conf."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/health")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode('utf-8').strip()
            assert body == "OK", f"Expected response body 'OK', got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx proxy on 8080: {e}")


def test_monitor_artifacts_and_process():
    source = '/home/user/sre_monitor.cpp'
    binary = '/home/user/sre_monitor'
    assert os.path.isfile(source), f"Monitor source missing at {source}"
    assert os.path.getsize(source) > 0, "Monitor source is empty"
    assert os.path.isfile(binary), f"Compiled monitor missing at {binary}"
    assert os.access(binary, os.X_OK), "Compiled monitor is not executable"
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "sre_monitor is not a compiled ELF executable"
    assert monitor_pids(), "The compiled /home/user/sre_monitor executable is not running"


def test_uptime_log_format():
    """Check that uptime.log exists and contains the correct format."""
    log_file = '/home/user/uptime.log'
    assert os.path.exists(log_file), f"Log file missing at {log_file}"

    with open(log_file, 'r') as f:
        lines = f.read().strip().split('\n')
        assert len(lines) > 0, "uptime.log is empty"
        last_line = lines[-1]
        assert re.match(r'^\d+\s*\|\s*9001:(UP|DOWN)\s*\|\s*9002:(UP|DOWN)\s*\|\s*9003:(UP|DOWN)$', last_line), \
            f"Log format is incorrect. Got: '{last_line}'"


def test_initial_health_and_two_second_checks():
    """All initially healthy servers must be logged and configured on a continuing two-second cadence."""
    upstream_file = '/home/user/nginx/upstream.conf'
    with open(upstream_file) as f:
        content = f.read()
    for port in (9001, 9002, 9003):
        assert re.search(rf'\bserver\s+127\.0\.0\.1:{port}\s*;', content), f"Healthy port {port} is absent from upstream.conf"

    baseline = len(read_log_entries())
    arrivals = []
    seen = baseline
    deadline = time.monotonic() + 6.4
    while time.monotonic() < deadline:
        entries = read_log_entries()
        if len(entries) > seen:
            now = time.monotonic()
            for entry in entries[seen:]:
                arrivals.append((now, entry))
            seen = len(entries)
        time.sleep(0.1)

    assert 3 <= len(arrivals) <= 4, f"Expected checks every two seconds; observed {len(arrivals)} new log records in 6.4 seconds"
    for _, entry in arrivals:
        assert entry[1:] == ('UP', 'UP', 'UP'), f"Initially healthy backends were not all recorded UP: {entry}"
        assert abs(int(time.time()) - entry[0]) < 15, "Log timestamp is not a current epoch timestamp"
    for (first_time, _), (second_time, _) in zip(arrivals, arrivals[1:]):
        interval = second_time - first_time
        assert 1.4 <= interval <= 2.8, f"Health checks are not occurring every two seconds (observed {interval:.2f}s)"


def test_dynamic_update():
    """Kill backend 9002 and verify the running monitor updates config, logs, and sends SIGHUP."""
    pid_file = '/home/user/nginx/nginx.pid'
    upstream_file = '/home/user/nginx/upstream.conf'
    marker = '/tmp/monitor_hup_received'
    ready = '/tmp/hup_catcher_ready'
    for path in (marker, ready):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    with open(pid_file, 'rb') as f:
        original_pid_data = f.read()
    original_stat = os.stat(pid_file)

    catcher_code = r'''
import os, signal, time
marker, ready = os.environ['MARKER'], os.environ['READY']
def hup(signum, frame):
    with open(marker, 'a') as f:
        f.write('HUP\n')
signal.signal(signal.SIGHUP, hup)
open(ready, 'w').close()
while True:
    time.sleep(1)
'''
    catcher = subprocess.Popen(
        ['python3', '-c', catcher_code],
        env={**os.environ, 'MARKER': marker, 'READY': ready}
    )
    stopped = []
    try:
        deadline = time.time() + 2
        while not os.path.exists(ready) and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.exists(ready), "Could not start SIGHUP catcher"

        temp_pid = pid_file + '.verifier'
        with open(temp_pid, 'w') as f:
            f.write(str(catcher.pid) + '\n')
        os.replace(temp_pid, pid_file)

        # A stable healthy list must not cause unconditional reload signals.
        time.sleep(2.5)
        assert not os.path.exists(marker), "Monitor sent SIGHUP even though the healthy-server list did not change"

        stopped = monitor_pids()
        assert stopped, "The compiled monitor stopped running"
        for pid in stopped:
            os.kill(pid, signal.SIGSTOP)
        time.sleep(0.2)

        before_entries = len(read_log_entries())
        with open(upstream_file) as f:
            assert '9002' in f.read(), "Port 9002 was not present before its backend was killed"

        # Find and kill the python process listening on 9002.
        try:
            ps_output = subprocess.check_output(['ps', 'aux']).decode()
            killed = False
            for line in ps_output.splitlines():
                if 'server.py 9002' in line and 'grep' not in line:
                    pid = int(line.split()[1])
                    os.kill(pid, signal.SIGKILL)
                    killed = True
            assert killed, "Could not find backend process for port 9002 to kill."
        except subprocess.CalledProcessError:
            pytest.fail("Failed to run ps command.")

        # While the submitted executable is stopped, no helper should perform its work.
        time.sleep(2.7)
        assert len(read_log_entries()) == before_entries, "Health checks continued while the submitted monitor executable was stopped"
        with open(upstream_file) as f:
            assert '9002' in f.read(), "upstream.conf changed while the submitted monitor executable was stopped"
        assert not os.path.exists(marker), "SIGHUP was sent while the submitted monitor executable was stopped"

        for pid in stopped:
            os.kill(pid, signal.SIGCONT)
        stopped = []

        # Wait for the monitor to detect the failure (checks every 2s).
        time.sleep(3.5)

        # 1. Verify uptime.log registers 9002:DOWN.
        log_file = '/home/user/uptime.log'
        assert os.path.exists(log_file), f"Log file missing at {log_file}"
        with open(log_file, 'r') as f:
            lines = f.read().strip().split('\n')
            last_line = lines[-1]
            assert "9002:DOWN" in last_line, f"Expected 9002:DOWN in log after killing it. Got: '{last_line}'"
            match = LOG_RE.fullmatch(last_line)
            assert match and match.group(2) == 'UP' and match.group(3) == 'DOWN' and match.group(4) == 'UP', \
                f"Monitor did not derive all backend states correctly: '{last_line}'"

        # 2. Verify upstream.conf no longer contains 9002.
        assert os.path.exists(upstream_file), f"Upstream conf missing at {upstream_file}"
        with open(upstream_file, 'r') as f:
            content = f.read()
            assert '9002' not in content, f"Port 9002 should have been removed from {upstream_file}"
            assert '9001' in content and '9003' in content, "Healthy ports disappeared from upstream.conf"

        # Verify the real configuration change caused a SIGHUP to the PID read from nginx.pid.
        assert os.path.exists(marker), "Monitor did not send SIGHUP after the healthy-server list changed"

        # 3. Verify curl to 8080/health still succeeds (served by 9001 or 9003).
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/health")
            with urllib.request.urlopen(req, timeout=2) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                body = response.read().decode('utf-8').strip()
                assert body == "OK", f"Expected response body 'OK', got '{body}'"
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to Nginx proxy on 8080 after backend failure: {e}")
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        temp_pid = pid_file + '.restore'
        with open(temp_pid, 'wb') as f:
            f.write(original_pid_data)
        os.chmod(temp_pid, stat.S_IMODE(original_stat.st_mode))
        try:
            os.chown(temp_pid, original_stat.st_uid, original_stat.st_gid)
        except PermissionError:
            pass
        os.replace(temp_pid, pid_file)
        catcher.terminate()
        try:
            catcher.wait(timeout=2)
        except subprocess.TimeoutExpired:
            catcher.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
