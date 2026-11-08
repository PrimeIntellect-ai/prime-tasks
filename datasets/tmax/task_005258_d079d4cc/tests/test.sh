#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request


def start_http_server(status=200, delay=0):
    code = r'''
import sys, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
status = int(sys.argv[1])
delay = float(sys.argv[2])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if delay:
            time.sleep(delay)
        self.send_response(status)
        self.end_headers()
        self.wfile.write(b"verification response")
    def log_message(self, *args):
        pass
server = ThreadingHTTPServer(("127.0.0.1", 9090), Handler)
server.serve_forever()
'''
    proc = subprocess.Popen(
        ["python3", "-c", code, str(status), str(delay)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    time.sleep(0.4)
    assert proc.poll() is None, "Dummy HTTP server could not bind to port 9090."
    return proc


def stop_process(proc):
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def test_directories_exist():
    dirs = [
        "/home/user/run",
        "/home/user/logs",
        "/home/user/alerts",
    ]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory {directory} does not exist."


def test_deploy_script_and_forwarder():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deploy script {deploy_script} not found."
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable."

    pid_file = "/home/user/run/forwarder.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} not found. Did deploy.sh run?"
    with open(pid_file) as handle:
        pid = handle.read().strip()

    assert pid.isdigit(), f"PID file {pid_file} does not contain a valid PID."
    assert os.path.exists(f"/proc/{pid}"), f"Process with PID {pid} is not running."
    with open(f"/proc/{pid}/comm") as handle:
        comm = handle.read().strip()
    assert "socat" in comm, f"Process {pid} is not socat, it is {comm}."

    server_proc = start_http_server(200)
    try:
        request = urllib.request.Request("http://127.0.0.1:8080/")
        with urllib.request.urlopen(request, timeout=2) as response:
            assert response.status == 200, "Forwarder did not return 200 OK."
    finally:
        stop_process(server_proc)


def test_health_check_script():
    script = "/home/user/health_check.sh"
    log_file = "/home/user/logs/health.log"
    curl_path = "/usr/bin/curl"
    real_curl = "/usr/bin/curl.verifier-real"
    trace_file = "/tmp/verifier-curl-trace"

    assert os.path.isfile(script), f"Health check script {script} not found."
    assert os.access(script, os.X_OK), f"{script} is not executable."
    assert os.path.isfile(curl_path), "curl is not installed."
    assert not os.path.exists(real_curl), f"Unexpected file already exists: {real_curl}"

    os.rename(curl_path, real_curl)
    with open(curl_path, "w") as handle:
        handle.write(
            "#!/bin/bash\n"
            "{ printf 'CALL\\0'; printf '%s\\0' \"$@\"; printf 'END\\0'; } >> "
            + trace_file
            + "\n"
            "exec " + real_curl + " \"$@\"\n"
        )
    os.chmod(curl_path, 0o755)

    def run_and_check(expected, server=None, maximum_runtime=None):
        open(log_file, "w").close()
        open(trace_file, "wb").close()
        before = int(time.time())
        started = time.monotonic()
        result = subprocess.run([script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        elapsed = time.monotonic() - started
        after = int(time.time())

        assert result.returncode == 0, (
            f"Health check exited with {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        if maximum_runtime is not None:
            assert elapsed <= maximum_runtime, (
                f"Health check took {elapsed:.2f}s; curl was not limited to a 2-second maximum timeout."
            )

        assert os.path.isfile(log_file), f"Log file {log_file} not created."
        with open(log_file) as handle:
            lines = handle.read().splitlines()
        assert len(lines) == 1, "Each health-check run must append exactly one status line."
        match = re.fullmatch(r"\[(\d+)\] STATUS: (OK|FAIL)", lines[0])
        assert match, f"Health log line has an invalid format: {lines[0]!r}"
        assert match.group(2) == expected, f"Expected STATUS: {expected}, got {lines[0]!r}"
        assert before - 1 <= int(match.group(1)) <= after + 1, "Health log timestamp is not current."

        # Preserve the original positive/negative status assertions.
        content = "\n".join(lines)
        assert re.search(r"\[\d+\] STATUS: " + expected, content)

        trace = open(trace_file, "rb").read().split(b"\0")
        calls = []
        current = None
        for token in trace:
            if token == b"CALL":
                current = []
            elif token == b"END" and current is not None:
                calls.append([item.decode(errors="replace") for item in current])
                current = None
            elif current is not None and token:
                current.append(token)
        assert calls, "health_check.sh did not invoke curl."

        def valid_curl_call(args):
            has_url = "http://127.0.0.1:8080/" in args
            has_timeout = any(arg in ("--max-time=2", "-m2") for arg in args)
            for index, arg in enumerate(args[:-1]):
                if arg in ("--max-time", "-m") and args[index + 1] == "2":
                    has_timeout = True
            return has_url and has_timeout

        assert any(valid_curl_call(call) for call in calls), (
            "curl must request http://127.0.0.1:8080/ with a maximum timeout of 2 seconds."
        )

    try:
        server_proc = start_http_server(200)
        try:
            run_and_check("OK")
        finally:
            stop_process(server_proc)

        server_proc = start_http_server(503)
        try:
            run_and_check("FAIL")
        finally:
            stop_process(server_proc)

        # No server is listening: curl failure must produce exactly one FAIL line.
        run_and_check("FAIL", maximum_runtime=4)

        # A server that accepts but does not answer verifies the 2-second curl timeout.
        server_proc = start_http_server(200, delay=10)
        try:
            run_and_check("FAIL", maximum_runtime=4)
        finally:
            stop_process(server_proc)
    finally:
        if os.path.exists(curl_path):
            os.unlink(curl_path)
        os.rename(real_curl, curl_path)
        if os.path.exists(trace_file):
            os.unlink(trace_file)


def test_logrotate_config():
    conf = "/home/user/logrotate.conf"
    log_file = "/home/user/logs/health.log"
    assert os.path.isfile(conf), f"Logrotate config {conf} not found."

    with open(conf) as handle:
        content = handle.read()

    # Keep the original assertions.
    assert re.search(r"size\s+10k", content, re.IGNORECASE), (
        "logrotate.conf does not contain 'size 10k'."
    )
    assert re.search(r"rotate\s+3", content, re.IGNORECASE), (
        "logrotate.conf does not contain 'rotate 3'."
    )
    assert "/home/user/logs/health.log" in content, (
        "logrotate.conf does not target /home/user/logs/health.log."
    )

    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    with open(log_file, "wb") as handle:
        handle.write(b"x" * 9000)
    os.chown(log_file, 1000, 1000)

    state_dir = tempfile.mkdtemp(prefix="logrotate-check-")
    os.chown(state_dir, 1000, 1000)
    state_file = os.path.join(state_dir, "state")

    def debug_logrotate():
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "-d", "-s", state_file, conf],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        assert result.returncode == 0, f"Invalid or unusable logrotate configuration:\n{result.stdout}"
        return result.stdout

    try:
        small_output = debug_logrotate()
        assert re.search(
            r"rotating pattern:\s*/home/user/logs/health\.log\s+10240 bytes\s+\(3 rotations\)",
            small_output,
            re.IGNORECASE,
        ), "The target stanza is not parsed as size 10k with exactly 3 rotations."
        assert "log does not need rotating" in small_output.lower(), (
            "A health.log smaller than 10k should not rotate."
        )

        with open(log_file, "wb") as handle:
            handle.write(b"x" * 12000)
        os.chown(log_file, 1000, 1000)
        large_output = debug_logrotate()
        assert "log needs rotating" in large_output.lower(), (
            "A health.log larger than 10k was not selected for rotation."
        )
    finally:
        shutil.rmtree(state_dir, ignore_errors=True)
        with open(log_file, "w"):
            pass


def test_storage_monitor_script():
    script = "/home/user/storage_monitor.sh"
    alert_file = "/home/user/alerts/quota.txt"
    log_dir = "/home/user/logs"

    assert os.path.isfile(script), f"Storage monitor script {script} not found."
    assert os.access(script, os.X_OK), f"{script} is not executable."

    subprocess.run([script], check=True)
    assert os.path.isfile(alert_file), f"Alert file {alert_file} not created."
    with open(alert_file) as handle:
        assert handle.read().strip() == "QUOTA_OK", (
            "Alert file does not say QUOTA_OK when size is small."
        )

    dummy_file = os.path.join(log_dir, "dummy.log")
    try:
        with open(dummy_file, "wb") as handle:
            handle.write(b"0" * 60000)
        subprocess.run([script], check=True)
        with open(alert_file) as handle:
            assert handle.read().strip() == "QUOTA_EXCEEDED", (
                "Alert file does not say QUOTA_EXCEEDED when size is large."
            )
    finally:
        if os.path.exists(dummy_file):
            os.remove(dummy_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
