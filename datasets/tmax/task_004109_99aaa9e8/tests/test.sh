#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import json
import os
import shlex
import shutil
import signal
import socketserver
import stat
import subprocess
import threading
import time
import uuid

APP_DIR = "/home/user/app"
BACKUP_FILE = os.path.join(APP_DIR, "backups", "start_services.sh.bak")
START_SCRIPT = os.path.join(APP_DIR, "start_services.sh")
INITIALIZER = os.path.join(APP_DIR, "data_initializer.py")
BACKEND = os.path.join(APP_DIR, "backend_api.py")
SHARED_DATA = os.path.join(APP_DIR, "shared_data.json")
HEALTH_CHECK_SCRIPT = os.path.join(APP_DIR, "health_check.py")
LOG_DIR = os.path.join(APP_DIR, "logs")
HEALTH_LOG = os.path.join(LOG_DIR, "health.log")

ORIGINAL_START = (
    b"#!/bin/bash\n"
    b"python3 /home/user/app/data_initializer.py &\n"
    b"python3 /home/user/app/backend_api.py &\n"
    b"wait\n"
)


def test_backup_exists():
    assert os.path.isfile(BACKUP_FILE), f"Backup file not found at {BACKUP_FILE}"
    with open(BACKUP_FILE, "rb") as f:
        content = f.read()
    assert b"data_initializer.py" in content, "Backup file does not look like the original script."
    assert content == ORIGINAL_START, "Backup is not an unchanged copy of the original start_services.sh"


def test_start_services_fixed():
    assert os.path.isfile(START_SCRIPT), f"Script not found at {START_SCRIPT}"
    assert os.access(START_SCRIPT, os.X_OK), f"Script {START_SCRIPT} is not executable"

    with open(START_SCRIPT, "r") as f:
        content = f.read()

    # Retain the original structural assertions.
    assert "shared_data.json" in content, "start_services.sh does not seem to check for shared_data.json"
    assert "sleep" in content or "inotifywait" in content, "start_services.sh does not seem to wait/sleep for the file"


def _stop_process_group(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=1)


def _wait_for_file(path, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.isfile(path):
            return
        time.sleep(0.03)
    raise AssertionError(f"Timed out waiting for probe output {path}")


def _run_start_probe(initially_present, initializer_delay):
    token = uuid.uuid4().hex
    suffix = uuid.uuid4().hex
    backend_marker = f"/tmp/backend_probe_{suffix}.json"
    init_marker = f"/tmp/init_probe_{suffix}"

    initializer_source = f'''import json, os, time
time.sleep({initializer_delay!r})
with open({init_marker!r}, "w") as f:
    f.write({token!r})
tmp = {SHARED_DATA!r} + ".probe.tmp"
with open(tmp, "w") as f:
    json.dump({{"token": {token!r}}}, f)
os.replace(tmp, {SHARED_DATA!r})
'''
    backend_source = f'''import json, os, time
ok = False
try:
    with open({SHARED_DATA!r}, "r") as f:
        ok = json.load(f) == {{"token": {token!r}}}
except Exception:
    ok = False
with open({backend_marker!r}, "w") as f:
    json.dump({{"shared_valid": ok, "init_done": os.path.exists({init_marker!r}), "started": time.time()}}, f)
'''

    with open(INITIALIZER, "w") as f:
        f.write(initializer_source)
    with open(BACKEND, "w") as f:
        f.write(backend_source)

    if os.path.exists(SHARED_DATA):
        os.remove(SHARED_DATA)
    if initially_present:
        with open(SHARED_DATA, "w") as f:
            json.dump({"token": token}, f)

    started = time.time()
    proc = subprocess.Popen(
        [START_SCRIPT],
        cwd=APP_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        _wait_for_file(backend_marker, 5.5)
        with open(backend_marker) as f:
            result = json.load(f)
        result["elapsed"] = result["started"] - started
        return result
    finally:
        _stop_process_group(proc)
        for path in (backend_marker, init_marker, SHARED_DATA + ".probe.tmp"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_start_services_runtime_dependency():
    saved = {}
    for path in (INITIALIZER, BACKEND):
        with open(path, "rb") as f:
            saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
    shared_existed = os.path.exists(SHARED_DATA)
    shared_content = None
    shared_mode = None
    if shared_existed:
        with open(SHARED_DATA, "rb") as f:
            shared_content = f.read()
        shared_mode = stat.S_IMODE(os.stat(SHARED_DATA).st_mode)

    try:
        # With no data file, backend must not be invoked until the delayed
        # initializer has actually produced the expected file.
        delayed = _run_start_probe(initially_present=False, initializer_delay=2.2)
        assert delayed["shared_valid"], "backend_api.py was started before valid shared_data.json existed"
        assert delayed["init_done"], "backend_api.py was started before the initializer completed its data setup"
        assert delayed["elapsed"] >= 2.0, "backend_api.py started before the delayed initializer produced the file"

        # The check must be idempotent: when the file already exists, backend
        # should start promptly rather than waiting a fixed initializer delay.
        ready = _run_start_probe(initially_present=True, initializer_delay=5.0)
        assert ready["shared_valid"], "backend_api.py did not receive the already-existing valid data file"
        assert ready["elapsed"] < 1.2, "start_services.sh uses an unconditional delay instead of checking file existence"
    finally:
        for path, (content, mode) in saved.items():
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
        try:
            os.remove(SHARED_DATA)
        except FileNotFoundError:
            pass
        if shared_existed:
            with open(SHARED_DATA, "wb") as f:
                f.write(shared_content)
            os.chmod(SHARED_DATA, shared_mode)


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


class StatusHandler(http.server.BaseHTTPRequestHandler):
    status_code = 503

    def do_GET(self):
        if self.path == "/status":
            self.send_response(type(self).status_code)
            self.end_headers()
            self.wfile.write(b"OK" if type(self).status_code == 200 else b"FAIL")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def _run_health_check():
    return subprocess.run(
        ["python3", HEALTH_CHECK_SCRIPT],
        capture_output=True,
        text=True,
        timeout=8,
    )


def _read_log_lines():
    with open(HEALTH_LOG, "r") as f:
        return f.readlines()


def test_health_check_script_functionality():
    assert os.path.isfile(HEALTH_CHECK_SCRIPT), f"Health check script not found at {HEALTH_CHECK_SCRIPT}"

    # The script itself must ensure the logs directory exists.
    if os.path.isdir(LOG_DIR):
        shutil.rmtree(LOG_DIR)

    down = _run_health_check()
    assert down.returncode == 0, "Health check crashed when the service was down"
    assert os.path.isdir(LOG_DIR), f"Log directory not created at {LOG_DIR}"
    assert os.path.isfile(HEALTH_LOG), f"Log file not created at {HEALTH_LOG}"
    logs = _read_log_lines()
    assert len(logs) >= 1, "No logs written when service is down"
    assert "[ERROR] Service unreachable or failing" in logs[-1], "Incorrect error log message"
    assert logs[-1] == "[ERROR] Service unreachable or failing\n", "Error log entry is not exact"

    httpd = ReusableTCPServer(("127.0.0.1", 8080), StatusHandler)
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    try:
        time.sleep(0.2)

        StatusHandler.status_code = 503
        failed = _run_health_check()
        assert failed.returncode == 0, "Health check crashed on a non-200 response"
        logs = _read_log_lines()
        assert logs[-1] == "[ERROR] Service unreachable or failing\n", "Non-200 response was not logged as an exact error"

        StatusHandler.status_code = 200
        healthy = _run_health_check()
        assert healthy.returncode == 0, "Health check crashed on a healthy response"
        logs = _read_log_lines()
        assert len(logs) >= 2, "No new logs written when service is up"
        assert "[OK] Service healthy" in logs[-1], "Incorrect success log message"
        assert logs[-1] == "[OK] Service healthy\n", "Success log entry is not exact"
    finally:
        httpd.shutdown()
        httpd.server_close()
        server_thread.join(timeout=1)


def test_crontab_entry():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab"
    cron_jobs = result.stdout

    # Retain the original assertions.
    assert "health_check.py" in cron_jobs, "No crontab entry found for health_check.py"
    assert "* * * * *" in cron_jobs, "Crontab entry is not set to run every minute (* * * * *)"
    assert "/usr/bin/python3" in cron_jobs, "Crontab entry does not use /usr/bin/python3"

    valid = False
    for raw_line in cron_jobs.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 5)
        if len(parts) != 6 or parts[:5] != ["*", "*", "*", "*", "*"]:
            continue
        try:
            command = shlex.split(parts[5])
        except ValueError:
            continue
        if command[:2] == ["/usr/bin/python3", HEALTH_CHECK_SCRIPT]:
            valid = True
            break
    assert valid, "No active every-minute cron entry runs the required health-check command"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
