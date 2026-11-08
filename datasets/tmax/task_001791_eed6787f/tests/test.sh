#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import threading
from datetime import datetime
from zoneinfo import ZoneInfo
from http.server import HTTPServer, BaseHTTPRequestHandler

TOKYO = ZoneInfo("Asia/Tokyo")
LOG_FILE = "/home/user/conn.log"
SCRIPT_PATH = "/home/user/active_tool"
SENTINEL = b"verifier-existing-line\n"


def test_directory_exists():
    assert os.path.isdir("/home/user/network_tools"), "Directory /home/user/network_tools does not exist."


def test_symlink_exists_and_correct():
    symlink_path = "/home/user/active_tool"
    target_path = "/home/user/network_tools/check_conn.py"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    assert os.readlink(symlink_path) == target_path, f"Symlink does not point to {target_path}."


def test_script_is_executable():
    script_path = "/home/user/network_tools/check_conn.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_crontab_entry():
    try:
        output = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        output = ""

    required = "*/5 * * * * /home/user/active_tool"
    jobs = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        # Crontabs may contain environment assignments; these are not jobs.
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*\s*=', line):
            continue
        jobs.append(re.sub(r'\s+', ' ', line))

    assert required in jobs, "Crontab does not contain the correct entry: '*/5 * * * * /home/user/active_tool'."
    assert jobs == [required], f"Crontab must contain exactly one cron job, but contains: {jobs}"


def run_and_check_single_append(expected_status):
    with open(LOG_FILE, "wb") as f:
        f.write(SENTINEL)

    with open(LOG_FILE, "rb") as f:
        before_data = f.read()

    before_time = datetime.now(TOKYO)
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    after_time = datetime.now(TOKYO)

    assert result.returncode == 0, f"Script execution failed: {result.stderr}"
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created."

    with open(LOG_FILE, "rb") as f:
        after_data = f.read()

    assert after_data.startswith(before_data), "The script overwrote or modified existing log content instead of appending."
    appended = after_data[len(before_data):]
    appended_lines = appended.splitlines(keepends=True)
    assert len(appended_lines) == 1, f"Each execution must append exactly one log line; appended data was: {appended!r}"
    assert appended.endswith(b"\n"), "The appended log line must be newline-terminated."

    try:
        line = appended[:-1].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError("The appended log line is not valid UTF-8.") from exc

    pattern = rf"^\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}) JST\] {expected_status}$"
    match = re.match(pattern, line)
    assert match, f"Log line does not match expected format for {expected_status} case: {line}"

    reported_time = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=TOKYO)
    earliest = before_time.replace(microsecond=0)
    latest = after_time.replace(microsecond=0)
    assert earliest <= reported_time <= latest, (
        f"Log timestamp {reported_time.isoformat()} is not the current Asia/Tokyo time "
        f"for this execution ({earliest.isoformat()} through {latest.isoformat()})."
    )

    lines = after_data.decode("utf-8").splitlines()
    assert len(lines) > 0, "Log file is empty."
    assert lines[-1] == line, "The appended entry is not the last log line."


def test_script_execution_fail_case():
    subprocess.run(["fuser", "-k", "8080/tcp"], capture_output=True)
    run_and_check_single_append("FAIL")


class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, format, *args):
        pass


def test_script_execution_ok_case():
    server = HTTPServer(('127.0.0.1', 8080), SimpleHandler)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    try:
        time.sleep(0.5)
        run_and_check_single_append("OK")
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
