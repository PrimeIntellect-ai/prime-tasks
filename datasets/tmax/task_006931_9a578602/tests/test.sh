#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import threading
import time
import uuid
from email import policy
from email.parser import BytesParser

import pytest

DEPLOY_SCRIPT = "/home/user/deploy.py"
CRON_FILE = "/home/user/schedule.cron"
STAGING_DIR = "/home/user/staging"
PRODUCTION_DIR = "/home/user/production"
BACKUP_DIR = "/home/user/backup"
LOG_FILE = "/home/user/deploy_log.json"


class CapturingSMTPServer(threading.Thread):
    def __init__(self, host="127.0.0.1", port=1025):
        super().__init__(daemon=True)
        self.host = host
        self.port = port
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((host, port))
        self.server_socket.listen(5)
        self.server_socket.settimeout(0.2)
        self.running = True
        self.received_data = ""
        self.mail_from = None
        self.rcpt_to = []
        self.message_bytes = None
        self.error = None

    def run(self):
        try:
            while self.running and self.message_bytes is None:
                try:
                    conn, _ = self.server_socket.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                with conn:
                    conn.settimeout(2)
                    conn.sendall(b"220 localhost ESMTP\r\n")
                    buf = b""
                    in_data = False
                    data_lines = []
                    while self.running:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        self.received_data += chunk.decode("utf-8", errors="replace")
                        buf += chunk
                        while b"\n" in buf:
                            raw_line, buf = buf.split(b"\n", 1)
                            line = raw_line.rstrip(b"\r")
                            if in_data:
                                if line == b".":
                                    self.message_bytes = b"\r\n".join(data_lines)
                                    in_data = False
                                    conn.sendall(b"250 Message accepted\r\n")
                                    continue
                                if line.startswith(b".."):
                                    line = line[1:]
                                data_lines.append(line)
                                continue

                            text = line.decode("utf-8", errors="replace")
                            upper = text.upper()
                            if upper.startswith("EHLO"):
                                conn.sendall(b"250-localhost\r\n250 SIZE 10485760\r\n")
                            elif upper.startswith("HELO"):
                                conn.sendall(b"250 localhost\r\n")
                            elif upper.startswith("MAIL FROM:"):
                                match = re.match(r"MAIL FROM:\s*<([^>]*)>", text, re.I)
                                self.mail_from = match.group(1) if match else None
                                conn.sendall(b"250 OK\r\n")
                            elif upper.startswith("RCPT TO:"):
                                match = re.match(r"RCPT TO:\s*<([^>]*)>", text, re.I)
                                self.rcpt_to.append(match.group(1) if match else None)
                                conn.sendall(b"250 OK\r\n")
                            elif upper == "DATA":
                                in_data = True
                                data_lines = []
                                conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                            elif upper == "RSET":
                                self.mail_from = None
                                self.rcpt_to = []
                                conn.sendall(b"250 OK\r\n")
                            elif upper == "QUIT":
                                conn.sendall(b"221 Bye\r\n")
                                break
                            else:
                                conn.sendall(b"250 OK\r\n")
        except Exception as exc:
            self.error = exc

    def stop(self):
        self.running = False
        try:
            self.server_socket.close()
        except OSError:
            pass
        self.join(timeout=3)


def reset_directory(path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY_SCRIPT), f"{DEPLOY_SCRIPT} does not exist."
    st = os.stat(DEPLOY_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{DEPLOY_SCRIPT} is not executable."

    with open(DEPLOY_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=DEPLOY_SCRIPT)
    imports_smtplib = any(
        (isinstance(node, ast.Import) and any(alias.name == "smtplib" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "smtplib")
        for node in ast.walk(tree)
    )
    assert imports_smtplib, "deploy.py must use Python's built-in smtplib."


def test_cron_file_content():
    assert os.path.isfile(CRON_FILE), f"{CRON_FILE} does not exist."
    with open(CRON_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original checks.
    assert "15 2 * * 0" in content, f"Cron expression '15 2 * * 0' not found in {CRON_FILE}."
    assert DEPLOY_SCRIPT in content, f"Script path {DEPLOY_SCRIPT} not found in {CRON_FILE}."

    active_lines = [line.strip() for line in content.splitlines()
                    if line.strip() and not line.lstrip().startswith("#")]
    assert len(active_lines) == 1, "schedule.cron must contain exactly one active crontab line."
    fields = active_lines[0].split()
    assert fields == ["15", "2", "*", "*", "0", "/usr/bin/env", "python3", DEPLOY_SCRIPT], (
        "Cron job must run '/usr/bin/env python3 /home/user/deploy.py' at 2:15 AM every Sunday."
    )


def test_deploy_script_execution_and_effects():
    reset_directory(STAGING_DIR)
    reset_directory(PRODUCTION_DIR)
    shutil.rmtree(BACKUP_DIR, ignore_errors=True)

    token = uuid.uuid4().hex
    production_files = {
        "app_v1.py": b"old fixture content\n",
        f"old_{token}.bin": os.urandom(97),
        f".hidden_old_{token}": b"hidden production file",
    }
    staging_files = {
        "app_v2.py": b"new app fixture\n",
        "config.yml": b"version: fixture\n",
        f"release_{token}.dat": os.urandom(131),
        f"notes {token}.txt": b"filename containing spaces",
        f".hidden_new_{token}": b"hidden staging file",
    }
    for name, data in production_files.items():
        with open(os.path.join(PRODUCTION_DIR, name), "wb") as f:
            f.write(data)
    for name, data in staging_files.items():
        with open(os.path.join(STAGING_DIR, name), "wb") as f:
            f.write(data)

    sentinel = json.dumps({"preexisting": token}, separators=(",", ":")) + "\n"
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write(sentinel)

    smtp_server = CapturingSMTPServer()
    smtp_server.start()
    before = time.time()
    try:
        result = subprocess.run([DEPLOY_SCRIPT], capture_output=True, text=True, timeout=15)
        after = time.time()
        assert result.returncode == 0, (
            f"Script exited with status {result.returncode}. Stderr: {result.stderr}"
        )
        deadline = time.time() + 2
        while smtp_server.message_bytes is None and time.time() < deadline:
            time.sleep(0.02)
    finally:
        smtp_server.stop()

    assert smtp_server.error is None, f"SMTP test server failed: {smtp_server.error}"

    # Preserve the original fixture assertions.
    assert os.path.isdir(BACKUP_DIR), f"{BACKUP_DIR} was not created."
    assert os.path.isfile(os.path.join(BACKUP_DIR, "app_v1.py")), "app_v1.py was not moved to backup."
    assert not os.path.exists(os.path.join(PRODUCTION_DIR, "app_v1.py")), "app_v1.py was not removed from production."
    assert os.path.isfile(os.path.join(PRODUCTION_DIR, "app_v2.py")), "app_v2.py was not copied to production."
    assert os.path.isfile(os.path.join(PRODUCTION_DIR, "config.yml")), "config.yml was not copied to production."

    # Check every dynamically generated file and its contents.
    assert set(os.listdir(BACKUP_DIR)) == set(production_files), "Not all production files were moved to backup."
    assert set(os.listdir(PRODUCTION_DIR)) == set(staging_files), "Production is not an exact copy of staging files."
    assert set(os.listdir(STAGING_DIR)) == set(staging_files), "Copying must not remove staging files."
    for name, expected in production_files.items():
        with open(os.path.join(BACKUP_DIR, name), "rb") as f:
            assert f.read() == expected, f"Backup content changed for {name}."
    for name, expected in staging_files.items():
        with open(os.path.join(PRODUCTION_DIR, name), "rb") as f:
            assert f.read() == expected, f"Copied content is incorrect for {name}."
        with open(os.path.join(STAGING_DIR, name), "rb") as f:
            assert f.read() == expected, f"Staging content changed for {name}."

    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        log_text = f.read()
    assert log_text.startswith(sentinel), "The deployment log was overwritten instead of appended."
    lines = log_text.splitlines()
    assert len(lines) > 0, f"{LOG_FILE} is empty."
    assert len(lines) == 2, "A deployment must append exactly one single-line JSON object."
    try:
        log_data = json.loads(lines[-1])
    except json.JSONDecodeError:
        pytest.fail(f"Last line of {LOG_FILE} is not valid JSON.")

    # Preserve the original log assertions and enforce the exact schema/list.
    assert log_data.get("status") == "success", "Log JSON 'status' is not 'success'."
    assert "files" in log_data, "Log JSON missing 'files' key."
    assert "app_v2.py" in log_data["files"], "app_v2.py not found in log 'files' list."
    assert "timestamp" in log_data, "Log JSON missing 'timestamp' key."
    assert isinstance(log_data["timestamp"], float), "Log JSON 'timestamp' is not a float."
    assert set(log_data.keys()) == {"status", "files", "timestamp"}, "Log JSON schema has missing or extra keys."
    assert isinstance(log_data["files"], list), "Log JSON 'files' must be a list."
    assert len(log_data["files"]) == len(staging_files) and set(log_data["files"]) == set(staging_files), (
        "Log JSON 'files' must list every copied filename exactly once."
    )
    assert before <= log_data["timestamp"] <= after, "Log timestamp is not the current deployment time."

    # Preserve the original SMTP traffic assertions.
    email_data = smtp_server.received_data
    assert "deploy@company.local" in email_data, "Envelope sender 'deploy@company.local' not found in SMTP traffic."
    assert "eng-mailing-list@company.local" in email_data, "Recipient 'eng-mailing-list@company.local' not found in SMTP traffic."
    assert "Subject: Deployment Update" in email_data, "Email subject 'Deployment Update' not found."
    assert "New release deployed successfully." in email_data, "Email body not found in SMTP traffic."

    assert smtp_server.mail_from == "deploy@company.local", "Incorrect SMTP envelope sender."
    assert smtp_server.rcpt_to == ["eng-mailing-list@company.local"], "Incorrect SMTP envelope recipient(s)."
    assert smtp_server.message_bytes is not None, "No SMTP DATA message was received."
    message = BytesParser(policy=policy.default).parsebytes(smtp_server.message_bytes)
    assert message.get_all("From") == ["deploy@company.local"], "Email From field is not exact."
    assert message.get_all("To") == ["eng-mailing-list@company.local"], "Email To field is not exact."
    assert message.get_all("Subject") == ["Deployment Update"], "Email subject is not exact."
    assert not message.is_multipart(), "Notification body must be a single exact text body."
    body = message.get_content()
    expected_body = "New release deployed successfully."
    assert body in (expected_body, expected_body + "\n", expected_body + "\r\n"), "Email body is not exact."


def test_missing_staging_exits_one():
    saved = STAGING_DIR + ".verifier_saved_" + uuid.uuid4().hex
    if os.path.exists(saved):
        shutil.rmtree(saved)
    os.rename(STAGING_DIR, saved)
    try:
        result = subprocess.run([DEPLOY_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 1, "deploy.py must exit with status 1 when staging does not exist."
    finally:
        if os.path.exists(STAGING_DIR):
            shutil.rmtree(STAGING_DIR)
        os.rename(saved, STAGING_DIR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
