#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid
import pytest

AUTOMATE = "/home/user/automate.sh"
LEGACY = "/home/user/setup/legacy_config.sh"
CONFIG = "/home/user/.config/user_locale.conf"
STORAGE_SCRIPT = "/home/user/check_storage.sh"
STORAGE_DIR = "/home/user/secure_storage"
AUDIT_LOG = "/home/user/storage_audit.log"


def run_as_user(path):
    return subprocess.run(
        ["runuser", "-u", "user", "--", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=True,
    )


def expected_storage_line():
    try:
        du_output = subprocess.check_output(["du", "-sk", STORAGE_DIR], text=True).strip()
        size_kb = int(du_output.split()[0])
    except Exception as e:
        pytest.fail(f"Could not calculate size of {STORAGE_DIR}: {e}")
    status = "ALERT" if size_kb >= 5000 else "OK"
    return f"{status}: secure_storage is {size_kb}KB"


def test_automate_script_exists_and_executable():
    assert os.path.isfile(AUTOMATE), f"File {AUTOMATE} does not exist."
    assert os.access(AUTOMATE, os.X_OK), f"File {AUTOMATE} is not executable."


def test_legacy_config_output():
    assert os.path.isfile(CONFIG), f"Configuration file {CONFIG} was not created."
    with open(CONFIG, "r") as f:
        content = f.read()
    assert "TZ=Etc/UTC" in content, f"Expected 'TZ=Etc/UTC' in {CONFIG}, but got:\n{content}"
    assert "LANG=en_US.UTF-8" in content, f"Expected 'LANG=en_US.UTF-8' in {CONFIG}, but got:\n{content}"


def test_check_storage_script_exists_and_executable():
    assert os.path.isfile(STORAGE_SCRIPT), f"File {STORAGE_SCRIPT} does not exist."
    assert os.access(STORAGE_SCRIPT, os.X_OK), f"File {STORAGE_SCRIPT} is not executable."


def test_storage_audit_log_contents():
    assert os.path.isfile(AUDIT_LOG), f"Audit log file {AUDIT_LOG} was not created."
    with open(AUDIT_LOG, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) > 0, f"Audit log {AUDIT_LOG} is empty."
    expected_line = expected_storage_line()
    assert lines[-1] == expected_line, f"Expected log line '{expected_line}', but got '{lines[-1]}'"
    assert len(lines) == 1, f"Expected exactly one initial audit entry, but found {len(lines)} lines: {lines}"


def test_automate_script_executes_legacy_and_supplies_answers():
    token = uuid.uuid4().hex
    transcript = f"/tmp/legacy_probe_{token}"
    legacy_backup = f"/tmp/legacy_config_backup_{token}"
    config_backup = None

    if os.path.exists(CONFIG):
        with open(CONFIG, "rb") as f:
            config_backup = f.read()

    os.replace(LEGACY, legacy_backup)
    probe = f'''#!/bin/bash
printf "Starting legacy configuration wizard...\\n"
read -p "Enter desired timezone (e.g. UTC, EST): " tz
read -p "Enter desired locale (e.g. en_US.UTF-8): " loc
read -p "Confirm changes? (y/n): " confirm
printf "%s\\n%s\\n%s\\n" "$tz" "$loc" "$confirm" > {transcript}
if [ "$confirm" = "y" ]; then
    echo "TZ=$tz" > {CONFIG}
    echo "LANG=$loc" >> {CONFIG}
    echo "Configuration saved."
else
    echo "Aborted."
    exit 1
fi
'''
    try:
        with open(LEGACY, "w") as f:
            f.write(probe)
        os.chmod(LEGACY, 0o755)
        if os.path.exists(CONFIG):
            os.remove(CONFIG)

        try:
            run_as_user(AUTOMATE)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Automation script did not successfully execute the legacy script: {e}")

        assert os.path.isfile(transcript), "The automation script did not execute the legacy configuration script."
        with open(transcript, "r") as f:
            answers = f.read().splitlines()
        assert answers == ["Etc/UTC", "en_US.UTF-8", "y"], f"Legacy script received incorrect answers or order: {answers}"

        assert os.path.isfile(CONFIG), "Executing the automation script did not generate the configuration file."
        with open(CONFIG, "r") as f:
            content = f.read()
        assert "TZ=Etc/UTC" in content
        assert "LANG=en_US.UTF-8" in content
    finally:
        if os.path.lexists(LEGACY):
            os.remove(LEGACY)
        os.replace(legacy_backup, LEGACY)
        if os.path.exists(transcript):
            os.remove(transcript)
        if config_backup is None:
            if os.path.exists(CONFIG):
                os.remove(CONFIG)
        else:
            with open(CONFIG, "wb") as f:
                f.write(config_backup)
            os.chown(CONFIG, 1000, 1000)


def test_storage_script_behavior_for_both_threshold_branches():
    token = uuid.uuid4().hex
    storage_backup = f"/home/user/secure_storage_backup_{token}"
    log_existed = os.path.exists(AUDIT_LOG)
    log_backup = None
    if log_existed:
        with open(AUDIT_LOG, "rb") as f:
            log_backup = f.read()

    os.replace(STORAGE_DIR, storage_backup)
    try:
        os.mkdir(STORAGE_DIR)
        os.chown(STORAGE_DIR, 1000, 1000)

        # Exercise the strictly-less-than-5000 branch.
        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)
        run_as_user(STORAGE_SCRIPT)
        with open(AUDIT_LOG, "r") as f:
            low_lines = f.read().splitlines()
        low_expected = expected_storage_line()
        assert low_expected.startswith("OK:"), f"Empty test directory unexpectedly measured at or above threshold: {low_expected}"
        assert low_lines == [low_expected], f"Expected exactly one appended line '{low_expected}', got {low_lines}"

        # Exercise the greater-than-or-equal-to-5000 branch with newly allocated data.
        payload = os.path.join(STORAGE_DIR, f"payload_{token}.bin")
        with open(payload, "wb") as f:
            chunk = b"\0" * 1024 * 1024
            for _ in range(6):
                f.write(chunk)
            f.flush()
            os.fsync(f.fileno())
        os.chown(payload, 1000, 1000)

        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)
        run_as_user(STORAGE_SCRIPT)
        with open(AUDIT_LOG, "r") as f:
            high_lines = f.read().splitlines()
        high_expected = expected_storage_line()
        assert high_expected.startswith("ALERT:"), f"Allocated test directory unexpectedly measured below threshold: {high_expected}"
        assert high_lines == [high_expected], f"Expected exactly one appended line '{high_expected}', got {high_lines}"
    finally:
        if os.path.lexists(STORAGE_DIR):
            if os.path.isdir(STORAGE_DIR) and not os.path.islink(STORAGE_DIR):
                shutil.rmtree(STORAGE_DIR)
            else:
                os.remove(STORAGE_DIR)
        os.replace(storage_backup, STORAGE_DIR)
        if log_existed:
            with open(AUDIT_LOG, "wb") as f:
                f.write(log_backup)
            os.chown(AUDIT_LOG, 1000, 1000)
        elif os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
