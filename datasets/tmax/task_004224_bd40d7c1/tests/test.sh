#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import uuid
from collections import Counter


def test_c_files_exist():
    assert os.path.isfile("/home/user/provision_backup.c"), "C source file /home/user/provision_backup.c is missing."
    assert os.path.isfile("/home/user/provision_backup"), "Executable /home/user/provision_backup is missing."
    assert os.access("/home/user/provision_backup", os.X_OK), "Executable /home/user/provision_backup is not executable."


def test_provision_log_contents():
    log_file = "/home/user/provision.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert "BACKUP_SUCCESS: alice" in lines, "Missing BACKUP_SUCCESS: alice in log."
    assert "QUOTA_EXCEEDED: bob" in lines, "Missing QUOTA_EXCEEDED: bob in log."
    assert "BACKUP_SUCCESS: charlie" in lines, "Missing BACKUP_SUCCESS: charlie in log."


def test_backup_files():
    alice_backup = "/home/user/backups/alice_backup.tar.gz"
    charlie_backup = "/home/user/backups/charlie_backup.tar.gz"
    bob_backup = "/home/user/backups/bob_backup.tar.gz"

    assert os.path.isfile(alice_backup), f"Backup file {alice_backup} should exist."
    assert os.path.isfile(charlie_backup), f"Backup file {charlie_backup} should exist."
    assert not os.path.exists(bob_backup), f"Backup file {bob_backup} should NOT exist because bob exceeded quota."


def test_tarball_contents():
    alice_backup = "/home/user/backups/alice_backup.tar.gz"
    charlie_backup = "/home/user/backups/charlie_backup.tar.gz"

    if os.path.isfile(alice_backup):
        with tarfile.open(alice_backup, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("file.txt") for name in names), "Alice's backup does not contain file.txt."

    if os.path.isfile(charlie_backup):
        with tarfile.open(charlie_backup, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("file.txt") for name in names), "Charlie's backup does not contain file.txt."


def _replace_directory(path):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)
    os.makedirs(path)


def _prepare_dynamic_fixture(tag):
    user_data = "/home/user/user_data"
    backups = "/home/user/backups"
    _replace_directory(user_data)
    _replace_directory(backups)

    log_path = "/home/user/provision.log"
    if os.path.lexists(log_path):
        if os.path.isdir(log_path) and not os.path.islink(log_path):
            shutil.rmtree(log_path)
        else:
            os.unlink(log_path)

    users = [
        (f"under_{tag}", 417, 418, True),
        (f"over_{tag}", 9001, 9000, False),
        (f"equal_{tag}", 765432, 765432, True),
    ]

    expected_files = {}
    for index, (username, used, quota, should_backup) in enumerate(users):
        root = os.path.join(user_data, username)
        os.makedirs(os.path.join(root, "nested"))
        files = {
            f"{username}/file.txt": f"dynamic file for {username} #{index}\n".encode(),
            f"{username}/nested/payload.bin": (f"payload:{tag}:{used}:{quota}").encode(),
        }
        for archive_name, content in files.items():
            relative = archive_name.split("/", 1)[1]
            with open(os.path.join(root, relative), "wb") as f:
                f.write(content)
        if should_backup:
            expected_files[username] = files

    with open("/home/user/quota_data.txt", "w", encoding="utf-8") as f:
        for username, used, quota, _ in users:
            f.write(f"{username}:{used}:{quota}\n")

    return users, expected_files


def _check_archive(username, expected):
    archive = f"/home/user/backups/{username}_backup.tar.gz"
    assert os.path.isfile(archive), f"Expected backup {archive} was not created."

    with tarfile.open(archive, "r:gz") as tar:
        actual = {}
        for member in tar.getmembers():
            normalized = member.name
            while normalized.startswith("./"):
                normalized = normalized[2:]
            assert not normalized.startswith("/"), "Archive contains an absolute path."
            assert ".." not in normalized.split("/"), "Archive contains a traversal path."
            if member.isfile():
                stream = tar.extractfile(member)
                assert stream is not None
                actual[normalized] = stream.read()

    assert actual == expected, f"Backup for {username} does not match that user's source data."


def _exercise(executable, tag):
    users, expected_files = _prepare_dynamic_fixture(tag)
    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20, check=False)
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )

    assert os.path.isfile("/home/user/provision.log"), "Program did not create provision.log."
    with open("/home/user/provision.log", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        ("BACKUP_SUCCESS: " if should_backup else "QUOTA_EXCEEDED: ") + username
        for username, _, _, should_backup in users
    ]
    assert Counter(actual_lines) == Counter(expected_lines), (
        "Log decisions do not match the dynamically supplied quota data."
    )

    for username, _, _, should_backup in users:
        archive = f"/home/user/backups/{username}_backup.tar.gz"
        if should_backup:
            _check_archive(username, expected_files[username])
        else:
            assert not os.path.exists(archive), (
                f"Backup {archive} was created even though the user exceeds quota."
            )


def test_executable_and_c_source_on_dynamic_inputs():
    with open("/home/user/provision_backup", "rb") as f:
        assert f.read(4) == b"\x7fELF", "provision_backup is not a compiled executable."

    _exercise("/home/user/provision_backup", uuid.uuid4().hex[:10])

    rebuilt = "/tmp/provision_backup_rebuilt"
    compile_result = subprocess.run(
        ["cc", "/home/user/provision_backup.c", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
    )
    assert compile_result.returncode == 0, (
        "provision_backup.c does not compile: "
        + compile_result.stderr.decode(errors="replace")
    )
    _exercise(rebuilt, uuid.uuid4().hex[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
