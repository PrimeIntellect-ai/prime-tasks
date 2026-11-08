#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def stop_services():
    subprocess.run(["pkill", "-f", "/home/user/proxy/proxy_bin"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/backends/backend_bin"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/start_services.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def test_proxy_bin_exists():
    bin_path = "/home/user/proxy/proxy_bin"
    assert os.path.isfile(bin_path), f"File {bin_path} does not exist. Did you recompile the proxy?"
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."


def test_alerts_log_permissions():
    log_path = "/home/user/alerts/alerts.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    st = os.stat(log_path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o600, f"Permissions for {log_path} are {oct(mode)}, expected 0o600."


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original required-directive assertions.
    assert "/home/user/alerts/alerts.log" in content, "logrotate.conf does not target /home/user/alerts/alerts.log"
    assert re.search(r"\bdaily\b", content), "logrotate.conf is missing 'daily' directive."
    assert re.search(r"\brotate\s+3\b", content), "logrotate.conf is missing 'rotate 3' directive."
    assert re.search(r"\bmissingok\b", content), "logrotate.conf is missing 'missingok' directive."
    assert re.search(r"\bnotifempty\b", content), "logrotate.conf is missing 'notifempty' directive."

    # Require the directives to be inside a real block for the requested log.
    uncommented = re.sub(r"(?m)#.*$", "", content)
    match = re.search(r"(?ms)^\s*/home/user/alerts/alerts\.log\s*\{([^{}]*)\}", uncommented)
    assert match, "The requested log must have a valid logrotate configuration block."
    body = match.group(1)
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    assert "daily" in lines, "'daily' must be a directive in the alerts.log block."
    assert any(re.fullmatch(r"rotate\s+3", line) for line in lines), "'rotate 3' must be in the alerts.log block."
    assert "missingok" in lines, "'missingok' must be a directive in the alerts.log block."
    assert "notifempty" in lines, "'notifempty' must be a directive in the alerts.log block."

    # Have logrotate parse the submitted block. Use a secure temporary target so
    # the intentionally permissive /home/user parent does not cause a false error.
    work = "/tmp/verifier-logrotate"
    os.makedirs(work, mode=0o700, exist_ok=True)
    target = os.path.join(work, "alerts.log")
    open(target, "a").close()
    synthetic = target + " {\n" + body + "\n    su root root\n}\n"
    parsed_conf = os.path.join(work, "logrotate.conf")
    with open(parsed_conf, "w") as f:
        f.write(synthetic)
    os.chmod(parsed_conf, 0o600)
    result = subprocess.run(
        ["logrotate", "-d", "-s", os.path.join(work, "state"), parsed_conf],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, "logrotate rejected the configuration block:\n" + result.stdout


def test_proxy_retries_and_delays_before_starting():
    stop_services()

    records = {
        8081: {"ping_times": [], "alerts": []},
        8082: {"ping_times": [], "alerts": []},
    }

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            port = self.server.server_address[1]
            if self.path != "/ping":
                self.send_response(404)
                self.end_headers()
                return
            rec = records[port]
            rec["ping_times"].append(time.monotonic())
            # Each backend becomes healthy only on its fifth check.
            self.send_response(200 if len(rec["ping_times"]) >= 5 else 503)
            self.end_headers()
            self.wfile.write(b"pong")

        def do_POST(self):
            port = self.server.server_address[1]
            length = int(self.headers.get("Content-Length", "0"))
            records[port]["alerts"].append(self.rfile.read(length))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, fmt, *args):
            pass

    servers = []
    threads = []
    proc = None
    try:
        for port in (8081, 8082):
            server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
            servers.append(server)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            threads.append(thread)

        proc = subprocess.Popen(
            ["/home/user/proxy/proxy_bin"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )

        deadline = time.monotonic() + 15
        listening = False
        while time.monotonic() < deadline:
            assert proc.poll() is None, "proxy exited before the delayed backends became healthy"
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    listening = True
                    break
            except OSError:
                time.sleep(0.1)
        assert listening, "proxy did not start after the backends became healthy"

        for port in (8081, 8082):
            times = records[port]["ping_times"]
            assert len(times) == 5, f"backend {port} received {len(times)} health checks, expected 5"
            gaps = [b - a for a, b in zip(times, times[1:])]
            assert all(0.75 <= gap <= 2.0 for gap in gaps), \
                f"backend {port} retry delays were not approximately one second: {gaps}"

        request = urllib.request.Request(
            "http://127.0.0.1:8080/alert",
            data=b'{"probe":"verifier"}',
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=2) as response:
            assert response.status == 200
        assert sum(len(records[p]["alerts"]) for p in (8081, 8082)) == 1, \
            "the running proxy did not forward the test alert to a backend"
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
        for server in servers:
            server.shutdown()
            server.server_close()
        stop_services()


def test_proxy_eventually_panics_when_backends_never_start():
    stop_services()
    started = time.monotonic()
    proc = subprocess.Popen(
        ["/home/user/proxy/proxy_bin"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = proc.communicate(timeout=9)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        raise AssertionError("proxy did not finally panic after its retry limit")
    elapsed = time.monotonic() - started
    assert proc.returncode != 0, "proxy should panic when no backend ever becomes available"
    assert 3.4 <= elapsed <= 7.5, f"unexpected retry duration before panic: {elapsed:.2f} seconds"
    assert "panic" in output.lower(), "proxy exited without the required final panic"


def test_verification_script():
    script_path = "/home/user/test_alert.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    stop_services()
    result_path = "/home/user/result.txt"
    if os.path.exists(result_path):
        os.remove(result_path)
    with open("/home/user/alerts/alerts.log", "w"):
        pass
    os.chmod("/home/user/alerts/alerts.log", 0o600)

    trace_path = "/tmp/test_alert.trace"
    started = time.monotonic()
    with open(trace_path, "w") as trace:
        proc = subprocess.Popen(
            ["bash", "-x", script_path],
            stdout=subprocess.DEVNULL,
            stderr=trace,
            start_new_session=True,
        )
        try:
            rc = proc.wait(timeout=14)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise AssertionError("test_alert.sh did not complete in time")
        finally:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    elapsed = time.monotonic() - started
    stop_services()

    assert rc == 0, f"test_alert.sh exited with status {rc}"
    assert elapsed >= 6.5, f"test_alert.sh did not wait approximately 7 seconds ({elapsed:.2f}s)"
    with open(trace_path) as f:
        trace = f.read()
    assert re.search(r"(?:^|\s)/home/user/start_services\.sh(?:\s|$)", trace, re.MULTILINE), \
        "test_alert.sh did not execute /home/user/start_services.sh"

    # Preserve the original result assertions, but only after executing the script.
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you run the test_alert.sh script?"
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "200", f"Expected HTTP status code 200 in {result_path}, but got '{content}'."

    with open("/home/user/alerts/alerts.log", "r") as f:
        alerts = f.read()
    assert '{"message": "Critical CPU usage"}' in alerts, \
        "the verification POST did not reach either real backend"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
