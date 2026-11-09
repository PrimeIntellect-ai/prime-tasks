#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def test_backup_dir_contents():
    """Verify that the backup directory contains exactly the expected .txt files."""
    backup_dir = "/home/user/backup_dir"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    expected_files = {
        "another file.txt",
        "file 1.txt",
        "file2.txt",
        "normal.txt"
    }

    actual_files = set(os.listdir(backup_dir))

    missing_files = expected_files - actual_files
    assert not missing_files, f"Missing files in backup directory: {missing_files}"

    unexpected_files = actual_files - expected_files
    assert not unexpected_files, f"Unexpected files in backup directory: {unexpected_files}"


def test_success_log_contents():
    """Verify that success.log contains the sorted list of backed-up .txt files."""
    log_file = "/home/user/success.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "another file.txt",
        "file 1.txt",
        "file2.txt",
        "normal.txt"
    ]

    assert content == expected_content, f"Contents of {log_file} do not match the expected sorted list of filenames. Got: {content}"


def test_backup_script_executable():
    """Verify that the backup script is still executable."""
    script_path = "/home/user/backup.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is no longer executable."


def test_backup_script_handles_runtime_files_with_spaces():
    """Execute the submitted script on fresh inputs and verify exact copied data."""
    script_path = "/home/user/backup.sh"
    nonce = secrets.token_hex(8)

    with tempfile.TemporaryDirectory(prefix="backup-script-check-") as root:
        source_dir = os.path.join(root, "source directory")
        destination_dir = os.path.join(root, "destination directory")
        os.mkdir(source_dir)

        expected = {
            f"alpha {nonce}.txt": os.urandom(31),
            f"multiple word name {nonce}.txt": os.urandom(47),
            f"plain-{nonce}.txt": os.urandom(19),
        }
        ignored_name = f"not text {nonce}.log"

        for filename, data in expected.items():
            with open(os.path.join(source_dir, filename), "wb") as f:
                f.write(data)
        with open(os.path.join(source_dir, ignored_name), "wb") as f:
            f.write(os.urandom(23))

        result = subprocess.run(
            [script_path, source_dir, destination_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert result.returncode == 0, (
            f"backup.sh exited with status {result.returncode}. "
            f"stderr: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isdir(destination_dir), "backup.sh did not create the destination directory."

        actual_names = set(os.listdir(destination_dir))
        assert actual_names == set(expected), (
            f"Runtime backup contents were incorrect. Expected {set(expected)}, got {actual_names}"
        )

        for filename, original_data in expected.items():
            copied_path = os.path.join(destination_dir, filename)
            assert os.path.isfile(copied_path), f"Copied entry is not a regular file: {filename}"
            with open(copied_path, "rb") as f:
                copied_data = f.read()
            assert copied_data == original_data, f"Copied data was mangled for {filename}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
