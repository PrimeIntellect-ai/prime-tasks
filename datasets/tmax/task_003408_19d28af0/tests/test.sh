#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shutil
import stat
import subprocess
import tempfile

SERVICE_FILE = "/home/user/.config/systemd/user/data-analyzer.service"
SCRIPT = "/home/user/deploy.sh"
V3_DIR = "/home/user/deploy/releases/v3"
CONFIG = V3_DIR + "/config.ini"
CURRENT = "/home/user/deploy/current"
V2_DIR = "/home/user/deploy/releases/v2"
LOG = "/home/user/verification.log"

ORIGINAL_SERVICE_LINES = [
    "[Unit]",
    "Description=Data Analyzer Service",
    "",
    "[Service]",
    "ExecStart=/usr/bin/python3 -m http.server 8080",
    "Restart=always",
    "",
    "[Install]",
    "WantedBy=default.target",
]


def run_as_user(env=None):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        env=env or os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        preexec_fn=demote,
    )


def reset_deployment():
    if os.path.lexists(V3_DIR):
        if os.path.isdir(V3_DIR) and not os.path.islink(V3_DIR):
            shutil.rmtree(V3_DIR)
        else:
            os.unlink(V3_DIR)
    if os.path.lexists(CURRENT):
        if os.path.isdir(CURRENT) and not os.path.islink(CURRENT):
            shutil.rmtree(CURRENT)
        else:
            os.unlink(CURRENT)
    os.symlink(V2_DIR, CURRENT)
    account = pwd.getpwnam("user")
    for root, dirs, files in os.walk("/home/user/deploy"):
        os.chown(root, account.pw_uid, account.pw_gid)
        for name in dirs + files:
            path = os.path.join(root, name)
            if not os.path.islink(path):
                os.chown(path, account.pw_uid, account.pw_gid)


def test_01_systemd_service_file_updated_without_other_changes():
    assert os.path.isfile(SERVICE_FILE), f"Systemd service file {SERVICE_FILE} is missing."
    with open(SERVICE_FILE, "r") as f:
        content = f.read()

    assert "After=data-collector.service" in content, "Service file does not contain the required 'After=data-collector.service' directive."
    lines = content.splitlines()
    assert lines.count("After=data-collector.service") == 1, "The required After= directive must occur exactly once."
    after_idx = lines.index("After=data-collector.service")
    unit_idx = lines.index("[Unit]")
    service_idx = lines.index("[Service]")
    assert unit_idx < after_idx < service_idx, "'After=' directive is not in the [Unit] section."

    unchanged = lines[:after_idx] + lines[after_idx + 1:]
    assert unchanged == ORIGINAL_SERVICE_LINES, "Existing systemd unit lines were modified, removed, added, or reordered."


def test_02_deploy_script_exists_executable_and_contains_required_mechanisms():
    assert os.path.isfile(SCRIPT), f"Deployment script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), "Deployment script must be a regular file, not a symlink."
    assert os.access(SCRIPT, os.X_OK), f"Deployment script {SCRIPT} is not executable."
    with open(SCRIPT, "r") as f:
        source = f.read()
    assert re.match(r"^#!.*\b(?:bash|env bash)\b", source), "deploy.sh must be a Bash script."
    assert re.search(r"(?:^|[\s/])df\b", source, re.MULTILINE), "deploy.sh does not use df for its storage check."
    assert "10000" in source, "deploy.sh does not contain the required 10,000 KB threshold."
    atomic_primitives = re.search(r"\bmv\b|os\.replace|renameat|\brename\b", source)
    assert atomic_primitives, "deploy.sh does not use an atomic replacement operation for the current symlink."


def test_03_low_space_check_happens_before_deployment():
    reset_deployment()
    df_path = os.path.realpath(shutil.which("df"))
    backup = df_path + ".verifier-backup"
    assert not os.path.exists(backup)
    os.replace(df_path, backup)
    try:
        with open(df_path, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' 'verifierfs 20000 19001 999 96% /home/user'\n")
        os.chmod(df_path, 0o755)
        result = run_as_user()
    finally:
        if os.path.lexists(df_path):
            os.unlink(df_path)
        os.replace(backup, df_path)

    assert result.returncode == 1, f"Low-space run exited with {result.returncode}, expected 1. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert "error" in (result.stdout + result.stderr).lower(), "Low-space run did not print an error."
    assert not os.path.lexists(V3_DIR), "The v3 release was created before the low-space check succeeded."
    assert os.path.islink(CURRENT) and os.readlink(CURRENT) == V2_DIR, "The current link changed despite the low-space failure."


def test_04_script_builds_release_and_is_idempotent():
    reset_deployment()
    first = run_as_user()
    assert first.returncode == 0, f"First deploy.sh run failed: stdout={first.stdout!r} stderr={first.stderr!r}"

    assert os.path.isdir(V3_DIR), f"Directory {V3_DIR} was not created."
    assert os.path.isfile(CONFIG), f"Config file {CONFIG} is missing."
    with open(CONFIG, "rb") as f:
        assert f.read() == b"secure_mode=true", "Config file does not contain exactly 'secure_mode=true'."
    assert stat.S_IMODE(os.stat(CONFIG).st_mode) == 0o400, "Config file permissions are not 0400."
    assert os.path.islink(CURRENT), f"{CURRENT} is not a symlink."
    assert os.readlink(CURRENT) == V3_DIR, f"Symlink points to {os.readlink(CURRENT)} instead of {V3_DIR}."

    expected = (open(CONFIG, "rb").read(), stat.S_IMODE(os.stat(CONFIG).st_mode), os.readlink(CURRENT))
    second = run_as_user()
    assert second.returncode == 0, f"Second deploy.sh run failed: stdout={second.stdout!r} stderr={second.stderr!r}"
    actual = (open(CONFIG, "rb").read(), stat.S_IMODE(os.stat(CONFIG).st_mode), os.readlink(CURRENT))
    assert actual == expected, "A second run did not produce the same final state."
    assert os.path.isdir(V3_DIR) and not os.path.islink(V3_DIR), "Idempotent run created an invalid or nested v3 release."


def test_05_verification_log_has_exactly_three_lines():
    assert os.path.isfile(LOG), f"Verification log {LOG} is missing."
    with open(LOG, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 3, f"Verification log must contain exactly three lines, found {len(lines)}."
    assert lines[0] == V3_DIR, f"Line 1 is incorrect: {lines[0]!r}"
    assert lines[1] in ("400", "0400"), f"Line 2 is incorrect: {lines[1]!r}"
    assert lines[2] == "After=data-collector.service", f"Line 3 is incorrect: {lines[2]!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
