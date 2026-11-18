#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import signal
import string
import subprocess
import time
import urllib.request
import uuid

import pytest
import redis

PIPELINE = "/home/user/pipeline"
SETUP = os.path.join(PIPELINE, "setup.sh")
ORACLE = "/app/oracle_parser"
PARSER = os.path.join(PIPELINE, "parser_daemon.py")


def backup_files():
    root = os.path.join(PIPELINE, "backups")
    if not os.path.isdir(root):
        return []
    return [p for p in glob.glob(os.path.join(root, "**"), recursive=True) if os.path.isfile(p)]


def run_setup():
    subprocess.run(
        ["/bin/bash", SETUP],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=True,
    )


def read_pid(path):
    with open(path, "r") as f:
        text = f.read().strip()
    assert text.isdigit(), f"{path} does not contain a numeric PID."
    pid = int(text)
    assert pid > 1, f"Invalid PID in {path}."
    os.kill(pid, 0)
    return pid


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode("utf-8", errors="replace")


def wait_until(predicate, timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    if last_error:
        raise AssertionError(f"Condition was not met before timeout: {last_error}")
    raise AssertionError("Condition was not met before timeout.")


def test_00_setup_exists_is_idempotent_and_backs_up_webhook():
    assert os.path.isfile(SETUP), f"Setup script {SETUP} does not exist."
    with open(SETUP, "rb") as f:
        assert f.read(2) == b"#!", "setup.sh must be a shell script with a shebang."

    webhook = "/app/webhook.py"
    assert os.path.isfile(webhook), f"Webhook source {webhook} is missing."
    with open(webhook, "rb") as f:
        webhook_before = f.read()

    run_setup()
    time.sleep(1.1)
    run_setup()

    backups = backup_files()
    assert backups, "setup.sh did not create a backup of /app/webhook.py."
    matching = []
    for path in backups:
        try:
            with open(path, "rb") as f:
                if f.read() == webhook_before:
                    matching.append(path)
        except OSError:
            pass
    assert matching, "No backup contains the webhook source that existed before setup.sh ran."
    assert any("webhook" in os.path.basename(p).lower() for p in matching), \
        "The webhook backup is not identified as a webhook backup."


def test_users_json():
    users_file = "/home/user/pipeline/users.json"
    assert os.path.isfile(users_file), f"{users_file} does not exist."
    with open(users_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{users_file} is not valid JSON.")

    assert data.get("netadmin") == "netops", "User 'netadmin' is not mapped to 'netops' in users.json."
    assert data.get("backup_svc") == "backup", "User 'backup_svc' is not mapped to 'backup' in users.json."


def test_directories_created():
    backups_dir = "/home/user/pipeline/backups"
    logs_dir = "/home/user/pipeline/logs"
    assert os.path.isdir(backups_dir), f"Directory {backups_dir} was not created."
    assert os.path.isdir(logs_dir), f"Directory {logs_dir} was not created."


def test_pid_files_exist():
    flask_pid = "/home/user/pipeline/flask.pid"
    daemon_pid = "/home/user/pipeline/daemon.pid"
    assert os.path.isfile(flask_pid), f"Flask PID file {flask_pid} is missing."
    assert os.path.isfile(daemon_pid), f"Daemon PID file {daemon_pid} is missing."

    flask = read_pid(flask_pid)
    daemon = read_pid(daemon_pid)
    flask_cmd = cmdline(flask).lower()
    daemon_cmd = cmdline(daemon)
    assert "waitress" in flask_cmd or "gunicorn" in flask_cmd, \
        f"Flask PID {flask} is not a Waitress or Gunicorn process: {flask_cmd}"
    assert "parser_daemon.py" in daemon_cmd, \
        f"Daemon PID {daemon} is not running parser_daemon.py: {daemon_cmd}"


def test_redis_requires_netpass():
    unauthenticated = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    with pytest.raises(redis.exceptions.AuthenticationError):
        unauthenticated.ping()

    authenticated = redis.Redis(
        host="127.0.0.1", port=6379, db=0, password="netpass", socket_timeout=2
    )
    assert authenticated.ping() is True


def test_webhook_and_daemon_end_to_end():
    token = "marker" + uuid.uuid4().hex
    payload = f"zeta:{token}\ninterface=GigabitEthernet999\nalpha:value"
    oracle_proc = subprocess.run(
        [ORACLE], input=payload.encode("utf-8"), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, check=True
    )
    expected = oracle_proc.stdout
    assert expected, "Oracle unexpectedly produced empty output for the integration payload."

    log_path = os.path.join(PIPELINE, "logs", "processed.log")
    before_size = os.path.getsize(log_path) if os.path.isfile(log_path) else 0

    def submit():
        request = urllib.request.Request(
            "http://127.0.0.1:8080/submit",
            data=payload.encode("utf-8"),
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=2) as response:
            body = response.read()
            assert response.status == 200
            assert body == b"OK"
        return True

    wait_until(submit, timeout=15)

    def output_arrived():
        if not os.path.isfile(log_path):
            return False
        with open(log_path, "rb") as f:
            f.seek(min(before_size, os.path.getsize(log_path)))
            appended = f.read()
        return expected in appended

    wait_until(output_arrived, timeout=15)


def test_fuzz_equivalence():
    oracle_path = "/app/oracle_parser"
    agent_cmd = ["/usr/bin/python3", "/home/user/pipeline/parser_daemon.py", "--test-mode"]

    assert os.path.isfile(oracle_path), f"Oracle parser {oracle_path} missing."
    assert os.path.isfile(agent_cmd[1]), f"Agent parser {agent_cmd[1]} missing."

    random.seed(42)
    charset = string.ascii_letters + string.digits + ".:-_\n{}"

    for i in range(1000):
        length = random.randint(50, 500)
        inp = "".join(random.choices(charset, k=length))

        oracle_proc = subprocess.run(
            [oracle_path],
            input=inp.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            agent_cmd,
            input=inp.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        agent_out = agent_proc.stdout

        assert oracle_proc.returncode == 0, f"Oracle failed on random input #{i}."
        assert agent_proc.returncode == 0, f"Agent parser failed on random input #{i}: {agent_proc.stderr!r}"

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch found on random input #{i}!\n"
                f"Input:\n{inp}\n"
                f"Oracle Output:\n{oracle_out.decode('utf-8', errors='replace')}\n"
                f"Agent Output:\n{agent_out.decode('utf-8', errors='replace')}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
