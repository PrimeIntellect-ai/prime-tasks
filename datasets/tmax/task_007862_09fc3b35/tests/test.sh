#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import tempfile


def run_as_user(command, *, env=None, timeout=15):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    child_env = os.environ.copy()
    child_env.update({"HOME": account.pw_dir, "USER": "user", "LOGNAME": "user"})
    if env:
        child_env.update(env)
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        env=child_env,
        preexec_fn=demote,
    )


def test_monitor_routes_script_exists():
    path = "/home/user/monitor_routes.py"
    assert os.path.isfile(path), f"Expected script {path} does not exist."
    assert not os.path.islink(path), f"Expected {path} to be a real Python script, not a symlink."


def test_logrotate_conf_exists_and_configured():
    path = "/home/user/logrotate.conf"
    assert os.path.isfile(path), f"Expected config {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Check for required directives. We use regex to allow formatting flexibility.
    assert re.search(r'\bsize\s+20\b', content), "logrotate.conf missing 'size 20' directive."
    assert re.search(r'\brotate\s+3\b', content), "logrotate.conf missing 'rotate 3' directive."
    assert re.search(r'\bcreate\b', content), "logrotate.conf missing 'create' directive."
    assert re.search(r'\bnocompress\b', content), "logrotate.conf missing 'nocompress' directive."


def test_logrotate_state_exists():
    path = "/home/user/lr.state"
    assert os.path.isfile(path), f"Expected logrotate state file {path} does not exist. Did you run logrotate with the custom state file?"


def test_logs_rotated_correctly():
    log_file = "/home/user/migration.log"
    log_1 = "/home/user/migration.log.1"
    log_2 = "/home/user/migration.log.2"

    assert os.path.isfile(log_file), f"{log_file} does not exist."
    assert os.path.isfile(log_1), f"{log_1} does not exist. Log rotation may not have run or failed."
    assert os.path.isfile(log_2), f"{log_2} does not exist. Log rotation may not have run twice as requested."

    # Check that the current log is empty (since it was just rotated and created)
    assert os.path.getsize(log_file) == 0, f"{log_file} should be 0 bytes after the second rotation."

    expected_content = "127.0.0.1 - STATUS: UP\n198.51.100.254 - STATUS: DOWN\n"

    for rotated_log in [log_1, log_2]:
        with open(rotated_log, "r") as f:
            content = f.read()

        # We allow some flexibility in whitespace, but the core strings must be present
        assert "127.0.0.1 - STATUS: UP" in content, f"{rotated_log} missing correct UP status for 127.0.0.1"
        assert "198.51.100.254 - STATUS: DOWN" in content, f"{rotated_log} missing correct DOWN status for 198.51.100.254"


def test_monitor_script_behavior():
    script = "/home/user/monitor_routes.py"
    targets = "/home/user/targets.json"
    migration_log = "/home/user/migration.log"
    account = pwd.getpwnam("user")

    with open(targets, "rb") as f:
        old_targets = f.read()
    old_log = None
    if os.path.exists(migration_log):
        assert os.path.isfile(migration_log) and not os.path.islink(migration_log)
        with open(migration_log, "rb") as f:
            old_log = f.read()

    ping_path = os.path.realpath(shutil.which("ping"))
    ping_backup = ping_path + ".verifier-backup"
    record_path = tempfile.mktemp(prefix="ping-record-", dir="/tmp")
    open(record_path, "w").close()
    os.chmod(record_path, 0o666)

    try:
        with open(targets, "w") as f:
            json.dump(["192.0.2.10", "192.0.2.11"], f)
        os.chown(targets, account.pw_uid, account.pw_gid)

        if os.path.lexists(migration_log):
            os.unlink(migration_log)
        with open(migration_log, "w") as f:
            f.write("seed\n")
        os.chown(migration_log, account.pw_uid, account.pw_gid)
        os.chmod(migration_log, 0o666)

        assert not os.path.exists(ping_backup), f"Unexpected verifier backup path already exists: {ping_backup}"
        os.replace(ping_path, ping_backup)
        wrapper = '''#!/usr/bin/python3
import json
import os
import sys
with open(os.environ["PING_RECORD"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(0 if "192.0.2.10" in sys.argv[1:] else 1)
'''
        with open(ping_path, "w") as f:
            f.write(wrapper)
        os.chmod(ping_path, 0o755)

        result = run_as_user(["python3", script], env={"PING_RECORD": record_path})
        assert result.returncode == 0, f"monitor_routes.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

        with open(record_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 2, f"Expected exactly one ping per target (2 calls total), got {calls!r}"

        def option_is_one(args, option):
            for index, arg in enumerate(args):
                if arg == option and index + 1 < len(args) and args[index + 1] == "1":
                    return True
                if arg in (option + "1", option + "=1"):
                    return True
            return False

        for ip in ("192.0.2.10", "192.0.2.11"):
            matching = [args for args in calls if args.count(ip) == 1]
            assert len(matching) == 1, f"Expected exactly one ping invocation for {ip}, got {calls!r}"
            args = matching[0]
            assert option_is_one(args, "-c"), f"Ping for {ip} must request exactly one packet with -c 1: {args!r}"
            assert option_is_one(args, "-W"), f"Ping for {ip} must use a 1-second timeout with -W 1: {args!r}"

        with open(migration_log) as f:
            content = f.read()
        assert content == (
            "seed\n"
            "192.0.2.10 - STATUS: UP\n"
            "192.0.2.11 - STATUS: DOWN\n"
        ), f"Script did not append results in the exact required format: {content!r}"
    finally:
        if os.path.exists(ping_backup):
            if os.path.lexists(ping_path):
                os.unlink(ping_path)
            os.replace(ping_backup, ping_path)
        if os.path.exists(record_path):
            os.unlink(record_path)
        with open(targets, "wb") as f:
            f.write(old_targets)
        os.chown(targets, account.pw_uid, account.pw_gid)
        if os.path.lexists(migration_log):
            os.unlink(migration_log)
        if old_log is not None:
            with open(migration_log, "wb") as f:
                f.write(old_log)
            os.chown(migration_log, account.pw_uid, account.pw_gid)


def test_logrotate_configuration_operates_as_required():
    base = "/home/user/migration.log"
    config = "/home/user/logrotate.conf"
    state_file = "/home/user/.verifier-lr.state"
    account = pwd.getpwnam("user")

    existing = {}
    for path in glob.glob(base + "*"):
        assert os.path.isfile(path) and not os.path.islink(path), f"Unexpected non-regular log artifact: {path}"
        info = os.stat(path)
        with open(path, "rb") as f:
            existing[path] = (f.read(), stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid)

    try:
        for path in glob.glob(base + "*"):
            os.unlink(path)
        if os.path.exists(state_file):
            os.unlink(state_file)

        # A file not exceeding 20 bytes must remain unrotated.
        with open(base, "wb") as f:
            f.write(b"12345678901234567890")
        os.chown(base, account.pw_uid, account.pw_gid)
        result = run_as_user(["logrotate", "-s", state_file, config])
        assert result.returncode == 0, f"logrotate failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert os.path.isfile(base) and not os.path.exists(base + ".1"), "A 20-byte log should not rotate."

        # Exercise four rotations; only the three newest versions may remain.
        for cycle in range(4):
            payload = (f"rotation-{cycle}-" + "x" * 20).encode()
            with open(base, "wb") as f:
                f.write(payload)
            os.chown(base, account.pw_uid, account.pw_gid)
            result = run_as_user(["logrotate", "-s", state_file, config])
            assert result.returncode == 0, f"logrotate cycle {cycle + 1} failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
            assert os.path.isfile(base), "logrotate did not create a new migration.log."
            assert os.path.getsize(base) == 0, "New migration.log is not empty after rotation."

        assert all(os.path.isfile(base + f".{n}") for n in (1, 2, 3)), "Exactly three rotated versions were not retained."
        assert not os.path.exists(base + ".4"), "More than three rotated versions were retained."
        assert not glob.glob(base + "*.gz"), "Rotated logs were compressed despite nocompress."
    finally:
        for path in glob.glob(base + "*"):
            os.unlink(path)
        if os.path.exists(state_file):
            os.unlink(state_file)
        for path, (data, mode, uid, gid) in existing.items():
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)
            os.chown(path, uid, gid)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
