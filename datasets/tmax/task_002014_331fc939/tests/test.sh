#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
import pytest

ARCHIVE = "/home/user/archive/legacy_service.tar.gz"
LOG_DIR = "/home/user/shared_logs/cloud_service"
SYMLINK = "/home/user/cloud_service/logs"
EXPECTED_TARGET = "/home/user/shared_logs/cloud_service"
SERVICE_FILE = "/home/user/services/cloud-worker.service"
SCRIPT = "/home/user/cloud_service/health_check.py"
STATUS = "/home/user/shared_logs/cloud_service/status.log"


def test_backup_archive_exists_and_valid():
    assert os.path.isfile(ARCHIVE), f"Backup archive {ARCHIVE} does not exist or is not a file."

    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            names = tar.getnames()
            assert len(names) > 0, f"Archive {ARCHIVE} is empty."

            matches = []
            for member in tar.getmembers():
                normalized = member.name.lstrip("./")
                if normalized == "data.txt" or normalized == "legacy_service/data.txt" or normalized.endswith("/legacy_service/data.txt"):
                    matches.append(member)

            assert matches, "Archive does not contain legacy_service/data.txt."
            assert any(
                member.isfile()
                and tar.extractfile(member) is not None
                and tar.extractfile(member).read() == b"legacy data\n"
                for member in matches
            ), "Archived legacy_service/data.txt does not contain the expected legacy data."
    except tarfile.ReadError:
        pytest.fail(f"Archive {ARCHIVE} is not a valid gzip-compressed tar archive.")


def test_shared_logs_directory_exists():
    assert os.path.isdir(LOG_DIR), f"Shared logs directory {LOG_DIR} does not exist."


def test_logs_symlink_correct():
    assert os.path.islink(SYMLINK), f"{SYMLINK} is not a symbolic link."
    actual_target = os.readlink(SYMLINK)
    assert actual_target == EXPECTED_TARGET, f"Symlink {SYMLINK} points to {actual_target}, expected {EXPECTED_TARGET}."


def test_systemd_service_file_updated():
    assert os.path.isfile(SERVICE_FILE), f"Service file {SERVICE_FILE} does not exist."

    with open(SERVICE_FILE, "r") as f:
        content = f.read()

    assert "After=cloud-db.service" in content, "Missing 'After=cloud-db.service' in the systemd service file."
    assert "Requires=cloud-db.service" in content, "Missing 'Requires=cloud-db.service' in the systemd service file."

    current_section = None
    unit_lines = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            current_section = line
        elif current_section == "[Unit]" and line and not line.startswith(("#", ";")):
            unit_lines.append(line)

    assert "After=cloud-db.service" in unit_lines, "'After=cloud-db.service' must be under [Unit]."
    assert "Requires=cloud-db.service" in unit_lines, "'Requires=cloud-db.service' must be under [Unit]."


def test_health_check_script_exists():
    assert os.path.isfile(SCRIPT), f"Health check script {SCRIPT} does not exist."


def test_status_log_contains_migration_ready():
    assert os.path.isfile(STATUS), f"Status log {STATUS} does not exist. Did the script run successfully?"
    with open(STATUS, "r") as f:
        content = f.read().strip()
    assert content == "MIGRATION_READY", f"Expected 'MIGRATION_READY' in {STATUS}, got '{content}'."


def remove_status():
    if os.path.lexists(STATUS):
        os.unlink(STATUS)


def run_health_check():
    return subprocess.run(
        ["/usr/bin/env", "python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def assert_no_ready_status():
    if os.path.isfile(STATUS):
        with open(STATUS, "r") as f:
            assert f.read() != "MIGRATION_READY", "Health check wrote MIGRATION_READY despite a failed migration condition."


def assert_valid_run():
    remove_status()
    result = run_health_check()
    assert result.returncode == 0, f"Health check failed on valid state: {result.stderr}"
    assert os.path.isfile(STATUS), "Health check did not create status.log on valid state."
    with open(STATUS, "r") as f:
        assert f.read() == "MIGRATION_READY", "Health check must write the exact string MIGRATION_READY."


def test_health_check_executes_and_validates_all_conditions():
    # A pre-created status file must not suffice: execute the submitted script itself.
    assert_valid_run()

    held_archive = ARCHIVE + ".verifier-held"
    remove_status()
    os.replace(ARCHIVE, held_archive)
    try:
        run_health_check()
        assert_no_ready_status()
    finally:
        if os.path.lexists(ARCHIVE):
            os.unlink(ARCHIVE)
        os.replace(held_archive, ARCHIVE)
    assert_valid_run()

    remove_status()
    os.unlink(SYMLINK)
    os.symlink("/tmp/not-the-shared-log-directory", SYMLINK)
    try:
        run_health_check()
        assert_no_ready_status()
    finally:
        if os.path.lexists(SYMLINK):
            os.unlink(SYMLINK)
        os.symlink(EXPECTED_TARGET, SYMLINK)
    assert_valid_run()

    with open(SERVICE_FILE, "rb") as f:
        original_service = f.read()
    invalid_service = original_service.replace(b"After=cloud-db.service", b"After=missing-db.service")
    invalid_service = invalid_service.replace(b"Requires=cloud-db.service", b"Requires=missing-db.service")
    remove_status()
    with open(SERVICE_FILE, "wb") as f:
        f.write(invalid_service)
    try:
        run_health_check()
        assert_no_ready_status()
    finally:
        with open(SERVICE_FILE, "wb") as f:
            f.write(original_service)
    assert_valid_run()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
