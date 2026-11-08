#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tarfile
import pytest

SOURCE_PATH = "/home/user/mail_monitor.c"
EXE_PATH = "/home/user/mail_monitor"
SPOOL_PATH = "/home/user/mail_spool"
BACKUP_PATH = "/home/user/mail_backup.tar.gz"
LOG_PATH = "/home/user/health_status.log"


def test_c_source_exists():
    """Verify that the C source code file exists."""
    assert os.path.isfile(SOURCE_PATH), f"C source file {SOURCE_PATH} does not exist."


def test_executable_exists():
    """Verify that the compiled executable exists, is executable, and is a native binary."""
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable {EXE_PATH} is not an ELF binary."


def test_backup_exists_and_valid():
    """Verify that the initial backup tarball is valid and contains the expected file."""
    assert os.path.isfile(BACKUP_PATH), f"Backup file {BACKUP_PATH} does not exist."
    try:
        with tarfile.open(BACKUP_PATH, "r:gz") as tar:
            names = tar.getnames()
            expected_file = "mail_spool/msg_1.eml"
            assert expected_file in names, f"Expected file {expected_file} not found in the backup tarball."
    except tarfile.ReadError:
        pytest.fail(f"File {BACKUP_PATH} is not a valid gzip-compressed tarball.")


def test_health_status_log():
    """Verify that the initial health status log has the required output."""
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    expected_content = "STATUS: BACKUP_TRIGGERED, EMAIL_COUNT: 12"
    assert content == expected_content, f"Log file content is incorrect. Expected '{expected_content}', got '{content}'."


def reset_spool(file_count):
    shutil.rmtree(SPOOL_PATH, ignore_errors=True)
    os.makedirs(SPOOL_PATH)
    payloads = {}
    for _ in range(file_count):
        name = f"dynamic_{secrets.token_hex(8)}.eml"
        data = os.urandom(37)
        with open(os.path.join(SPOOL_PATH, name), "wb") as f:
            f.write(data)
        payloads[name] = data
    # Directories must not be included in the regular-file count.
    os.mkdir(os.path.join(SPOOL_PATH, f"ignored_dir_{secrets.token_hex(4)}"))
    for path in (BACKUP_PATH, LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    return payloads


def run_monitor(executable):
    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


def assert_log(expected):
    assert os.path.isfile(LOG_PATH), "Monitor did not create the health status log."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == expected, f"Expected log '{expected}', got '{content}'."


def exercise_thresholds(executable):
    reset_spool(5)
    run_monitor(executable)
    assert_log("STATUS: HEALTHY, EMAIL_COUNT: 5")
    assert not os.path.exists(BACKUP_PATH), "A backup was created when the count was not greater than 5."

    count = 6 + secrets.randbelow(4)
    payloads = reset_spool(count)
    run_monitor(executable)
    assert_log(f"STATUS: BACKUP_TRIGGERED, EMAIL_COUNT: {count}")
    assert os.path.isfile(BACKUP_PATH), "Monitor did not create the backup."

    try:
        with tarfile.open(BACKUP_PATH, "r:gz") as tar:
            members = {m.name: m for m in tar.getmembers() if m.isfile()}
            expected_names = {f"mail_spool/{name}" for name in payloads}
            assert set(members) == expected_names, (
                f"Backup regular-file contents are incorrect. Expected {sorted(expected_names)}, "
                f"got {sorted(members)}."
            )
            for name, data in payloads.items():
                archived = tar.extractfile(members[f"mail_spool/{name}"])
                assert archived is not None
                assert archived.read() == data, f"Archived contents for {name} do not match the spool file."
    except tarfile.ReadError:
        pytest.fail(f"File {BACKUP_PATH} is not a valid gzip-compressed tarball.")


def test_dynamic_counting_threshold_and_complete_backup():
    """Compile the submitted source and exercise both it and the submitted executable."""
    rebuilt = "/tmp/mail_monitor_rebuilt"
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "Submitted C source does not compile with GCC: "
        + compile_result.stderr.decode(errors="replace")
    )

    exercise_thresholds(EXE_PATH)
    exercise_thresholds(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
