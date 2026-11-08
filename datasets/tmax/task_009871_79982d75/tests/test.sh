#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import stat
import subprocess
import time
import uuid

WATCHDOG = '/home/user/watchdog.py'
API = '/home/user/flaky_api.py'
LOG = '/home/user/watchdog.log'
CONF = '/home/user/watchrotate.conf'

MOCK_API = r'''import http.server
import os
import sys
import time

mode, ready, evidence = sys.argv[1:4]

class Server(http.server.HTTPServer):
    allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(evidence, 'a') as f:
            f.write(self.command + ' ' + self.path + '\n')
        if mode == 'timeout':
            time.sleep(6)
            self.send_response(200)
        elif mode == 'error':
            self.send_response(418)
        else:
            self.send_response(200)
        self.end_headers()
        try:
            self.wfile.write(b'probe')
        except BrokenPipeError:
            pass

    def log_message(self, *args):
        pass

server = Server(('127.0.0.1', 8080), Handler)
with open(ready, 'w') as f:
    f.write('ready')
server.serve_forever()
'''


def test_watchdog_artifact_exists_and_is_executable():
    assert os.path.isfile(WATCHDOG), 'watchdog.py is missing.'
    assert os.access(WATCHDOG, os.X_OK), 'watchdog.py is not executable.'


def test_crontab_configured():
    """Verify that the watchdog is scheduled in the user's crontab to run every minute."""
    result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert result.returncode == 0, 'Failed to read crontab. Is it configured?'
    cron_jobs = result.stdout.strip().split('\n')

    found = False
    for job in cron_jobs:
        if job.startswith('#'):
            continue
        if '/usr/bin/python3 /home/user/watchdog.py' in job:
            parts = job.split()
            if parts[:5] == ['*', '*', '*', '*', '*']:
                found = True
                break

    assert found, 'Crontab does not contain the correct entry to run the watchdog every minute.'


def test_logrotate_configured():
    """Verify the logrotate configuration file contains the required directives."""
    assert os.path.isfile(CONF), f'Logrotate config {CONF} is missing.'
    with open(CONF, 'r') as f:
        content = f.read()

    assert '/home/user/watchdog.log' in content, 'Logrotate config missing the target log file.'
    assert re.search(r'\bdaily\b', content), "Logrotate config missing 'daily' directive."
    assert re.search(r'\brotate\s+5\b', content), "Logrotate config missing 'rotate 5' directive."
    assert re.search(r'\bcompress\b', content), "Logrotate config missing 'compress' directive."
    assert re.search(r'\bmissingok\b', content), "Logrotate config missing 'missingok' directive."
    assert re.search(r'\bcreate\s+(0?644)\b', content), "Logrotate config missing 'create 0644' directive."


def get_flaky_api_pids():
    result = subprocess.run(['pgrep', '-f', '[f]laky_api.py'], capture_output=True, text=True)
    return [p for p in result.stdout.strip().splitlines() if p]


def get_flaky_api_pid():
    pids = get_flaky_api_pids()
    return pids[0] if pids else None


def kill_flaky_api():
    subprocess.run(['pkill', '-f', '[f]laky_api.py'], check=False)
    deadline = time.time() + 3
    while time.time() < deadline and get_flaky_api_pid() is not None:
        time.sleep(0.1)


def run_watchdog():
    return subprocess.run(
        ['/usr/bin/python3', WATCHDOG], capture_output=True, text=True, timeout=8
    )


def wait_for_service(timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = get_flaky_api_pid()
        if pid is not None:
            return pid
        time.sleep(0.1)
    return None


def check_log_for_reason(reason):
    assert os.path.isfile(LOG), f'Log file {LOG} not found.'
    with open(LOG, 'r') as f:
        lines = f.readlines()
    if not lines:
        return False
    last_line = lines[-1].strip()
    pattern = rf'^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] RESTART triggered\. Reason: {reason}$'
    return bool(re.match(pattern, last_line))


def log_bytes():
    if not os.path.exists(LOG):
        return None
    with open(LOG, 'rb') as f:
        return f.read()


def start_mock_api(mode):
    """Run alternate loaded code under the exact required flaky_api.py command."""
    kill_flaky_api()
    token = uuid.uuid4().hex
    ready = f'/tmp/mock-ready-{token}'
    evidence = f'/tmp/mock-evidence-{token}'
    with open(API, 'rb') as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(API).st_mode)
    try:
        with open(API, 'w') as f:
            f.write(MOCK_API)
        os.chmod(API, original_mode)
        proc = subprocess.Popen(['/usr/bin/python3', API, mode, ready, evidence])
        deadline = time.time() + 4
        while time.time() < deadline and not os.path.exists(ready):
            if proc.poll() is not None:
                raise AssertionError('Mock health service exited before binding port 8080.')
            time.sleep(0.05)
        assert os.path.exists(ready), 'Mock health service did not bind port 8080.'
    finally:
        with open(API, 'wb') as f:
            f.write(original)
        os.chmod(API, original_mode)
    return proc, evidence


def read_evidence(path):
    if not os.path.exists(path):
        return ''
    with open(path) as f:
        return f.read()


def test_watchdog_healthy_performs_get_and_does_nothing():
    """A real 200 response must be queried and must not trigger healing or logging."""
    proc, evidence = start_mock_api('healthy')
    old_pid = str(proc.pid)
    before = log_bytes()
    try:
        result = run_watchdog()
        assert result.returncode == 0, 'Watchdog did not exit cleanly for a healthy service.'
        time.sleep(0.3)
        assert read_evidence(evidence).splitlines() == ['GET /health'], \
            'Watchdog did not make an HTTP GET request to /health.'
        assert proc.poll() is None, 'Watchdog terminated a healthy service.'
        assert old_pid in get_flaky_api_pids(), 'Healthy service PID changed.'
        assert log_bytes() == before, 'Watchdog logged a restart for a healthy service.'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        kill_flaky_api()


def test_watchdog_down_behavior():
    """Verify watchdog restarts the service when it is DOWN."""
    kill_flaky_api()
    assert get_flaky_api_pid() is None, 'Failed to kill flaky_api.py for testing.'

    result = run_watchdog()
    assert result.returncode == 0, 'Watchdog did not exit cleanly for DOWN.'
    assert wait_for_service() is not None, 'Watchdog failed to restart the service when DOWN.'
    assert check_log_for_reason('DOWN'), 'Watchdog log does not contain the correct DOWN reason format.'


def test_watchdog_timeout_behavior():
    """Verify timeout classification using an unadvertised delayed HTTP response."""
    proc, evidence = start_mock_api('timeout')
    old_pid = str(proc.pid)
    started = time.monotonic()
    result = run_watchdog()
    elapsed = time.monotonic() - started

    assert result.returncode == 0, 'Watchdog did not exit cleanly for TIMEOUT.'
    assert read_evidence(evidence).splitlines() == ['GET /health'], \
        'Watchdog did not GET /health during the timeout test.'
    assert 1.5 <= elapsed < 4.0, \
        f'Watchdog did not enforce an approximately 2-second timeout (elapsed {elapsed:.2f}s).'
    new_pid = wait_for_service()
    assert new_pid is not None, 'Service is not running after timeout restart.'
    assert new_pid != old_pid, 'Watchdog failed to restart the service (PID unchanged) when TIMEOUT.'
    assert check_log_for_reason('TIMEOUT'), 'Watchdog log does not contain the correct TIMEOUT reason format.'


def test_watchdog_error_behavior():
    """Verify arbitrary non-200 HTTP status is classified as ERROR."""
    proc, evidence = start_mock_api('error')
    old_pid = str(proc.pid)
    result = run_watchdog()

    assert result.returncode == 0, 'Watchdog did not exit cleanly for ERROR.'
    assert read_evidence(evidence).splitlines() == ['GET /health'], \
        'Watchdog did not GET /health during the error test.'
    new_pid = wait_for_service()
    assert new_pid is not None, 'Service is not running after error restart.'
    assert new_pid != old_pid, 'Watchdog failed to restart the service (PID unchanged) when ERROR.'
    assert check_log_for_reason('ERROR'), 'Watchdog log does not contain the correct ERROR reason format.'


def test_logrotate_configuration_is_functional():
    """Actually rotate, compress, recreate, and tolerate a missing watchdog log."""
    kill_flaky_api()
    home_mode = stat.S_IMODE(os.stat('/home/user').st_mode)
    state_file = f'/tmp/logrotate-state-{uuid.uuid4().hex}'
    try:
        os.chmod('/home/user', 0o755)
        for path in glob.glob(LOG + '.*'):
            if os.path.isfile(path):
                os.remove(path)
        with open(LOG, 'w') as f:
            f.write('rotation probe\n')
        os.chmod(LOG, 0o644)

        result = subprocess.run(
            ['/usr/sbin/logrotate', '-f', '-s', state_file, CONF],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f'logrotate rejected or failed to apply the config: {result.stderr}'
        assert os.path.isfile(LOG), "Logrotate's create rule did not recreate watchdog.log."
        assert stat.S_IMODE(os.stat(LOG).st_mode) == 0o644, \
            'Recreated watchdog.log does not have mode 0644.'
        compressed = [p for p in glob.glob(LOG + '.*') if p.endswith('.gz')]
        assert compressed, 'The rotated watchdog log was not compressed.'

        os.remove(LOG)
        missing = subprocess.run(
            ['/usr/sbin/logrotate', '-f', '-s', state_file, CONF],
            capture_output=True, text=True
        )
        assert missing.returncode == 0, \
            f'Logrotate failed when watchdog.log was missing: {missing.stderr}'
    finally:
        os.chmod('/home/user', home_mode)
        if os.path.exists(state_file):
            os.remove(state_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
