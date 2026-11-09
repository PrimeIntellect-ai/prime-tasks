#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import socket
import threading
import subprocess
from datetime import datetime, timezone
try:
    import zoneinfo
except ImportError:
    from backports import zoneinfo

import pytest

class MockSMTPServer(threading.Thread):
    def __init__(self, port=8025):
        super().__init__(daemon=True)
        self.port = port
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(('127.0.0.1', self.port))
        self.server.listen(1)
        self.server.settimeout(0.5)
        self.running = True
        self.emails = []

    def run(self):
        while self.running:
            try:
                conn, addr = self.server.accept()
                self.handle_client(conn)
            except socket.timeout:
                continue
            except Exception:
                break

    def handle_client(self, conn):
        conn.settimeout(2.0)
        try:
            conn.sendall(b"220 mock.local ESMTP\r\n")
            data_mode = False
            email_lines = []
            buffer = ""
            while self.running:
                chunk = conn.recv(1024).decode('utf-8', errors='ignore')
                if not chunk:
                    break
                buffer += chunk
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.rstrip('\r')
                    if data_mode:
                        if line == '.':
                            data_mode = False
                            conn.sendall(b"250 OK\r\n")
                            self.emails.append('\n'.join(email_lines))
                            email_lines = []
                        else:
                            email_lines.append(line)
                    else:
                        upper_line = line.upper()
                        if upper_line.startswith('DATA'):
                            data_mode = True
                            conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                        elif upper_line.startswith('QUIT'):
                            conn.sendall(b"221 Bye\r\n")
                            return
                        else:
                            conn.sendall(b"250 OK\r\n")
        except Exception:
            pass
        finally:
            conn.close()

    def stop(self):
        self.running = False
        self.server.close()

@pytest.fixture(scope="module")
def smtp_server():
    server = MockSMTPServer(port=8025)
    server.start()
    yield server
    server.stop()
    server.join()

def test_fstab_entry():
    fstab_path = '/home/user/fstab_entry.txt'
    assert os.path.exists(fstab_path), f"File {fstab_path} does not exist."
    with open(fstab_path, 'r') as f:
        content = f.read().strip()

    assert content, "fstab_entry.txt is empty."
    lines = [line for line in content.splitlines() if line.strip() and not line.strip().startswith('#')]
    assert len(lines) == 1, "fstab_entry.txt should contain exactly one fstab entry."

    parts = lines[0].split()
    assert len(parts) >= 4, "fstab entry is malformed. Needs at least 4 fields."

    assert parts[0] == '/home/user/app_data/run', f"Expected source /home/user/app_data/run, got {parts[0]}"
    assert parts[1] == '/home/user/run', f"Expected target /home/user/run, got {parts[1]}"

    # Check if 'bind' is present in either the type field or options field
    assert 'bind' in parts[2] or 'bind' in parts[3], "The fstab entry must specify a bind mount."

def test_monitor_script_missing_socket(smtp_server):
    script_path = '/home/user/monitor.py'
    sock_path = '/home/user/run/app.sock'

    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    if os.path.exists(sock_path):
        os.remove(sock_path)

    smtp_server.emails.clear()

    result = subprocess.run(['python3', script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script exited with error:\n{result.stderr}"

    assert len(smtp_server.emails) == 1, "Script should have sent exactly one email when socket is missing."
    email_content = smtp_server.emails[0]

    assert "From: monitor@local" in email_content, "Missing or incorrect From address."
    assert "To: admin@local" in email_content, "Missing or incorrect To address."
    assert "Subject: Alert: Socket Missing" in email_content, "Missing or incorrect Subject."

    match = re.search(r'Error at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', email_content)
    assert match, "Email body does not contain 'Error at <timestamp>' in the correct format."

    timestamp_str = match.group(1)
    try:
        dt = datetime.strptime(timestamp_str, '%Y-%m-%d %H:%M:%S')
    except ValueError:
        pytest.fail(f"Timestamp format is incorrect: {timestamp_str}")

    # Verify timezone logic (Europe/Berlin)
    tz = zoneinfo.ZoneInfo("Europe/Berlin")
    now_berlin = datetime.now(timezone.utc).astimezone(tz)

    # The naive datetime from the email should match the current Berlin time closely
    dt_berlin = dt.replace(tzinfo=tz)
    diff = abs((now_berlin - dt_berlin).total_seconds())
    assert diff < 120, f"Timestamp {timestamp_str} is not a valid current time in Europe/Berlin."

def test_monitor_script_existing_socket(smtp_server):
    script_path = '/home/user/monitor.py'
    sock_path = '/home/user/run/app.sock'

    os.makedirs(os.path.dirname(sock_path), exist_ok=True)
    with open(sock_path, 'w') as f:
        f.write("mock socket")

    smtp_server.emails.clear()

    result = subprocess.run(['python3', script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script exited with error:\n{result.stderr}"

    assert len(smtp_server.emails) == 0, "Script should not send an email when the socket exists."

    os.remove(sock_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
