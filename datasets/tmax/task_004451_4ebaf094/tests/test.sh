#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncore
import configparser
import email
from email import policy
from email.parser import BytesParser
import json
import os
import secrets
import signal
import smtplib
import socket
import socketserver
import subprocess
import sys
import threading
import time

import pytest

BASE = "/home/user/capacity_planner"
CONFIG = f"{BASE}/configs/prod.json"
METRICS = f"{BASE}/simulated_metrics.csv"
EMAIL_LOG = f"{BASE}/logs/emails.log"
SMTP_SCRIPT = f"{BASE}/bin/mock_smtp.py"
MONITOR_SCRIPT = f"{BASE}/bin/monitor.py"
SUPERVISOR_CONF = f"{BASE}/supervisord.conf"


def test_directories_exist():
    dirs = [
        "/home/user/capacity_planner/configs",
        "/home/user/capacity_planner/logs",
        "/home/user/capacity_planner/bin"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} is missing or not a directory."


def test_config_and_symlink():
    config_path = "/home/user/capacity_planner/configs/prod.json"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Config file {config_path} is not valid JSON.")

    assert config.get("cpu_max") == 90, "cpu_max in config is not 90."
    assert config.get("mem_max") == 80, "mem_max in config is not 80."
    assert config.get("alert_email") == "alerts@capacity.local", "alert_email in config is incorrect."

    symlink_path = "/home/user/capacity_planner/active_config"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == config_path, f"Symlink points to {abs_target} instead of {config_path}."


def test_simulated_metrics_csv():
    csv_path = "/home/user/capacity_planner/simulated_metrics.csv"
    assert os.path.isfile(csv_path), f"CSV file {csv_path} is missing."
    with open(csv_path, 'r') as f:
        content = f.read().strip()
    assert "timestamp,cpu_usage,mem_usage" in content, "CSV header is missing or incorrect."
    assert "1600000004,99,99" in content, "CSV data is missing or incorrect."


def test_scripts_exist():
    smtp_script = "/home/user/capacity_planner/bin/mock_smtp.py"
    monitor_script = "/home/user/capacity_planner/bin/monitor.py"

    assert os.path.isfile(smtp_script), f"Script {smtp_script} is missing."
    assert os.path.isfile(monitor_script), f"Script {monitor_script} is missing."


def test_supervisord_conf():
    conf_path = "/home/user/capacity_planner/supervisord.conf"
    assert os.path.isfile(conf_path), f"Supervisord config {conf_path} is missing."
    with open(conf_path, 'r') as f:
        content = f.read()
    assert "mock_smtp.py" in content, "mock_smtp.py not referenced in supervisord.conf."
    assert "monitor.py" in content, "monitor.py not referenced in supervisord.conf."


def test_emails_log():
    log_path = "/home/user/capacity_planner/logs/emails.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did the monitor and smtp server run?"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_alerts = [
        "ALERT: timestamp=1600000002, cpu=95, mem=70",
        "ALERT: timestamp=1600000003, cpu=50, mem=85",
        "ALERT: timestamp=1600000004, cpu=99, mem=99"
    ]

    assert len(lines) == len(expected_alerts), f"Expected {len(expected_alerts)} alerts in log, found {len(lines)}."

    for i, expected in enumerate(expected_alerts):
        assert expected in lines[i], f"Log line {i+1} does not contain expected alert. Expected: '{expected}', Found: '{lines[i]}'"


def _kill_existing_stack():
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            raw = open(f'/proc/{entry}/cmdline', 'rb').read()
            args = [x.decode(errors='ignore') for x in raw.split(b'\0') if x]
        except (OSError, ProcessLookupError):
            continue
        joined = ' '.join(args)
        if BASE not in joined:
            continue
        names = {os.path.basename(x) for x in args}
        if 'supervisord' in names or 'mock_smtp.py' in names or 'monitor.py' in names:
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.7)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def _wait_for_port(proc, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"SMTP script exited early with status {proc.returncode}")
        try:
            with socket.create_connection(('127.0.0.1', 8025), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("SMTP script did not listen on 127.0.0.1:8025")


def _stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def test_mock_smtp_script_functionally_logs_only_dynamic_body():
    _kill_existing_stack()
    old_log = open(EMAIL_LOG, 'rb').read()
    token = secrets.token_hex(10)
    body = f"DYNAMIC-{token}"
    proc = None
    try:
        open(EMAIL_LOG, 'w').close()
        proc = subprocess.Popen(
            [sys.executable, SMTP_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _wait_for_port(proc)
        raw = (
            f"From: sender-{token}@example.test\r\n"
            f"To: recipient-{token}@example.test\r\n"
            f"Subject: hidden-{token}\r\n"
            "\r\n"
            f"{body}"
        )
        with smtplib.SMTP('127.0.0.1', 8025, timeout=3) as client:
            client.sendmail(
                f"sender-{token}@example.test",
                [f"recipient-{token}@example.test"],
                raw,
            )
        deadline = time.monotonic() + 3
        lines = []
        while time.monotonic() < deadline:
            lines = [x.strip() for x in open(EMAIL_LOG, encoding='utf-8').readlines() if x.strip()]
            if lines:
                break
            time.sleep(0.1)
        assert lines == [body], f"SMTP log must contain only the exact body; got {lines!r}"
    finally:
        if proc is not None:
            _stop_process(proc)
        open(EMAIL_LOG, 'wb').write(old_log)


class _CaptureServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address):
        self.messages = []
        self.lock = threading.Lock()
        super().__init__(address, _SMTPHandler)


class _SMTPHandler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"220 verifier.local ESMTP\r\n")
        recipients = []
        while True:
            line = self.rfile.readline()
            if not line:
                return
            command = line.decode('utf-8', 'replace').rstrip('\r\n')
            upper = command.upper()
            if upper.startswith('EHLO') or upper.startswith('HELO'):
                self.wfile.write(b"250 verifier.local\r\n")
            elif upper.startswith('MAIL FROM:'):
                recipients = []
                self.wfile.write(b"250 OK\r\n")
            elif upper.startswith('RCPT TO:'):
                value = command.split(':', 1)[1].strip().split()[0].strip('<>')
                recipients.append(value)
                self.wfile.write(b"250 OK\r\n")
            elif upper == 'DATA':
                self.wfile.write(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                chunks = []
                while True:
                    data_line = self.rfile.readline()
                    if data_line in (b'.\r\n', b'.\n', b'.') or not data_line:
                        break
                    if data_line.startswith(b'..'):
                        data_line = data_line[1:]
                    chunks.append(data_line)
                with self.server.lock:
                    self.server.messages.append((list(recipients), b''.join(chunks)))
                self.wfile.write(b"250 accepted\r\n")
            elif upper == 'QUIT':
                self.wfile.write(b"221 bye\r\n")
                return
            elif upper == 'RSET':
                recipients = []
                self.wfile.write(b"250 OK\r\n")
            else:
                self.wfile.write(b"250 OK\r\n")


def _decoded_body(raw):
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    payload = msg.get_payload(decode=True)
    if payload is None:
        payload = str(msg.get_payload()).encode()
    charset = msg.get_content_charset() or 'utf-8'
    return msg, payload.decode(charset, errors='replace').rstrip('\r\n')


def test_monitor_script_uses_symlink_config_dynamic_rows_and_sleeps():
    _kill_existing_stack()
    old_config = open(CONFIG, 'rb').read()
    old_metrics = open(METRICS, 'rb').read()
    nonce = secrets.token_hex(8)
    recipient = f"dynamic-{nonce}@capacity.local"
    timestamps = [str(7000000000 + secrets.randbelow(1000000) + i) for i in range(4)]
    rows = [
        (timestamps[0], '10', '20'),
        (timestamps[1], '42', '20'),
        (timestamps[2], '10', '53'),
        (timestamps[3], '40', '52'),
    ]
    expected = [
        f"ALERT: timestamp={timestamps[1]}, cpu=42, mem=20",
        f"ALERT: timestamp={timestamps[2]}, cpu=10, mem=53",
    ]
    server = _CaptureServer(('127.0.0.1', 8025))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        open(CONFIG, 'w').write(json.dumps({
            'cpu_max': 41,
            'mem_max': 52,
            'alert_email': recipient,
        }))
        with open(METRICS, 'w') as f:
            f.write('timestamp,cpu_usage,mem_usage\n')
            for row in rows:
                f.write(','.join(row) + '\n')

        start = time.monotonic()
        completed = subprocess.run(
            [sys.executable, MONITOR_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        elapsed = time.monotonic() - start
        assert completed.returncode == 0, completed.stderr
        assert elapsed >= 2.5, f"Monitor processed four rows too quickly ({elapsed:.2f}s); it must sleep between rows"

        with server.lock:
            captured = list(server.messages)
        assert len(captured) == len(expected), f"Expected {len(expected)} dynamic emails, got {len(captured)}"
        bodies = []
        for recipients, raw in captured:
            msg, body = _decoded_body(raw)
            assert recipients == [recipient], f"Wrong SMTP recipient: {recipients!r}"
            assert msg.get('To') == recipient, f"Wrong To header: {msg.get('To')!r}"
            bodies.append(body)
        assert bodies == expected
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        open(CONFIG, 'wb').write(old_config)
        open(METRICS, 'wb').write(old_metrics)


def test_supervisord_configuration_runs_both_scripts_on_dynamic_inputs():
    _kill_existing_stack()
    old_config = open(CONFIG, 'rb').read()
    old_metrics = open(METRICS, 'rb').read()
    old_log = open(EMAIL_LOG, 'rb').read()
    nonce = secrets.token_hex(8)
    recipient = f"supervised-{nonce}@capacity.local"
    timestamps = [str(8000000000 + secrets.randbelow(1000000) + i) for i in range(4)]
    rows = [
        (timestamps[0], '1', '1'),
        (timestamps[1], '61', '2'),
        (timestamps[2], '2', '71'),
        (timestamps[3], '3', '3'),
    ]
    expected = [
        f"ALERT: timestamp={timestamps[1]}, cpu=61, mem=2",
        f"ALERT: timestamp={timestamps[2]}, cpu=2, mem=71",
    ]
    proc = None
    try:
        open(CONFIG, 'w').write(json.dumps({
            'cpu_max': 60,
            'mem_max': 70,
            'alert_email': recipient,
        }))
        with open(METRICS, 'w') as f:
            f.write('timestamp,cpu_usage,mem_usage\n')
            for row in rows:
                f.write(','.join(row) + '\n')
        open(EMAIL_LOG, 'w').close()

        proc = subprocess.Popen(
            ['supervisord', '-n', '-c', SUPERVISOR_CONF],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.monotonic() + 9
        lines = []
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"supervisord exited early with status {proc.returncode}")
            try:
                lines = [x.strip() for x in open(EMAIL_LOG, encoding='utf-8').readlines() if x.strip()]
            except FileNotFoundError:
                lines = []
            if len(lines) >= len(expected):
                break
            time.sleep(0.2)
        assert lines == expected, f"Supervised stack did not produce derived alerts: {lines!r}"

        # Give the one-shot monitor time to finish and ensure it is not restarted.
        time.sleep(3)
        lines = [x.strip() for x in open(EMAIL_LOG, encoding='utf-8').readlines() if x.strip()]
        assert lines == expected, "Monitor appears to have restarted or produced duplicate alerts"
        assert proc.poll() is None, "supervisord must remain running to supervise the SMTP service"
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=2)
        open(CONFIG, 'wb').write(old_config)
        open(METRICS, 'wb').write(old_metrics)
        open(EMAIL_LOG, 'wb').write(old_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
