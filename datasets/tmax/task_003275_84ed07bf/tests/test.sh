#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pwd
import stat
import subprocess
import uuid

import pytest


def test_incident_report():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"Incident report missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_timestamps = [
        "2023/10/24 11:20:05",
        "2023/10/24 12:25:10",
        "2023/10/24 13:30:15",
        "2023/10/24 14:35:20",
        "2023/10/24 15:40:25"
    ]

    assert lines == expected_timestamps, (
        f"Incident report does not contain the exact expected 5 timestamps. "
        f"Expected: {expected_timestamps}, Got: {lines}"
    )


def test_nginx_config_fixed():
    conf_path = "/home/user/nginx/conf/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    expected_directive = "proxy_pass http://unix:/home/user/app/run/backend.sock;"
    assert expected_directive in content, (
        f"The nginx.conf does not contain the correct proxy_pass directive. "
        f"Expected to find: '{expected_directive}'"
    )
    assert "wrong_backend.sock" not in content, "The nginx.conf still contains 'wrong_backend.sock'."


def test_deploy_script_exists_and_executable():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deploy script missing at {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deploy script {script_path} is not executable."


def test_backup_created():
    backup_path = "/home/user/backup/nginx.conf.bak"
    conf_path = "/home/user/nginx/conf/nginx.conf"

    assert os.path.isfile(backup_path), f"Backup file missing at {backup_path}"

    with open(backup_path, "r") as f:
        backup_content = f.read()

    with open(conf_path, "r") as f:
        conf_content = f.read()

    assert backup_content == conf_content, "The backup file content does not match the current nginx.conf."


def test_log_rotation_occurred():
    app_log_path = "/home/user/app/logs/app.log"
    rotated_log_path = "/home/user/app/logs/app.log.1"

    assert os.path.isfile(rotated_log_path), (
        f"Rotated log file missing at {rotated_log_path}. "
        f"Ensure deploy.sh was executed and rotates logs correctly."
    )

    assert os.path.isfile(app_log_path), f"New empty log file missing at {app_log_path}"

    with open(app_log_path, "r") as f:
        content = f.read()

    assert content == "", f"The new {app_log_path} is not empty. It should be recreated as an empty file."


def test_deploy_script_behavior_and_idempotence():
    script = "/home/user/deploy.sh"
    conf = "/home/user/nginx/conf/nginx.conf"
    backup = "/home/user/backup/nginx.conf.bak"
    log = "/home/user/app/logs/app.log"
    uid = pwd.getpwnam("user").pw_uid
    gid = pwd.getpwnam("user").pw_gid

    tracked = {conf, backup, log}
    tracked.update(glob.glob(log + ".[0-9]*"))

    def snapshot(path):
        if not os.path.lexists(path):
            return None
        st = os.stat(path)
        with open(path, "rb") as f:
            data = f.read()
        return (data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)

    saved = {path: snapshot(path) for path in tracked}

    def write_as_user(path, data):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        os.chown(path, uid, gid)
        os.chmod(path, 0o666)

    def run_deploy():
        return subprocess.run(
            ["runuser", "-u", "user", "--", "/bin/bash", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )

    try:
        with open(conf, "rb") as f:
            original_conf = f.read()

        # Exercise the script's proxy-path validation rather than trusting a
        # pre-created final state.
        invalid_conf = original_conf.replace(
            b"/home/user/app/run/backend.sock",
            b"/home/user/app/run/invalid_backend.sock",
        )
        assert invalid_conf != original_conf, "Could not construct invalid proxy configuration"
        write_as_user(conf, invalid_conf)
        invalid_result = run_deploy()
        assert invalid_result.returncode != 0, (
            "deploy.sh did not reject an incorrect proxy_pass socket path"
        )

        nonce = uuid.uuid4().hex.encode()
        valid_conf = original_conf.rstrip(b"\n") + b"\n# verifier-" + nonce + b"\n"
        write_as_user(conf, valid_conf)
        write_as_user(backup, b"stale-backup-" + nonce + b"\n")

        # Remove all numeric generations, then seed unpredictable contents.
        for path in glob.glob(log + ".[0-9]*"):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)

        current_1 = b"current-" + nonce + b"\n"
        old_1 = b"old-one-" + nonce + b"\n"
        old_2 = b"old-two-" + nonce + b"\n"
        old_3 = b"old-three-" + nonce + b"\n"
        write_as_user(log, current_1)
        write_as_user(log + ".1", old_1)
        write_as_user(log + ".2", old_2)
        write_as_user(log + ".3", old_3)

        first = run_deploy()
        assert first.returncode == 0, (
            f"deploy.sh failed on a valid configuration: {first.stderr}"
        )
        with open(backup, "rb") as f:
            assert f.read() == valid_conf, "deploy.sh did not overwrite the backup with current nginx.conf"
        with open(log, "rb") as f:
            assert f.read() == b"", "deploy.sh did not recreate an empty app.log"
        with open(log + ".1", "rb") as f:
            assert f.read() == current_1, "Current app.log was not rotated to app.log.1"
        with open(log + ".2", "rb") as f:
            assert f.read() == old_1, "app.log.1 was not shifted to app.log.2"
        with open(log + ".3", "rb") as f:
            assert f.read() == old_2, "app.log.2 was not shifted to app.log.3"
        assert not os.path.exists(log + ".4"), "deploy.sh retained more than three old log generations"

        # Run again with new input to verify repeatable/idempotent operation.
        current_2 = b"second-current-" + uuid.uuid4().hex.encode() + b"\n"
        write_as_user(log, current_2)
        second = run_deploy()
        assert second.returncode == 0, f"deploy.sh failed when run a second time: {second.stderr}"
        with open(log, "rb") as f:
            assert f.read() == b""
        with open(log + ".1", "rb") as f:
            assert f.read() == current_2
        with open(log + ".2", "rb") as f:
            assert f.read() == current_1
        with open(log + ".3", "rb") as f:
            assert f.read() == old_1
        assert not os.path.exists(log + ".4"), "Repeated deployment created a fourth generation"
        with open(backup, "rb") as f:
            assert f.read() == valid_conf, "Repeated deployment did not refresh the backup"
    finally:
        # Restore the agent's checked final state after behavioral testing.
        for path in glob.glob(log + ".[0-9]*"):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)
        for path, state in saved.items():
            if state is None:
                if os.path.lexists(path):
                    os.unlink(path)
                continue
            data, mode, owner, group = state
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)
            os.chown(path, owner, group)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
