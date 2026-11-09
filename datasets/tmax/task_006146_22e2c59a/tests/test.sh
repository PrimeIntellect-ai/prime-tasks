#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import stat
import subprocess
import threading
import time


class DummySMTPServer(threading.Thread):
    def __init__(self, host='127.0.0.1', port=8025, timeout=10):
        super().__init__()
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.host, self.port))
        self.sock.listen(1)
        self.sock.settimeout(timeout)
        self.data_received = ""
        self.error = None
        self.connected = False

    def run(self):
        try:
            conn, _ = self.sock.accept()
            self.connected = True
            conn.settimeout(5)
            conn.sendall(b"220 localhost ESMTP\r\n")
            in_data = False
            pending = ""
            while True:
                try:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    text = chunk.decode('utf-8', errors='ignore')
                    self.data_received += text
                    pending += text
                    while '\n' in pending:
                        line, pending = pending.split('\n', 1)
                        line = line.rstrip('\r')
                        if in_data:
                            if line == ".":
                                in_data = False
                                conn.sendall(b"250 OK\r\n")
                        else:
                            upper_line = line.upper()
                            if upper_line.startswith("HELO") or upper_line.startswith("EHLO"):
                                conn.sendall(b"250 Hello\r\n")
                            elif upper_line.startswith("MAIL FROM"):
                                conn.sendall(b"250 OK\r\n")
                            elif upper_line.startswith("RCPT TO"):
                                conn.sendall(b"250 OK\r\n")
                            elif upper_line.startswith("DATA"):
                                conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                                in_data = True
                            elif upper_line.startswith("QUIT"):
                                conn.sendall(b"221 Bye\r\n")
                                conn.close()
                                return
                except socket.timeout:
                    break
            conn.close()
        except socket.timeout:
            pass
        except Exception as e:
            self.error = e
        finally:
            self.sock.close()


def first_line(path):
    with open(path, "r", errors="ignore") as f:
        return f.readline().strip().lower()


def test_expect_script_exists_and_executable():
    path = "/home/user/check_link.exp"
    assert os.path.exists(path), f"Expect script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."
    assert "expect" in first_line(path), f"{path} is not an executable Expect script."


def test_monitor_script_exists_and_executable():
    path = "/home/user/monitor.sh"
    assert os.path.exists(path), f"Bash script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."
    assert "bash" in first_line(path), f"{path} is not an executable Bash script."


def test_git_repo_and_hook_exists():
    repo_dir = "/home/user/net-logs"
    hook_path = os.path.join(repo_dir, ".git/hooks/post-commit")
    assert os.path.isdir(os.path.join(repo_dir, ".git")), f"Git repository not initialized at {repo_dir}."
    assert os.path.exists(hook_path), f"post-commit hook does not exist at {hook_path}."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"post-commit hook {hook_path} is not executable."
    assert "python" in first_line(hook_path), f"post-commit hook {hook_path} is not written as an executable Python script."
    compiled = subprocess.run(["python3", "-m", "py_compile", hook_path], capture_output=True, text=True)
    assert compiled.returncode == 0, f"post-commit hook is not valid Python: {compiled.stderr}"


def test_workflow_up_and_down_states():
    force_down_path = "/home/user/force_down"
    repo_dir = "/home/user/net-logs"
    status_file = os.path.join(repo_dir, "status.txt")
    monitor_script = "/home/user/monitor.sh"

    if os.path.exists(force_down_path):
        os.remove(force_down_path)

    result = subprocess.run([monitor_script], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"{monitor_script} failed with output: {result.stderr}"

    assert os.path.exists(status_file), f"{status_file} was not created."
    with open(status_file, "r") as f:
        status_content = f.read().strip()
    assert status_content == "UP", f"Expected 'UP' in {status_file}, got '{status_content}'"

    git_log = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=repo_dir, capture_output=True, text=True)
    assert "Status: UP" in git_log.stdout, f"Expected commit message 'Status: UP', got '{git_log.stdout.strip()}'"

    smtp_server = DummySMTPServer()
    smtp_server.start()
    time.sleep(0.2)

    try:
        with open(force_down_path, "w") as f:
            f.write("")

        result = subprocess.run([monitor_script], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"{monitor_script} failed on DOWN test with output: {result.stderr}"

        with open(status_file, "r") as f:
            status_content = f.read().strip()
        assert status_content == "DOWN", f"Expected 'DOWN' in {status_file}, got '{status_content}'"

        git_log = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=repo_dir, capture_output=True, text=True)
        assert "Status: DOWN" in git_log.stdout, f"Expected commit message 'Status: DOWN', got '{git_log.stdout.strip()}'"
    finally:
        if os.path.exists(force_down_path):
            os.remove(force_down_path)

    smtp_server.join(timeout=12)
    assert smtp_server.error is None, f"SMTP test server failed: {smtp_server.error}"
    email_data = smtp_server.data_received
    assert "monitor@local.net" in email_data, "Sender 'monitor@local.net' not found in SMTP transaction."
    assert "net-admins@local.net" in email_data, "Recipient 'net-admins@local.net' not found in SMTP transaction."
    assert "Subject: ALERT: Link is DOWN" in email_data, "Subject 'ALERT: Link is DOWN' not found in SMTP transaction."


def test_expect_script_performs_required_console_interaction():
    appliance = "/home/user/appliance.py"
    expect_script = "/home/user/check_link.exp"
    log_path = f"/tmp/appliance-interaction-{secrets.token_hex(8)}.json"
    expected_state = "DOWN" if secrets.randbits(1) else "UP"
    original = open(appliance, "rb").read()
    original_mode = stat.S_IMODE(os.stat(appliance).st_mode)

    challenge = f'''#!/usr/bin/env python3
import json
log_path = {log_path!r}
answers = []
try:
    print("Welcome to ChallengeRouter", flush=True)
    answers.append(input("Username: "))
    answers.append(input("Password: "))
    answers.append(input("router# ").strip())
    if answers == ["admin", "netadmin99", "check-uplink"]:
        print("Uplink is {expected_state}", flush=True)
    answers.append(input("router# ").strip())
finally:
    with open(log_path, "w") as f:
        json.dump(answers, f)
'''
    try:
        with open(appliance, "w") as f:
            f.write(challenge)
        os.chmod(appliance, 0o755)
        result = subprocess.run([expect_script], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"Expect script failed against the appliance: {result.stderr}"
        assert os.path.exists(log_path), "Expect script did not execute /home/user/appliance.py."
        with open(log_path) as f:
            interaction = json.load(f)
        assert interaction == ["admin", "netadmin99", "check-uplink", "exit"], f"Incorrect appliance interaction: {interaction}"
        assert f"Uplink is {expected_state}" in result.stdout, "Expect script did not capture the appliance response."
    finally:
        with open(appliance, "wb") as f:
            f.write(original)
        os.chmod(appliance, original_mode)
        if os.path.exists(log_path):
            os.remove(log_path)


def write_probe(path, marker, state):
    with open(path, "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"printf '%s' invoked > {marker!r}\n")
        f.write(f"printf '%s\\n' 'Uplink is {state}'\n")
    os.chmod(path, 0o755)


def test_monitor_uses_expect_output_and_does_not_send_email_itself():
    expect_path = "/home/user/check_link.exp"
    hook_path = "/home/user/net-logs/.git/hooks/post-commit"
    monitor = "/home/user/monitor.sh"
    repo = "/home/user/net-logs"
    status_path = os.path.join(repo, "status.txt")
    force_down = "/home/user/force_down"
    marker = f"/tmp/expect-probe-{secrets.token_hex(8)}"

    expect_original = open(expect_path, "rb").read()
    expect_mode = stat.S_IMODE(os.stat(expect_path).st_mode)
    hook_original = open(hook_path, "rb").read()
    hook_mode = stat.S_IMODE(os.stat(hook_path).st_mode)

    try:
        with open(hook_path, "w") as f:
            f.write("#!/usr/bin/env python3\n")
            f.write("pass\n")
        os.chmod(hook_path, 0o755)

        with open(force_down, "w") as f:
            f.write("")
        write_probe(expect_path, marker, "UP")
        result = subprocess.run([monitor], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"monitor.sh failed with probe Expect output: {result.stderr}"
        assert os.path.exists(marker), "monitor.sh did not run /home/user/check_link.exp."
        assert open(status_path).read().strip() == "UP", "monitor.sh did not derive UP from the Expect script output."
        message = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=repo, capture_output=True, text=True).stdout.strip()
        assert message == "Status: UP", f"Expected exact commit message 'Status: UP', got {message!r}"

        os.remove(marker)
        os.remove(force_down)
        write_probe(expect_path, marker, "DOWN")
        smtp_server = DummySMTPServer(timeout=2)
        smtp_server.start()
        time.sleep(0.2)
        result = subprocess.run([monitor], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"monitor.sh failed with DOWN probe output: {result.stderr}"
        assert os.path.exists(marker), "monitor.sh did not run /home/user/check_link.exp for DOWN."
        assert open(status_path).read().strip() == "DOWN", "monitor.sh did not derive DOWN from the Expect script output."
        message = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=repo, capture_output=True, text=True).stdout.strip()
        assert message == "Status: DOWN", f"Expected exact commit message 'Status: DOWN', got {message!r}"
        smtp_server.join(timeout=4)
        assert smtp_server.error is None, f"SMTP test server failed: {smtp_server.error}"
        assert not smtp_server.connected, "monitor.sh sent SMTP mail directly while the post-commit hook was disabled."
    finally:
        with open(expect_path, "wb") as f:
            f.write(expect_original)
        os.chmod(expect_path, expect_mode)
        with open(hook_path, "wb") as f:
            f.write(hook_original)
        os.chmod(hook_path, hook_mode)
        if os.path.exists(force_down):
            os.remove(force_down)
        if os.path.exists(marker):
            os.remove(marker)


def commit_probe(repo, message, token):
    probe = os.path.join(repo, ".hook-verifier-probe")
    with open(probe, "w") as f:
        f.write(token)
    subprocess.run(["git", "add", ".hook-verifier-probe"], cwd=repo, check=True, capture_output=True, text=True)
    return subprocess.run(["git", "commit", "-m", message], cwd=repo, capture_output=True, text=True, timeout=20)


def test_post_commit_hook_itself_controls_email_alerts():
    repo = "/home/user/net-logs"

    up_server = DummySMTPServer(timeout=2)
    up_server.start()
    time.sleep(0.2)
    result = commit_probe(repo, "Status: UP", secrets.token_hex(12))
    assert result.returncode == 0, f"Could not create UP hook test commit: {result.stderr}"
    up_server.join(timeout=4)
    assert up_server.error is None, f"SMTP test server failed: {up_server.error}"
    assert not up_server.connected, "post-commit hook sent an email for 'Status: UP'."

    down_server = DummySMTPServer(timeout=8)
    down_server.start()
    time.sleep(0.2)
    result = commit_probe(repo, "Status: DOWN", secrets.token_hex(12))
    assert result.returncode == 0, f"Could not create DOWN hook test commit: {result.stderr}"
    down_server.join(timeout=10)
    assert down_server.error is None, f"SMTP test server failed: {down_server.error}"
    assert down_server.connected, "post-commit hook did not connect to SMTP for a direct 'Status: DOWN' commit."
    email_data = down_server.data_received
    assert "MAIL FROM:<monitor@local.net>".lower() in email_data.lower(), "Hook used the wrong SMTP envelope sender."
    assert "RCPT TO:<net-admins@local.net>".lower() in email_data.lower(), "Hook used the wrong SMTP envelope recipient."
    assert "Subject: ALERT: Link is DOWN" in email_data, "Hook email used the wrong subject."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
