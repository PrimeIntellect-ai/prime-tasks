#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import subprocess
import tarfile

import pytest

PROJECT = pathlib.Path("/home/user/project")
EMAILS = PROJECT / "emails.txt"
VALID = PROJECT / "valid_emails.txt"
APP = PROJECT / "app"
BACKUP = pathlib.Path("/home/user/backup.sh")
DAEMON = pathlib.Path("/home/user/ci_daemon.sh")
ARCHIVE = pathlib.Path("/home/user/backups/project_backup.tar.gz")
NOTIFICATION = pathlib.Path("/home/user/mail_spool/notification.txt")


def test_01_valid_emails_content():
    assert VALID.is_file(), f"File {VALID} is missing."
    content = VALID.read_text().strip().splitlines()
    expected = ["admin@example.com", "user@domain.com"]
    assert content == expected, f"Content of {VALID} does not match expected valid emails. Got: {content}"


def test_02_backup_script_exists_and_executable():
    assert BACKUP.is_file(), f"Backup script {BACKUP} is missing."
    assert os.access(BACKUP, os.X_OK), f"Backup script {BACKUP} is not executable."


def test_03_backup_archive_exists_and_valid():
    assert ARCHIVE.is_file(), f"Backup archive {ARCHIVE} is missing."
    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            members = tar.getnames()
            assert len(members) > 0, "Tar archive is empty."
    except tarfile.ReadError:
        pytest.fail(f"File {ARCHIVE} is not a valid gzip-compressed tar archive.")


def test_04_notification_email_content():
    assert NOTIFICATION.is_file(), f"Notification file {NOTIFICATION} is missing."
    content = NOTIFICATION.read_text().strip()
    assert content == "BUILD SUCCESS", (
        f"Notification file content is incorrect. Expected 'BUILD SUCCESS', got '{content}'"
    )


def test_05_ci_daemon_fixed():
    assert DAEMON.is_file(), f"Daemon script {DAEMON} is missing."
    assert os.access(DAEMON, os.X_OK), f"Daemon script {DAEMON} is not executable."
    content = DAEMON.read_text()
    assert "set -e" in content or "set -o errexit" in content, (
        "Daemon script does not appear to have 'set -e' for error handling."
    )
    assert "then" in content, "Daemon script seems to still be missing 'then' in its if-statement."


def test_06_pipeline_and_artifacts_work():
    assert (PROJECT / "main.cpp").is_file(), "main.cpp is missing."
    assert BACKUP.is_file() and os.access(BACKUP, os.X_OK)
    assert DAEMON.is_file() and os.access(DAEMON, os.X_OK)

    subprocess.run(["bash", "-n", str(BACKUP)], check=True)
    subprocess.run(["bash", "-n", str(DAEMON)], check=True)

    backup_text = BACKUP.read_text()
    assert "set -e" in backup_text or "set -o errexit" in backup_text, (
        "Backup script does not enable immediate exit on errors."
    )

    # The backup script must reject anything other than exactly one argument.
    assert subprocess.run([str(BACKUP)]).returncode != 0
    assert subprocess.run([str(BACKUP), str(PROJECT), str(PROJECT)]).returncode != 0

    token = secrets.token_hex(12)
    direct_lines = [
        f"{token}@example.com",
        f"invalid-{token}",
        f"double@{token}@example.com",
        "@",
        f"left@{token}",
        f"{token}@",
    ]
    direct_expected = [line for line in direct_lines if line.count("@") == 1]
    EMAILS.write_text("\n".join(direct_lines) + "\n")

    # Compile and execute the submitted C++ source independently.
    verifier_app = pathlib.Path("/tmp/verifier_compiled_app")
    subprocess.run(
        ["g++", str(PROJECT / "main.cpp"), "-o", str(verifier_app)],
        check=True,
        timeout=30,
    )
    VALID.unlink(missing_ok=True)
    subprocess.run([str(verifier_app)], check=True, timeout=15)
    assert VALID.is_file(), "The compiled C++ application did not create valid_emails.txt."
    assert VALID.read_text().splitlines() == direct_expected

    # Use a fresh, unpredictable input for the actual daemon run.
    token2 = secrets.token_hex(12)
    pipeline_lines = [
        f"admin-{token2}@example.com",
        f"bad-{token2}",
        f"a@b@{token2}",
        f"user@{token2}.test",
        "@",
    ]
    pipeline_expected = [line for line in pipeline_lines if line.count("@") == 1]
    EMAILS.write_text("\n".join(pipeline_lines) + "\n")

    for path in (VALID, APP, ARCHIVE, NOTIFICATION):
        path.unlink(missing_ok=True)

    # Wrap the submitted backup script temporarily to prove the daemon calls it
    # with the required project-directory argument.
    marker = pathlib.Path(f"/tmp/backup_called_{secrets.token_hex(8)}")
    saved_backup = pathlib.Path(f"/tmp/submitted_backup_{secrets.token_hex(8)}.sh")
    os.rename(BACKUP, saved_backup)
    try:
        BACKUP.write_text(
            "#!/bin/bash\n"
            "set -e\n"
            f"printf '%s\\n' \"$#\" \"${{1-}}\" > {marker}\n"
            f"exec {saved_backup} \"$@\"\n"
        )
        os.chmod(BACKUP, 0o755)
        subprocess.run([str(DAEMON)], check=True, timeout=45)
    finally:
        BACKUP.unlink(missing_ok=True)
        os.rename(saved_backup, BACKUP)

    assert marker.is_file(), "The CI daemon did not call /home/user/backup.sh."
    assert marker.read_text().splitlines() == ["1", str(PROJECT)], (
        "The CI daemon did not call backup.sh with exactly the project directory."
    )

    assert APP.is_file() and os.access(APP, os.X_OK), "The daemon did not produce an executable app."
    assert APP.read_bytes().startswith(b"\x7fELF"), "The daemon's app is not a compiled executable."
    assert VALID.is_file(), "The daemon run did not create valid_emails.txt."
    assert VALID.read_text().splitlines() == pipeline_expected
    assert NOTIFICATION.is_file()
    assert NOTIFICATION.read_text().strip() == "BUILD SUCCESS"

    assert ARCHIVE.is_file(), "The daemon run did not create the backup archive."
    app_bytes = APP.read_bytes()
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        assert any(
            pathlib.PurePosixPath(m.name.lstrip("./")).name == "main.cpp"
            and pathlib.PurePosixPath(m.name.lstrip("./")).parent.name == "project"
            for m in members
        ), "The archive does not contain the project source."

        archived_apps = []
        for member in members:
            path = pathlib.PurePosixPath(member.name.lstrip("./"))
            if member.isfile() and path.name == "app" and path.parent.name == "project":
                extracted = tar.extractfile(member)
                if extracted is not None:
                    archived_apps.append(extracted.read())
        assert app_bytes in archived_apps, "The archive does not contain the compiled project binary."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
