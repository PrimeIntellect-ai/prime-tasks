#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from pathlib import Path


def test_directories_exist():
    """Verify that required directories exist."""
    assert os.path.isdir("/home/user/service_data"), "Directory /home/user/service_data is missing."
    assert os.path.isdir("/home/user/backup"), "Directory /home/user/backup is missing."


def test_backup_file_correct():
    """Verify the backup file was created and contains the initial state."""
    backup_path = "/home/user/backup/passwd.bak"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."

    with open(backup_path, "r") as f:
        content = f.read()

    assert "dummyuser:x:1000:1000:Dummy:/home/dummy:/bin/bash" in content, "Backup file does not contain the original dummyuser entry."


def test_passwd_file_correct():
    """Verify the mock passwd file contains the correct entries and is idempotent."""
    passwd_path = "/home/user/service_data/passwd"
    assert os.path.isfile(passwd_path), f"File {passwd_path} is missing."

    with open(passwd_path, "r") as f:
        lines = f.readlines()

    appuser_lines = [line.strip() for line in lines if line.startswith("appuser:")]
    assert len(appuser_lines) == 1, f"Expected exactly one 'appuser' entry, found {len(appuser_lines)}. Script may not be idempotent."

    expected_appuser = "appuser:x:2001:2001:Microservice Account:/home/user/service_data:/bin/false"
    assert appuser_lines[0] == expected_appuser, f"The appuser entry does not match the expected string. Got: {appuser_lines[0]}"

    dummy_present = any("dummyuser:x:1000:1000:Dummy:/home/dummy:/bin/bash" in line for line in lines)
    assert dummy_present, "The original dummyuser entry was removed or modified in the passwd file."


def test_verify_script_exists_and_robust():
    """Verify the generated Python script exists and contains error handling."""
    script_path = "/home/user/service_data/verify.py"
    assert os.path.isfile(script_path), f"Python verification script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "Error: passwd file missing" in content, "The Python script does not contain the exact required error message string 'Error: passwd file missing'."
    assert "try:" in content or "try " in content, "The Python script does not appear to use a try-except block for error handling."


def test_result_log_correct():
    """Verify the result log contains the correct output."""
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"Result log {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read()

    assert content == "UID: 2001\n", f"Result log content is incorrect. Expected 'UID: 2001\\n', got {repr(content)}"


def test_init_script_executable():
    """Verify the init script exists and is executable."""
    script_path = "/home/user/init_service.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deployment script {script_path} is not executable."


def test_scripts_work_and_init_is_idempotent():
    """Execute the submitted artifacts against controlled states."""
    init_path = Path("/home/user/init_service.sh")
    passwd_path = Path("/home/user/service_data/passwd")
    backup_path = Path("/home/user/backup/passwd.bak")
    verify_path = Path("/home/user/service_data/verify.py")
    expected = "appuser:x:2001:2001:Microservice Account:/home/user/service_data:/bin/false"

    paths = (passwd_path, backup_path, verify_path)
    saved = {}
    for path in paths:
        if path.exists():
            saved[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
        else:
            saved[path] = None

    try:
        Path("/home/user/service_data").mkdir(parents=True, exist_ok=True)
        Path("/home/user/backup").mkdir(parents=True, exist_ok=True)

        seed = b"probeuser:x:3100:3100:Probe:/probe:/bin/false\n"
        passwd_path.write_bytes(seed)
        if backup_path.exists():
            backup_path.unlink()

        subprocess.run([str(init_path)], check=True, timeout=10)

        assert backup_path.is_file(), "The init script did not back up an existing passwd file."
        assert backup_path.read_bytes() == seed, "The init script did not back up passwd before changing it."

        first_result = passwd_path.read_text()
        first_lines = first_result.splitlines()
        assert first_lines[0] == seed.decode().rstrip("\n"), "The init script altered an existing passwd entry."
        assert first_lines.count(expected) == 1, "The init script did not add exactly one correct appuser entry."
        assert verify_path.is_file(), "The init script did not generate verify.py."

        successful_verify = subprocess.run(
            ["python3", str(verify_path)], capture_output=True, text=True, timeout=10
        )
        assert successful_verify.returncode == 0, f"verify.py failed with passwd present: {successful_verify.stderr}"
        assert successful_verify.stdout == "UID: 2001\n", f"verify.py produced incorrect output: {successful_verify.stdout!r}"

        before_second_run = passwd_path.read_bytes()
        subprocess.run([str(init_path)], check=True, timeout=10)
        assert passwd_path.read_bytes() == before_second_run, "Running init_service.sh twice changed passwd."
        assert passwd_path.read_text().splitlines().count(expected) == 1, "Running init_service.sh twice duplicated appuser."
        assert backup_path.read_bytes() == before_second_run, "The second run did not back up the existing passwd file before processing it."

        passwd_path.unlink()
        missing_verify = subprocess.run(
            ["python3", str(verify_path)], capture_output=True, text=True, timeout=10
        )
        assert missing_verify.returncode == 0, f"verify.py did not handle a missing passwd file: {missing_verify.stderr}"
        assert missing_verify.stdout == "Error: passwd file missing\n", f"Incorrect missing-file output: {missing_verify.stdout!r}"

        subprocess.run([str(init_path)], check=True, timeout=10)
        assert passwd_path.is_file(), "The init script did not create passwd when it was missing."
        created_lines = passwd_path.read_text().splitlines()
        assert created_lines.count(expected) == 1, "The newly created passwd file lacks exactly one correct appuser entry."
    finally:
        Path("/home/user/service_data").mkdir(parents=True, exist_ok=True)
        Path("/home/user/backup").mkdir(parents=True, exist_ok=True)
        for path, snapshot in saved.items():
            if path.exists() or path.is_symlink():
                path.unlink()
            if snapshot is not None:
                data, mode = snapshot
                path.write_bytes(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
