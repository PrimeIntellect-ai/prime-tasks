#!/bin/bash
set -e
mkdir -p /logs/verifier

cleanup() {
    timeout 5 supervisorctl -c /home/user/supervisord.conf shutdown >/dev/null 2>&1 || true
    pkill -f '[s]mtp_receiver.py' >/dev/null 2>&1 || true
    pkill -f '[a]rchive_worker.py' >/dev/null 2>&1 || true
    pkill -x redis-server >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import filecmp
import grp
import os
import pwd
import random
import smtplib
import stat
import subprocess
import time

import redis

CONFIG = "/home/user/supervisord.conf"
ORACLE = "/app/oracle/obfuscator_oracle"
SOURCE = "/home/user/obfuscator.c"
BINARY = "/home/user/obfuscator"


def transform(data):
    return bytes(byte ^ 0x5A for byte in data[:1024][::-1])


def supervisorctl(*args, check=True):
    return subprocess.run(
        ["supervisorctl", "-c", CONFIG, *args],
        text=True,
        capture_output=True,
        check=check,
    )


def supervisor_pid(name):
    result = supervisorctl("pid", name, check=False)
    try:
        return int(result.stdout.strip())
    except ValueError:
        return 0


def wait_until(predicate, timeout=15, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def test_user_and_group():
    try:
        group_info = grp.getgrnam("archive_grp")
    except KeyError:
        assert False, "Group 'archive_grp' does not exist."

    try:
        user_info = pwd.getpwnam("archive_usr")
    except KeyError:
        assert False, "User 'archive_usr' does not exist."

    user_groups = [g.gr_name for g in grp.getgrall() if user_info.pw_name in g.gr_mem]
    if group_info.gr_name not in user_groups and user_info.pw_gid != group_info.gr_gid:
        assert False, "User 'archive_usr' is not a member of 'archive_grp'."


def test_source_compiles_and_obfuscator_matches():
    assert os.path.exists(SOURCE), f"Source file not found at {SOURCE}"
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} is not a regular file"

    assert os.path.exists(BINARY), f"Agent binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Agent binary at {BINARY} is not executable"
    assert not filecmp.cmp(BINARY, ORACLE, shallow=False), "Agent binary is a byte-identical copy of the oracle"

    compiled = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY], capture_output=True, text=True
    )
    assert compiled.returncode == 0, f"gcc failed:\n{compiled.stdout}\n{compiled.stderr}"
    assert os.access(BINARY, os.X_OK), f"Compiled binary at {BINARY} is not executable"

    fixed_inputs = [
        b"",
        b"a",
        b"legacy mailing list",
        bytes(range(256)),
        bytes(range(256)) * 4,
        bytes(range(256)) * 4 + b"ignored tail",
    ]
    random.seed(42)
    fuzz_inputs = [
        bytes(random.getrandbits(8) for _ in range(random.randint(0, 1024)))
        for _ in range(500)
    ]

    for i, input_data in enumerate(fixed_inputs + fuzz_inputs):
        oracle_proc = subprocess.run([ORACLE], input=input_data, capture_output=True)
        assert oracle_proc.returncode == 0, "Oracle failed to execute"

        agent_proc = subprocess.run([BINARY], input=input_data, capture_output=True)
        assert agent_proc.returncode == 0, f"Agent binary failed to execute on iteration {i}"
        assert agent_proc.stdout == transform(input_data), f"Derived output mismatch on iteration {i}"
        assert agent_proc.stdout == oracle_proc.stdout, f"Oracle output mismatch on iteration {i}"


def test_supervisord_config():
    assert os.path.exists(CONFIG), f"Config file not found at {CONFIG}"

    config = configparser.ConfigParser()
    try:
        config.read(CONFIG)
    except Exception as exc:
        assert False, f"Failed to parse {CONFIG}: {exc}"

    assert "program:redis" in config.sections(), "Missing [program:redis] section"
    redis_cmd = config.get("program:redis", "command", fallback="")
    assert "redis-server" in redis_cmd and "6379" in redis_cmd, "redis command is incorrect"

    assert "program:smtp_receiver" in config.sections(), "Missing [program:smtp_receiver] section"
    smtp_cmd = config.get("program:smtp_receiver", "command", fallback="")
    assert "smtp_receiver.py" in smtp_cmd, "smtp_receiver command is incorrect"
    assert config.get("program:smtp_receiver", "user", fallback="") == "archive_usr", "smtp_receiver user is not archive_usr"

    assert "program:archive_worker" in config.sections(), "Missing [program:archive_worker] section"
    worker_cmd = config.get("program:archive_worker", "command", fallback="")
    assert "archive_worker.py" in worker_cmd, "archive_worker command is incorrect"
    assert config.get("program:archive_worker", "user", fallback="") == "archive_usr", "archive_worker user is not archive_usr"

    env_str = config.get("program:archive_worker", "environment", fallback="")
    assert "OBFUSCATOR_BIN" in env_str and "/home/user/obfuscator" in env_str, "archive_worker environment missing OBFUSCATOR_BIN"


def test_supervised_end_to_end_mail_flow():
    launch = subprocess.run(["supervisord", "-c", CONFIG], capture_output=True, text=True)
    assert launch.returncode == 0, f"supervisord failed to launch:\n{launch.stdout}\n{launch.stderr}"

    def all_running():
        result = supervisorctl("status", check=False)
        text = result.stdout
        return result.returncode == 0 and all(
            name in text and any(
                line.startswith(name) and "RUNNING" in line
                for line in text.splitlines()
            )
            for name in ("redis", "smtp_receiver", "archive_worker")
        )

    assert wait_until(all_running), f"Services did not become RUNNING:\n{supervisorctl('status', check=False).stdout}"

    archive_uid = pwd.getpwnam("archive_usr").pw_uid
    for name in ("smtp_receiver", "archive_worker"):
        pid = supervisor_pid(name)
        assert pid > 0, f"No running PID for {name}"
        assert os.stat(f"/proc/{pid}").st_uid == archive_uid, f"{name} is not running as archive_usr"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    assert wait_until(lambda: client.ping()), "Redis did not accept connections"
    client.delete("mail_queue", "archive_latest")

    message = (
        b"From: backup@example.test\r\n"
        b"To: archive@example.test\r\n"
        b"Subject: restore verification\r\n"
        b"X-Token: end-to-end-7391\r\n"
        b"\r\n"
        b"Binary-like body: \\x00 and staged restore.\r\n"
    )

    with smtplib.SMTP("127.0.0.1", 2525, timeout=10) as smtp:
        refused = smtp.sendmail("backup@example.test", ["archive@example.test"], message)
    assert refused == {}, f"SMTP receiver refused recipients: {refused}"

    archived = wait_until(lambda: client.get("archive_latest"), timeout=15)
    assert archived is not None, "archive_worker did not produce archive_latest"
    assert archived == transform(message), "End-to-end archived data was not correctly obfuscated"


def test_rollout_script():
    script_path = "/home/user/rollout.sh"
    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

    with open(script_path, "r") as handle:
        content = handle.read()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith("#")]
    worker_idx = sleep_idx = smtp_idx = -1
    for i, line in enumerate(lines):
        if "supervisorctl" in line and "restart" in line and "archive_worker" in line:
            worker_idx = i
        elif "sleep 2" in line or "sleep  2" in line:
            sleep_idx = i
        elif "supervisorctl" in line and "restart" in line and "smtp_receiver" in line:
            smtp_idx = i

    assert worker_idx != -1, "Script missing supervisorctl restart archive_worker"
    assert sleep_idx != -1, "Script missing sleep 2"
    assert smtp_idx != -1, "Script missing supervisorctl restart smtp_receiver"
    assert worker_idx < sleep_idx < smtp_idx, "Commands in rollout.sh are not in the correct order"

    old_worker = supervisor_pid("archive_worker")
    old_smtp = supervisor_pid("smtp_receiver")
    assert old_worker > 0 and old_smtp > 0, "Services must be running before rollout"

    env = os.environ.copy()
    env["SUPERVISOR_SERVER_URL"] = "unix:///tmp/supervisor.sock"
    proc = subprocess.Popen(
        [script_path], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    worker_stopped_at = None
    smtp_stopped_at = None
    deadline = time.monotonic() + 20
    while proc.poll() is None and time.monotonic() < deadline:
        now = time.monotonic()
        if worker_stopped_at is None and not os.path.exists(f"/proc/{old_worker}"):
            worker_stopped_at = now
        if smtp_stopped_at is None and not os.path.exists(f"/proc/{old_smtp}"):
            smtp_stopped_at = now
        time.sleep(0.02)

    if proc.poll() is None:
        proc.kill()
        assert False, "rollout.sh timed out"
    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, f"rollout.sh failed:\n{stdout}\n{stderr}"

    if worker_stopped_at is None and not os.path.exists(f"/proc/{old_worker}"):
        worker_stopped_at = time.monotonic()
    if smtp_stopped_at is None and not os.path.exists(f"/proc/{old_smtp}"):
        smtp_stopped_at = time.monotonic()

    assert worker_stopped_at is not None, "rollout.sh did not restart archive_worker"
    assert smtp_stopped_at is not None, "rollout.sh did not restart smtp_receiver"
    assert worker_stopped_at < smtp_stopped_at, "smtp_receiver restarted before archive_worker"
    assert smtp_stopped_at - worker_stopped_at >= 1.7, "rollout.sh did not wait approximately 2 seconds between restarts"

    assert wait_until(lambda: supervisor_pid("archive_worker") not in (0, old_worker)), "archive_worker did not return with a new PID"
    assert wait_until(lambda: supervisor_pid("smtp_receiver") not in (0, old_smtp)), "smtp_receiver did not return with a new PID"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
