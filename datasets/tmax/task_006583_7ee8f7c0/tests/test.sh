#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import secrets
import shutil
import subprocess
import tarfile


def test_symlink_current_data():
    symlink_path = "/home/user/app/current_data"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    target = os.readlink(symlink_path)
    assert target in ["data_v1", "/home/user/app/data_v1"], f"Symlink points to {target}, expected data_v1 or /home/user/app/data_v1"


def test_status_txt():
    processor_path = "/home/user/app/processor"
    status_path = "/home/user/app/status.txt"

    assert os.path.isfile(processor_path), f"{processor_path} does not exist."
    assert os.access(processor_path, os.X_OK), f"{processor_path} is not executable."

    if os.path.exists(status_path):
        os.remove(status_path)

    result = subprocess.run(
        [processor_path],
        cwd="/home/user/app",
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"processor failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )

    assert os.path.isfile(status_path), f"{status_path} does not exist. Did the processor run?"
    with open(status_path, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()
    assert content == "OK", f"Expected status.txt to contain 'OK', but found '{content}'"
    assert raw_content == "OK", "processor must create status.txt with exactly 'OK'"


def test_health_check_script():
    script_path = "/home/user/app/health_check.sh"
    status_path = "/home/user/app/status.txt"
    backup_status_path = "/home/user/app/status.txt.bak"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    # Test with OK status
    if not os.path.exists(status_path):
        with open(status_path, "w") as f:
            f.write("OK")

    result = subprocess.run([script_path], capture_output=True)
    assert result.returncode == 0, f"health_check.sh should exit with 0 when status is OK, got {result.returncode}"

    # Test with BAD status
    shutil.move(status_path, backup_status_path)
    try:
        with open(status_path, "w") as f:
            f.write("BAD")
        result_bad = subprocess.run([script_path], capture_output=True)
        assert result_bad.returncode == 1, f"health_check.sh should exit with 1 when status is not OK, got {result_bad.returncode}"

        # Test with missing status
        os.remove(status_path)
        result_missing = subprocess.run([script_path], capture_output=True)
        assert result_missing.returncode == 1, f"health_check.sh should exit with 1 when status.txt is missing, got {result_missing.returncode}"
    finally:
        if os.path.exists(status_path):
            os.remove(status_path)
        shutil.move(backup_status_path, status_path)


def test_backup_script():
    script_path = "/home/user/app/backup.sh"
    backup_dir = "/home/user/backup"
    backup_file = os.path.join(backup_dir, "data_backup.tar.gz")
    input_path = "/home/user/app/data_v1/input.txt"
    sentinel_name = f"backup_probe_{secrets.token_hex(8)}.bin"
    sentinel_path = os.path.join("/home/user/app/data_v1", sentinel_name)
    probe_input = secrets.token_bytes(47)
    probe_sentinel = secrets.token_bytes(61)

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(input_path, "rb") as f:
        original_input = f.read()

    try:
        with open(input_path, "wb") as f:
            f.write(probe_input)
        with open(sentinel_path, "wb") as f:
            f.write(probe_sentinel)

        if os.path.exists(backup_file):
            os.remove(backup_file)

        result = subprocess.run([script_path], capture_output=True)
        assert result.returncode == 0, f"backup.sh failed with exit code {result.returncode}"

        assert os.path.isfile(backup_file), f"Backup file {backup_file} was not created by the script."

        with tarfile.open(backup_file, "r:gz") as tar:
            names = tar.getnames()
            # Retain the original input.txt presence assertion.
            has_input = any(name.endswith("input.txt") for name in names)
            assert has_input, "The backup tarball does not contain input.txt from the data_v1 directory."

            def matching_regular_files(relative_name):
                expected = f"data_v1/{relative_name}"
                matches = []
                for member in tar.getmembers():
                    normalized = posixpath.normpath(member.name.lstrip("/"))
                    if (normalized == expected or normalized.endswith("/" + expected)) and member.isfile():
                        extracted = tar.extractfile(member)
                        if extracted is not None:
                            matches.append(extracted.read())
                return matches

            input_copies = matching_regular_files("input.txt")
            assert probe_input in input_copies, (
                "The archived data_v1/input.txt does not match the current source file."
            )
            sentinel_copies = matching_regular_files(sentinel_name)
            assert probe_sentinel in sentinel_copies, (
                "The backup does not contain the dynamically created file from data_v1."
            )
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if os.path.exists(sentinel_path):
            os.remove(sentinel_path)


def test_cron_txt():
    cron_path = "/home/user/app/cron.txt"
    assert os.path.isfile(cron_path), f"{cron_path} does not exist."

    with open(cron_path, "r") as f:
        raw_content = f.read()
    lines = [line.strip() for line in raw_content.splitlines() if line.strip()]

    assert len(lines) > 0, f"{cron_path} is empty."

    expected_cron = "0 * * * * /home/user/app/backup.sh"
    found = any(expected_cron in line for line in lines)
    assert found, f"Could not find the exact cron expression '{expected_cron}' in {cron_path}"
    assert raw_content in (expected_cron, expected_cron + "\n"), (
        f"{cron_path} must contain only the raw cron job line."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
