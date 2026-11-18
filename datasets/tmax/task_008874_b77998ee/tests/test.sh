#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import shutil
import stat
import subprocess
import sys
import uuid
import zipfile


def assert_original_final_state():
    config_path = "/home/user/backup_config.txt"
    assert os.path.isfile(config_path), f"File {config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
    assert "/home/user/backups" in content, "The config file does not contain the new path '/home/user/backups'."
    assert "/var/old_backups" not in content, "The config file still contains the old path '/var/old_backups'."

    log_path = "/home/user/vulnerable_archives.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == sorted(lines), f"Lines in {log_path} are not sorted alphabetically."
    expected = ["backup_absolute.zip", "backup_malicious.zip"]
    assert sorted(lines) == expected, f"Expected {expected} in {log_path}, got {lines}."

    log_path = "/home/user/safe_archives.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == sorted(lines), f"Lines in {log_path} are not sorted alphabetically."
    expected = ["backup_safe1.zip", "backup_safe2.zip"]
    assert sorted(lines) == expected, f"Expected {expected} in {log_path}, got {lines}."

    safe1 = "/home/user/extracted/safe1.txt"
    safe2 = "/home/user/extracted/safe2.txt"
    assert os.path.isfile(safe1), f"Safe extracted file {safe1} is missing."
    assert os.path.isfile(safe2), f"Safe extracted file {safe2} is missing."

    evil1 = "/home/user/extracted/evil.sh"
    evil2 = "/home/user/evil.sh"
    evil3 = "/etc/passwd_overwrite"
    assert not os.path.exists(evil1), f"Malicious file {evil1} was extracted!"
    assert not os.path.exists(evil2), f"Malicious file {evil2} was extracted!"
    assert not os.path.exists(evil3), f"Malicious file {evil3} was extracted!"


def read_log(path):
    assert os.path.isfile(path), f"Expected log {path} was not created."
    with open(path, "r") as f:
        text = f.read()
    lines = text.splitlines()
    assert all(line and line == os.path.basename(line) for line in lines), \
        f"{path} must contain only non-empty base filenames, one per line."
    assert lines == sorted(lines), f"Lines in {path} are not sorted alphabetically: {lines}"
    return lines


def test_submission():
    # Preserve all assertions made by the original verifier.
    assert_original_final_state()

    script = "/home/user/extract_safe.py"
    assert os.path.lexists(script), f"Required script {script} is missing."
    assert not os.path.islink(script), f"{script} must be a regular Python script, not a symlink."
    assert stat.S_ISREG(os.stat(script).st_mode), f"{script} is not a regular file."

    token = uuid.uuid4().hex
    backup_dir = "/home/user/backups"
    saved_dir = f"/home/user/backups.verifier_saved.{token}"
    extracted_dir = "/home/user/extracted"
    safe_log = "/home/user/safe_archives.log"
    vulnerable_log = "/home/user/vulnerable_archives.log"
    traversal_target = f"/home/user/{token}_traversal_escape"
    absolute_target = f"/tmp/{token}_absolute_escape"

    names = [f"{uuid.uuid4().hex}.zip" for _ in range(4)]
    safe_name, absolute_name, traversal_name, locked_name = names
    safe_member = f"nested/{token}_safe.txt"
    locked_member = f"{token}_locked.txt"
    vulnerable_benign_1 = f"{token}_absolute_archive_benign.txt"
    vulnerable_benign_2 = f"{token}_traversal_archive_benign.txt"

    had_backup_dir = os.path.lexists(backup_dir)
    if had_backup_dir:
        os.replace(backup_dir, saved_dir)
    os.mkdir(backup_dir)

    shutil.rmtree(extracted_dir, ignore_errors=True)
    os.mkdir(extracted_dir)
    for path in (safe_log, vulnerable_log, traversal_target, absolute_target):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)

    archive_members = {
        safe_name: [(safe_member, f"safe-{token}")],
        absolute_name: [
            (vulnerable_benign_1, "must not be extracted"),
            (absolute_target, "absolute escape"),
        ],
        traversal_name: [
            (vulnerable_benign_2, "must not be extracted"),
            (f"../{token}_traversal_escape", "traversal escape"),
        ],
        locked_name: [(locked_member, f"locked-{token}")],
    }

    # Deliberately create archives in reverse filename order so processing order
    # alone cannot accidentally satisfy the alphabetical-log requirement.
    for archive_name in sorted(archive_members, reverse=True):
        with zipfile.ZipFile(os.path.join(backup_dir, archive_name), "w") as zf:
            for member, data in archive_members[archive_name]:
                zf.writestr(member, data)

    # Derive expected classification directly from the generated ZIP metadata.
    safe_expected = []
    vulnerable_expected = []
    for archive_name in names:
        with zipfile.ZipFile(os.path.join(backup_dir, archive_name)) as zf:
            vulnerable = any(
                info.filename.startswith("/") or "../" in info.filename
                for info in zf.infolist()
            )
        (vulnerable_expected if vulnerable else safe_expected).append(archive_name)

    locked_path = os.path.join(backup_dir, locked_name)
    locked_file = open(locked_path, "rb")
    try:
        # Hold both BSD flock and POSIX record locks so implementations using
        # either fcntl.flock or fcntl.lockf must non-blockingly skip this ZIP.
        fcntl.flock(locked_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.lockf(locked_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        result = subprocess.run(
            [sys.executable, script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"Running {script} failed. stdout={result.stdout!r} stderr={result.stderr!r}"

        safe_expected.remove(locked_name)
        assert read_log(safe_log) == sorted(safe_expected)
        assert read_log(vulnerable_log) == sorted(vulnerable_expected)

        safe_path = os.path.join(extracted_dir, safe_member)
        assert os.path.isfile(safe_path), f"Safe member {safe_member} was not extracted."
        with open(safe_path) as f:
            assert f.read() == f"safe-{token}", "Extracted safe content is incorrect."

        assert not os.path.exists(os.path.join(extracted_dir, locked_member)), \
            "The locked archive was processed instead of being skipped."
        assert not os.path.exists(traversal_target), "A traversal member escaped the extraction directory."
        assert not os.path.exists(absolute_target), "An absolute member was extracted outside the destination."

        found_names = set()
        for _, _, files in os.walk(extracted_dir):
            found_names.update(files)
        assert vulnerable_benign_1 not in found_names, \
            "Part of an absolute-path-vulnerable archive was extracted."
        assert vulnerable_benign_2 not in found_names, \
            "Part of a traversal-vulnerable archive was extracted."
    finally:
        try:
            fcntl.lockf(locked_file.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        try:
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        locked_file.close()
        shutil.rmtree(backup_dir, ignore_errors=True)
        if had_backup_dir and os.path.lexists(saved_dir):
            os.replace(saved_dir, backup_dir)
        for path in (traversal_target, absolute_target):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
