#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tarfile

ARCHIVE = "/home/user/backups/mailer_backup.tar.gz"
SCRIPT = "/home/user/scripts/backup_mailer.sh"
UNIT = "/home/user/.config/systemd/user/mailer-backup.service"
LOG = "/home/user/deployment_summary.log"
SOURCE_CONFIG = "/home/user/mailing_list/config.cf"
SOURCE_WELCOME = "/home/user/mailing_list/templates/welcome.txt"


def assert_archive_matches_sources():
    assert os.path.isfile(ARCHIVE), f"Backup archive {ARCHIVE} does not exist."
    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            names = tar.getnames()

            # Preserve the original member-name assertions.
            has_config = any(name.endswith("config.cf") for name in names)
            has_welcome = any(name.endswith("templates/welcome.txt") for name in names)
            assert has_config, "config.cf is missing from the backup archive."
            assert has_welcome, "templates/welcome.txt is missing from the backup archive."

            config_members = [m for m in tar.getmembers() if m.name.endswith("config.cf")]
            welcome_members = [m for m in tar.getmembers() if m.name.endswith("templates/welcome.txt")]
            assert len(config_members) == 1, "Archive must contain exactly one config.cf member."
            assert len(welcome_members) == 1, "Archive must contain exactly one templates/welcome.txt member."
            assert config_members[0].isfile(), "Archived config.cf is not a regular file."
            assert welcome_members[0].isfile(), "Archived welcome.txt is not a regular file."

            archived_config = tar.extractfile(config_members[0]).read()
            archived_welcome = tar.extractfile(welcome_members[0]).read()
    except (tarfile.TarError, OSError) as e:
        raise AssertionError(f"Failed to read tar archive {ARCHIVE}: {e}")

    with open(SOURCE_CONFIG, "rb") as f:
        expected_config = f.read()
    with open(SOURCE_WELCOME, "rb") as f:
        expected_welcome = f.read()

    assert archived_config == expected_config, "Archived config.cf does not match the source file."
    assert archived_welcome == expected_welcome, "Archived welcome.txt does not match the source file."


def user_command(command, cwd=None):
    uid = os.getpwnam("user").pw_uid if hasattr(os, "getpwnam") else None
    if uid is None:
        import pwd
        uid = pwd.getpwnam("user").pw_uid
    runtime = f"/run/user/{uid}"
    env_args = [
        "HOME=/home/user",
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    ]
    return subprocess.run(
        ["/usr/sbin/runuser", "-u", "user", "--", "/usr/bin/env", *env_args, *command],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )


def test_backup_archive_exists_and_contents():
    assert_archive_matches_sources()


def test_deployment_summary_log_and_checksum():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} missing for checksum calculation."

    with open(LOG, "r") as f:
        log_content = f.read()

    # Preserve the original checksum assertion and additionally enforce exactly one line.
    match = re.search(r"BACKUP_CHECKSUM:\s*([a-f0-9]{32})", log_content)
    assert match is not None, f"Could not find BACKUP_CHECKSUM with a valid MD5 hash in {LOG}."
    assert re.fullmatch(r"BACKUP_CHECKSUM: [a-f0-9]{32}\n?", log_content), \
        f"{LOG} must contain exactly one correctly formatted line."

    md5 = hashlib.md5()
    with open(ARCHIVE, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            md5.update(chunk)
    assert match.group(1) == md5.hexdigest(), "Logged MD5 hash does not match the archive."


def test_script_hardening_and_absolute_paths():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "set -euo pipefail" in content, f"'set -euo pipefail' is missing from {SCRIPT}."

    operative = [line for line in content.splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
    assert operative, "Backup script has no executable statements."
    assert re.fullmatch(r"\s*set\s+-euo\s+pipefail\s*", operative[0]), \
        "set -euo pipefail must be an executable statement before the backup commands."
    operative_text = "\n".join(operative)
    assert "/home/user/mailing_list" in operative_text, "Script does not use the absolute source path."
    assert "/home/user/backups/mailer_backup.tar.gz" in operative_text, \
        "Script does not use the absolute destination archive path."

    syntax = subprocess.run(["/bin/bash", "-n", SCRIPT], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert syntax.returncode == 0, f"Backup script has invalid syntax:\n{syntax.stdout}"


def test_script_really_generates_backup_from_arbitrary_working_directory():
    if os.path.exists(ARCHIVE):
        os.remove(ARCHIVE)
    result = user_command([SCRIPT], cwd="/tmp")
    assert result.returncode == 0, f"Backup script failed from /tmp:\n{result.stdout}"
    assert_archive_matches_sources()


def test_service_unit_and_systemd_execution_generate_backup():
    assert os.path.isfile(UNIT), f"Service unit {UNIT} does not exist."
    with open(UNIT, "r") as f:
        unit_content = f.read()

    exec_lines = [line.strip() for line in unit_content.splitlines()
                  if line.strip().startswith("ExecStart=")]
    assert exec_lines == [f"ExecStart={SCRIPT}"], \
        f"Service must have exactly one ExecStart using the absolute backup script path: {exec_lines}"

    for line in unit_content.splitlines():
        stripped = line.strip()
        if stripped.startswith("WorkingDirectory="):
            working_dir = stripped.split("=", 1)[1]
            assert os.path.isabs(working_dir), "WorkingDirectory must be absolute."
            assert os.path.isdir(working_dir), "WorkingDirectory must exist."

    reload_result = user_command(["/usr/bin/systemctl", "--user", "daemon-reload"])
    assert reload_result.returncode == 0, f"systemctl --user daemon-reload failed:\n{reload_result.stdout}"

    if os.path.exists(ARCHIVE):
        os.remove(ARCHIVE)
    start_result = user_command(["/usr/bin/systemctl", "--user", "start", "mailer-backup.service"])
    assert start_result.returncode == 0, f"mailer-backup.service failed:\n{start_result.stdout}"
    assert_archive_matches_sources()

    failed_result = user_command(["/usr/bin/systemctl", "--user", "is-failed", "mailer-backup.service"])
    assert failed_result.returncode != 0, f"mailer-backup.service is in a failed state:\n{failed_result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
