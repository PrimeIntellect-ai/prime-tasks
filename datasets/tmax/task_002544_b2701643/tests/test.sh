#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import shutil
import subprocess
import tarfile

import pytest

BACKUP = "/home/user/backups/users.tar.gz"
EXPECT_SCRIPT = "/home/user/test_restore.exp"
RESTORE_SCRIPT = "/home/user/restore.sh"


def inspect_archive(probe_name, probe_data):
    assert os.path.isfile(BACKUP), f"Backup archive {BACKUP} was not created."
    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            names = tar.getnames()
            assert "alice.txt" in names or "./alice.txt" in names, "alice.txt missing from the backup archive."
            assert "bob.txt" in names or "./bob.txt" in names, "bob.txt missing from the backup archive."
            member = probe_name if probe_name in names else f"./{probe_name}"
            assert member in names, "The newly-created probe file is missing from the backup archive."
            extracted = tar.extractfile(member)
            assert extracted is not None and extracted.read() == probe_data, "Probe data in the archive is incorrect."
    except tarfile.TarError as exc:
        pytest.fail(f"The file {BACKUP} is not a valid gzip-compressed tar archive: {exc}")


@pytest.fixture(scope="session", autouse=True)
def exercise_requested_workflow():
    probe_name = f"verifier_probe_{secrets.token_hex(8)}.txt"
    probe_data = secrets.token_bytes(48)
    probe_path = os.path.join("/home/user/users_data", probe_name)
    saved_restore = f"/tmp/restore.sh.{secrets.token_hex(8)}"

    with open(probe_path, "wb") as f:
        f.write(probe_data)

    try:
        for path in (BACKUP, "/tmp/users.tar.gz"):
            if os.path.lexists(path):
                os.remove(path)

        cron = subprocess.run(
            ["/home/user/cron_run.sh"],
            cwd="/tmp",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
        )
        assert cron.returncode == 0, f"cron_run.sh failed:\n{cron.stdout}"
        assert not os.path.exists("/tmp/users.tar.gz"), "The cron run still wrote users.tar.gz in /tmp."
        inspect_archive(probe_name, probe_data)

        # Independently execute the Go artifact from the cron working directory so
        # changing cron_run.sh cannot substitute for fixing backup.go.
        os.remove(BACKUP)
        direct = subprocess.run(
            ["/usr/local/go/bin/go", "run", "/home/user/backup.go"],
            cwd="/tmp",
            env={},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
        )
        assert direct.returncode == 0, f"backup.go failed when run from /tmp:\n{direct.stdout}"
        assert not os.path.exists("/tmp/users.tar.gz"), "backup.go still writes users.tar.gz relative to /tmp."
        inspect_archive(probe_name, probe_data)

        assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} does not exist."
        with open(EXPECT_SCRIPT, "r") as f:
            expect_content = f.read()
        assert "Enter backup file path: " in expect_content, "The exact restore prompt is missing from the Expect script."
        assert "Restore complete" in expect_content, "The Expect script does not wait for the completion message."

        for entry in os.listdir("/home/user/restored_data"):
            path = os.path.join("/home/user/restored_data", entry)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

        # Temporarily instrument the required absolute restore path. The wrapper
        # accepts only the specified response, then delegates extraction to the
        # original restore.sh. This proves the Expect program really spawns and
        # interacts with that path rather than relying on pre-populated files.
        os.replace(RESTORE_SCRIPT, saved_restore)
        wrapper = f'''#!/bin/bash
printf 'Enter backup file path: '
IFS= read -r filepath || exit 40
[ "$filepath" = '/home/user/backups/users.tar.gz' ] || exit 41
sleep 0.4
printf '%s\\n' "$filepath" | {shlex.quote(saved_restore)}
'''
        with open(RESTORE_SCRIPT, "w") as f:
            f.write(wrapper)
        os.chmod(RESTORE_SCRIPT, 0o755)

        try:
            restored = subprocess.run(
                ["/usr/bin/expect", EXPECT_SCRIPT],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
            )
            assert restored.returncode == 0, f"Expect restore automation failed:\n{restored.stdout}"
        finally:
            if os.path.lexists(RESTORE_SCRIPT):
                os.remove(RESTORE_SCRIPT)
            os.replace(saved_restore, RESTORE_SCRIPT)

        restored_probe = os.path.join("/home/user/restored_data", probe_name)
        assert os.path.isfile(restored_probe), "Running the Expect script did not restore the probe file."
        with open(restored_probe, "rb") as f:
            assert f.read() == probe_data, "The restored probe file has incorrect contents."

        yield
    finally:
        if os.path.lexists(saved_restore):
            if os.path.lexists(RESTORE_SCRIPT):
                os.remove(RESTORE_SCRIPT)
            os.replace(saved_restore, RESTORE_SCRIPT)
        if os.path.exists(probe_path):
            os.remove(probe_path)


def test_backup_go_fixed():
    backup_file = "/home/user/backup.go"
    assert os.path.isfile(backup_file), f"File {backup_file} does not exist"
    with open(backup_file, "r") as f:
        content = f.read()
    assert "/home/user/backups/users.tar.gz" in content, (
        "The Go backup script does not contain the correct absolute path '/home/user/backups/users.tar.gz'."
    )


def test_backup_archive_exists_and_valid():
    assert os.path.isfile(BACKUP), f"Backup archive {BACKUP} was not created."
    try:
        with tarfile.open(BACKUP, "r:gz") as tar:
            names = tar.getnames()
            assert "alice.txt" in names or "./alice.txt" in names, "alice.txt missing from the backup archive."
            assert "bob.txt" in names or "./bob.txt" in names, "bob.txt missing from the backup archive."
    except tarfile.TarError:
        pytest.fail(f"The file {BACKUP} is not a valid gzip-compressed tar archive.")


def test_restored_data():
    alice_file = "/home/user/restored_data/alice.txt"
    bob_file = "/home/user/restored_data/bob.txt"

    assert os.path.isfile(alice_file), f"Restored file {alice_file} does not exist. Did the restore script run correctly?"
    with open(alice_file, "r") as f:
        assert f.read().strip() == "alice config", f"Content of {alice_file} is incorrect."

    assert os.path.isfile(bob_file), f"Restored file {bob_file} does not exist."
    with open(bob_file, "r") as f:
        assert f.read().strip() == "bob config", f"Content of {bob_file} is incorrect."


def test_expect_script():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} does not exist."
    with open(EXPECT_SCRIPT, "r") as f:
        content = f.read()

    assert "spawn" in content, f"'spawn' command missing from {EXPECT_SCRIPT}."
    assert "expect" in content, f"'expect' command missing from {EXPECT_SCRIPT}."
    assert "send" in content, f"'send' command missing from {EXPECT_SCRIPT}."
    assert "/home/user/backups/users.tar.gz" in content, f"The absolute backup path is missing from {EXPECT_SCRIPT}."


def test_fstab_entry():
    fstab_file = "/home/user/fstab_entry.txt"
    assert os.path.isfile(fstab_file), f"File {fstab_file} does not exist."

    with open(fstab_file, "r") as f:
        content = f.read().strip()

    expected_entry = "UUID=1234-5678-ABCD /home/user/backups ext4 defaults 0 2"
    assert content == expected_entry, (
        f"Contents of {fstab_file} are incorrect.\n"
        f"Expected: {expected_entry}\n"
        f"Found: {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
