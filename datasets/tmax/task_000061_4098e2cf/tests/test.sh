#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SMTP_EOF' > /tmp/verifier_smtp.py
import asyncio
import base64
import json
import sys
from aiosmtpd.controller import Controller

output = sys.argv[1]

class Handler:
    async def handle_DATA(self, server, session, envelope):
        record = {
            "mail_from": envelope.mail_from,
            "rcpt_tos": envelope.rcpt_tos,
            "data": base64.b64encode(envelope.original_content).decode("ascii"),
        }
        with open(output, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
            f.flush()
        return "250 OK"

controller = Controller(Handler(), hostname="127.0.0.1", port=10025)
controller.start()
try:
    asyncio.get_event_loop().run_forever()
finally:
    controller.stop()
SMTP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import email
from email import policy
from email.message import EmailMessage
import json
import os
import random
import secrets
import signal
import smtplib
import socket
import subprocess
import time


def wait_until(predicate, timeout, interval=0.05):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return True
        except (OSError, ValueError):
            pass
        time.sleep(interval)
    return False


def read_file(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def stop_services():
    subprocess.run(["pkill", "-f", "monitor.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "supervisor.sh"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["fuser", "-k", "10025/tcp"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def monitor_pids():
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            data = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
        except OSError:
            continue
        if b"monitor.py" in data:
            found.add(int(entry))
    return found


def test_monitor_profile_exists_and_configured():
    profile_path = "/home/user/.monitor_profile"
    assert os.path.exists(profile_path), f"{profile_path} is missing."
    with open(profile_path, "r") as f:
        content = f.read()
    assert "ALERT_THRESHOLD=90" in content, "ALERT_THRESHOLD=90 not found in .monitor_profile"
    assert "ALERT_EMAIL=admin@local.dev" in content, "ALERT_EMAIL=admin@local.dev not found in .monitor_profile"

    values = subprocess.check_output([
        "bash", "-c",
        "unset ALERT_THRESHOLD ALERT_EMAIL; source /home/user/.monitor_profile; "
        "printf '%s\\n%s\\n' \"$ALERT_THRESHOLD\" \"$ALERT_EMAIL\"; "
        "env | grep -qx 'ALERT_THRESHOLD=90'; env | grep -qx 'ALERT_EMAIL=admin@local.dev'"
    ], text=True).splitlines()
    assert values[:2] == ["90", "admin@local.dev"], ".monitor_profile does not export the required values"


def test_scripts_are_executable():
    assert os.access("/home/user/monitor.py", os.X_OK), "monitor.py is not executable"
    assert os.access("/home/user/supervisor.sh", os.X_OK), "supervisor.sh is not executable"


def test_supervisor_running():
    output = subprocess.check_output(["ps", "aux"]).decode()
    assert "supervisor.sh" in output, "supervisor.sh is not running in the background"


def test_alert_pipeline_and_supervisor_restart():
    cpu_file = "/home/user/cpu.txt"
    email_log = "/home/user/email_out.log"

    with open(cpu_file, "w") as f:
        f.write("95\n")
    time.sleep(2)

    assert os.path.exists(email_log), f"{email_log} was not created by the mock SMTP server."
    with open(email_log, "r") as f:
        log_content = f.read()

    assert "Subject: CPU Alert" in log_content, "Expected 'Subject: CPU Alert' in email log"
    assert "admin@local.dev" in log_content, "Expected destination 'admin@local.dev' in email log"

    initial_email_count = log_content.count("Subject: CPU Alert")
    assert initial_email_count >= 1, "No email found in log after exceeding threshold."

    subprocess.run(["pkill", "-f", "monitor.py"])
    time.sleep(3)

    with open(cpu_file, "w") as f:
        f.write("50\n")
    time.sleep(2)

    with open(cpu_file, "w") as f:
        f.write("99\n")
    time.sleep(3)

    with open(email_log, "r") as f:
        log_content_after = f.read()

    final_email_count = log_content_after.count("Subject: CPU Alert")
    assert final_email_count > initial_email_count, (
        "Supervisor did not restart monitor.py successfully, or the second alert was not sent."
    )


def test_real_mock_server_and_supervisor_restart_deadline():
    cpu_file = "/home/user/cpu.txt"
    email_log = "/home/user/email_out.log"
    stop_services()
    try:
        with open(cpu_file, "w") as f:
            f.write("50\n")
        try:
            os.unlink(email_log)
        except FileNotFoundError:
            pass

        hostile_env = os.environ.copy()
        hostile_env.update({"ALERT_THRESHOLD": "1000", "ALERT_EMAIL": "wrong@example.invalid"})
        subprocess.Popen(["/home/user/supervisor.sh"], env=hostile_env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)

        def port_open():
            with socket.create_connection(("127.0.0.1", 10025), timeout=0.2):
                return True
        assert wait_until(port_open, 4), "Supervisor did not start an SMTP server on 127.0.0.1:10025"
        assert wait_until(lambda: bool(monitor_pids()), 3), "Supervisor did not start monitor.py"

        token = secrets.token_hex(8)
        probe = EmailMessage()
        probe["From"] = f"probe-{token}@local.dev"
        probe["To"] = "sink@local.dev"
        probe["Subject"] = f"SMTP probe {token}"
        probe.set_content(f"probe body {token}")
        with smtplib.SMTP("127.0.0.1", 10025, timeout=3) as client:
            client.send_message(probe)
        assert wait_until(lambda: token in read_file(email_log), 2), (
            "The submitted SMTP server did not append a received message to email_out.log"
        )

        time.sleep(1.2)
        before = read_file(email_log).count("Subject: CPU Alert")
        with open(cpu_file, "w") as f:
            f.write("95\n")
        assert wait_until(lambda: read_file(email_log).count("Subject: CPU Alert") > before, 2.2), (
            "The supervised monitor did not deliver an alert through the submitted SMTP server"
        )
        alert_log = read_file(email_log)
        assert "monitor@local.dev" in alert_log
        assert "admin@local.dev" in alert_log
        assert "Threshold exceeded" in alert_log

        with open(cpu_file, "w") as f:
            f.write("50\n")
        time.sleep(1.2)
        old_pids = monitor_pids()
        assert old_pids, "No monitor.py process was available for restart testing"
        for pid in old_pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        killed_at = time.monotonic()
        assert wait_until(lambda: bool(monitor_pids() - old_pids), 2.2), (
            "Supervisor did not restart monitor.py within 2 seconds"
        )
        assert time.monotonic() - killed_at <= 2.2

        restarted_count = read_file(email_log).count("Subject: CPU Alert")
        with open(cpu_file, "w") as f:
            f.write("99\n")
        assert wait_until(lambda: read_file(email_log).count("Subject: CPU Alert") > restarted_count, 2.2), (
            "Restarted monitor.py did not send the second alert"
        )
    finally:
        stop_services()


def load_captured(path):
    records = []
    if not os.path.exists(path):
        return records
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def message_body(msg):
    if msg.is_multipart():
        part = msg.get_body(preferencelist=("plain",))
        return part.get_content().strip() if part else ""
    return msg.get_content().strip()


def monitor_command():
    data = open("/home/user/monitor.py", "rb").read(256)
    first = data.splitlines()[0] if data else b""
    if first.startswith(b"#!"):
        return ["/home/user/monitor.py"]
    if b"bash" in first or b"/sh" in first:
        return ["bash", "/home/user/monitor.py"]
    return ["python3", "/home/user/monitor.py"]


def test_monitor_uses_smtp_and_crossing_semantics():
    cpu_file = "/home/user/cpu.txt"
    capture = "/tmp/verifier_smtp_capture.jsonl"
    stop_services()
    for path in (capture, cpu_file):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    smtp_proc = subprocess.Popen(["python3", "/tmp/verifier_smtp.py", capture],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    monitor_proc = None
    try:
        def port_open():
            with socket.create_connection(("127.0.0.1", 10025), timeout=0.2):
                return True
        assert wait_until(port_open, 3), "Verifier SMTP server could not bind port 10025"

        env = os.environ.copy()
        env.update({"ALERT_THRESHOLD": "90", "ALERT_EMAIL": "admin@local.dev"})
        monitor_proc = subprocess.Popen(monitor_command(), env=env, cwd="/home/user",
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        start_new_session=True)

        time.sleep(1.3)
        assert len(load_captured(capture)) == 0, "Missing cpu.txt must be treated as zero"

        with open(cpu_file, "w") as f:
            f.write("90\n")
        time.sleep(1.3)
        assert len(load_captured(capture)) == 0, "A value equal to the threshold must not alert"

        high = random.randint(91, 500)
        started = time.monotonic()
        with open(cpu_file, "w") as f:
            f.write(f"{high}\n")
        assert wait_until(lambda: len(load_captured(capture)) >= 1, 1.8), (
            "monitor.py did not poll and send through SMTP within the one-second polling interval"
        )
        assert time.monotonic() - started <= 1.8

        first = load_captured(capture)[0]
        assert first["mail_from"].lower() == "monitor@local.dev", "Incorrect SMTP envelope sender"
        assert [x.lower() for x in first["rcpt_tos"]] == ["admin@local.dev"], "Incorrect SMTP recipient"
        raw = base64.b64decode(first["data"])
        msg = email.message_from_bytes(raw, policy=policy.default)
        assert msg["From"].addresses[0].addr_spec.lower() == "monitor@local.dev"
        assert msg["To"].addresses[0].addr_spec.lower() == "admin@local.dev"
        assert msg["Subject"] == "CPU Alert"
        assert message_body(msg) == "Threshold exceeded"

        time.sleep(2.2)
        assert len(load_captured(capture)) == 1, "Repeated alerts were sent while CPU stayed above threshold"

        low = random.randint(0, 90)
        with open(cpu_file, "w") as f:
            f.write(f"{low}\n")
        time.sleep(1.3)
        assert len(load_captured(capture)) == 1

        with open(cpu_file, "w") as f:
            f.write(f"{random.randint(91, 500)}\n")
        assert wait_until(lambda: len(load_captured(capture)) == 2, 1.8), (
            "Monitor did not re-arm after the value dropped to or below the threshold"
        )
        time.sleep(1.2)
        assert len(load_captured(capture)) == 2, "More than one alert was sent for one threshold crossing"
    finally:
        if monitor_proc is not None:
            try:
                os.killpg(monitor_proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        smtp_proc.kill()
        try:
            smtp_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        stop_services()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
