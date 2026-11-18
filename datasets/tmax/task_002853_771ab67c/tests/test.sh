#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import email
import json
import os
import signal
import smtplib
import socket
import subprocess
import time
import urllib.request

import pytest

RESTORE_DIR = "/home/user/restore_test"
CONF = os.path.join(RESTORE_DIR, "supervisord.conf")
SCRIPT = os.path.join(RESTORE_DIR, "verify_restore.py")
STATUS = os.path.join(RESTORE_DIR, "restore_status.txt")
MAIL_LOG = os.path.join(RESTORE_DIR, "logs/mail.log")
OBS = "/tmp/restore_verifier_observations.jsonl"
FAIL_FLAG = "/tmp/restore_verifier_http_fail"
SERVICE_NAMES = {"backend.py", "proxy.py", "smtp.py", "healthcheck.py"}


def restored_service_pids():
    found = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            cwd = os.readlink(f"/proc/{entry}/cwd")
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                parts = [p.decode(errors="replace") for p in f.read().split(b"\0") if p]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if cwd == RESTORE_DIR:
            for name in SERVICE_NAMES:
                if name in parts:
                    found.setdefault(name, []).append(int(entry))
    return found


def stop_stack():
    pids = set()
    pidfile = os.path.join(RESTORE_DIR, "logs/supervisord.pid")
    try:
        with open(pidfile) as f:
            pids.add(int(f.read().strip()))
    except (OSError, ValueError):
        pass
    for values in restored_service_pids().values():
        pids.update(values)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        alive = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            break
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    try:
        os.unlink(pidfile)
    except FileNotFoundError:
        pass
    time.sleep(0.3)


def wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Port {port} did not become available: {last_error}")


def wait_for_stack_processes(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = restored_service_pids()
        if all(found.get(name) for name in SERVICE_NAMES):
            return
        time.sleep(0.2)
    raise AssertionError(f"Not all configured supervisor services are running: {restored_service_pids()}")


def terminate_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


HARNESS = r'''import asyncore
import json
import os
import smtpd
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

OBS = "/tmp/restore_verifier_observations.jsonl"
FAIL_FLAG = "/tmp/restore_verifier_http_fail"
MAIL_LOG = "/home/user/restore_test/logs/mail.log"
lock = threading.Lock()

def record(value):
    with lock:
        with open(OBS, "a") as f:
            f.write(json.dumps(value) + "\n")

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        record({"kind": "http", "path": self.path, "headers": dict(self.headers)})
        if os.path.exists(FAIL_FLAG):
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"NOT READY")
        elif self.path == "/ping":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"PONG")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass

class SMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        text = data.decode("utf-8", errors="replace") if isinstance(data, bytes) else str(data)
        record({"kind": "smtp", "mailfrom": mailfrom, "rcpttos": rcpttos, "data": text})
        with open(MAIL_LOG, "a") as f:
            f.write(f"To: {rcpttos}\nData: {text}\n---\n")

httpd = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
SMTPServer(("127.0.0.1", 8025), None)
asyncore.loop(timeout=0.2)
'''


def read_observations():
    values = []
    if os.path.exists(OBS):
        with open(OBS) as f:
            for line in f:
                if line.strip():
                    values.append(json.loads(line))
    return values


def test_00_running_stack_and_validation_script():
    assert os.path.isfile(SCRIPT), f"Missing validation script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Validation script is not executable: {SCRIPT}"

    harness = None
    stop_stack()
    try:
        supervisor = subprocess.run(
            ["supervisord", "-c", CONF],
            cwd=RESTORE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        assert supervisor.returncode == 0, f"supervisord failed to start:\n{supervisor.stdout}"
        wait_for_stack_processes()
        wait_for_port(9000)
        wait_for_port(8080)
        wait_for_port(8025)

        request = urllib.request.Request("http://127.0.0.1:8080/ping", method="GET")
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read().decode("utf-8", errors="replace")
            assert response.status == 200, f"Proxy returned HTTP {response.status}"
            assert "PONG" in body, f"Proxy response did not contain PONG: {body!r}"

        try:
            os.unlink(MAIL_LOG)
        except FileNotFoundError:
            pass
        with smtplib.SMTP("127.0.0.1", 8025, timeout=5) as smtp:
            smtp.sendmail(
                "verifier@localhost",
                ["stack-probe@localhost"],
                "Subject: Stack Probe\n\nSMTP stack probe.",
            )
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                with open(MAIL_LOG) as f:
                    if "stack-probe@localhost" in f.read():
                        break
            except FileNotFoundError:
                pass
            time.sleep(0.1)
        else:
            raise AssertionError("The restored SMTP service did not record the probe email")

        stop_stack()
        for path in (STATUS, MAIL_LOG, OBS, FAIL_FLAG):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        harness_path = "/tmp/restore_verifier_services.py"
        with open(harness_path, "w") as f:
            f.write(HARNESS)
        harness = subprocess.Popen(
            ["python3", harness_path],
            cwd="/tmp",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        wait_for_port(8080)
        wait_for_port(8025)

        completed = subprocess.run(
            ["python3", SCRIPT],
            cwd=RESTORE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        assert completed.returncode == 0, f"verify_restore.py failed:\n{completed.stdout}"

        observations = read_observations()
        http_events = [v for v in observations if v.get("kind") == "http" and v.get("path") == "/ping"]
        assert http_events, "verify_restore.py did not send GET /ping to port 8080"
        smtp_events = [v for v in observations if v.get("kind") == "smtp"]
        assert smtp_events, "verify_restore.py did not dispatch an email through port 8025"

        matching_mail = []
        for event in smtp_events:
            message = email.message_from_string(event.get("data", ""))
            payload = message.get_payload(decode=True)
            if payload is None:
                body = str(message.get_payload())
            else:
                body = payload.decode(message.get_content_charset() or "utf-8", errors="replace")
            if (
                event.get("mailfrom") == "operator@localhost"
                and "backup-success@localhost" in event.get("rcpttos", [])
                and message.get("Subject") == "Restore Test Passed"
                and "All services operational." in body
            ):
                matching_mail.append(event)
        assert matching_mail, "The dispatched email did not have the required envelope, subject, and body"

        assert os.path.isfile(STATUS), "verify_restore.py did not create restore_status.txt after successful checks"
        with open(STATUS, "rb") as f:
            successful_status = f.read()
        assert successful_status.decode(errors="replace").splitlines()[-1].strip() == "RESTORE VALIDATED"

        open(FAIL_FLAG, "w").close()
        subprocess.run(
            ["python3", SCRIPT],
            cwd=RESTORE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        with open(STATUS, "rb") as f:
            failed_status = f.read()
        assert failed_status == successful_status, "verify_restore.py appended validation even when the HTTP check failed"
    finally:
        terminate_process(harness)
        try:
            os.unlink(FAIL_FLAG)
        except FileNotFoundError:
            pass
        stop_stack()


def test_restore_status_txt():
    status_file = os.path.join(RESTORE_DIR, "restore_status.txt")
    assert os.path.isfile(status_file), f"Missing file: {status_file}. The verify_restore.py script may not have been run or failed to create it."

    with open(status_file, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"File {status_file} is empty."
    assert lines[-1].strip() == "RESTORE VALIDATED", f"Last line of {status_file} is not 'RESTORE VALIDATED'. Found: {lines[-1]}"


def test_mail_log():
    mail_log = os.path.join(RESTORE_DIR, "logs/mail.log")
    assert os.path.isfile(mail_log), f"Missing file: {mail_log}. The verify_restore.py script may not have sent the email."

    with open(mail_log, "r") as f:
        content = f.read()

    assert "backup-success@localhost" in content, "Mail log is missing an email destined to 'backup-success@localhost'."
    assert "Restore Test Passed" in content, "Mail log is missing an email with the subject 'Restore Test Passed'."


def test_proxy_fixed():
    proxy_path = os.path.join(RESTORE_DIR, "proxy.py")
    assert os.path.isfile(proxy_path), f"Missing file: {proxy_path}"

    with open(proxy_path, "r") as f:
        content = f.read()

    assert "X-Backup-Restore-Test" not in content, "proxy.py still contains the 'X-Backup-Restore-Test' header check."


def test_healthcheck_fixed():
    healthcheck_path = os.path.join(RESTORE_DIR, "healthcheck.py")
    assert os.path.isfile(healthcheck_path), f"Missing file: {healthcheck_path}"

    with open(healthcheck_path, "r") as f:
        content = f.read()

    assert "smtplib.SMTP('127.0.0.1', 25)" not in content and "smtplib.SMTP(\"127.0.0.1\", 25)" not in content, "healthcheck.py still attempts to connect to port 25."
    assert "8025" in content, "healthcheck.py does not appear to be updated to use port 8025."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
