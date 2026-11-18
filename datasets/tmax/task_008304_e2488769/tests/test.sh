#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import secrets
import shutil
import signal
import stat
import subprocess
import tempfile
import time


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def hash_bytes(data):
    return hashlib.sha256(data).hexdigest()


def test_script_exists_and_uses_flock():
    script_path = "/home/user/config_backup.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, "The script must use 'flock' for file locking."
    assert "configs.lock" in content, "The script must lock /home/user/configs.lock."

    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), "The backup script must be a regular file, not a symlink."
    result = subprocess.run(
        ["/bin/bash", "-n", script_path], capture_output=True, text=True
    )
    assert result.returncode == 0, f"The backup script is not valid Bash: {result.stderr}"


def test_new_manifest_correctness():
    manifest_path = "/home/user/new_manifest.txt"
    assert os.path.isfile(manifest_path), f"New manifest {manifest_path} does not exist."

    expected_files = [
        "/home/user/configs/cache.conf",
        "/home/user/configs/db.conf",
        "/home/user/configs/web.conf"
    ]

    expected_lines = []
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected config file {filepath} is missing."
        checksum = get_sha256(filepath)
        expected_lines.append(f"{checksum}  {filepath}")

    expected_lines.sort()

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The new manifest does not match the expected sorted checksums of regular files."


def test_backup_diff_contents():
    backup_dir = "/home/user/backup_diff"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    backed_up_files = set(os.listdir(backup_dir))
    expected_files = {"web.conf", "cache.conf"}

    assert backed_up_files == expected_files, f"Backup directory should contain exactly {expected_files}, but found {backed_up_files}."

    for filename in expected_files:
        original = os.path.join("/home/user/configs", filename)
        backup = os.path.join(backup_dir, filename)

        assert get_sha256(original) == get_sha256(backup), f"Backed up file {filename} does not match the original."


def test_script_execution_locking_traversal_and_differential_behavior():
    script_path = "/home/user/config_backup.sh"
    configs = "/home/user/configs"
    old_manifest = "/home/user/old_manifest.txt"
    new_manifest = "/home/user/new_manifest.txt"
    backup_dir = "/home/user/backup_diff"
    lock_path = "/home/user/configs.lock"

    state_dir = tempfile.mkdtemp(prefix="backup-verifier-")
    saved = {}
    process = None
    lock_file = None
    external_target = os.path.join(state_dir, "external.conf")

    def save_path(path):
        if os.path.lexists(path):
            destination = os.path.join(state_dir, "saved_" + os.path.basename(path))
            os.rename(path, destination)
            saved[path] = destination

    try:
        for path in (configs, old_manifest, new_manifest, backup_dir):
            save_path(path)

        token = secrets.token_hex(6)
        unchanged_name = f"a_unchanged_{token}.conf"
        changed_name = f"b_changed_{token}.conf"
        new_name = f"c_new_{token}.conf"
        nested_name = f"d_nested_{token}.conf"

        unchanged_path = os.path.join(configs, unchanged_name)
        changed_path = os.path.join(configs, changed_name)
        new_path = os.path.join(configs, new_name)
        nested_path = os.path.join(configs, "subdir", nested_name)

        os.makedirs(os.path.dirname(nested_path), exist_ok=True)
        with open(unchanged_path, "wb") as f:
            f.write(b"decoy unchanged content\n")
        with open(changed_path, "wb") as f:
            f.write(b"decoy changed content\n")
        with open(nested_path, "wb") as f:
            f.write(b"decoy nested content\n")
        with open(old_manifest, "w") as f:
            f.write("0" * 64 + f"  {changed_path}\n")

        with open(external_target, "wb") as f:
            f.write(b"this symlink target must be ignored\n")
        os.symlink(external_target, os.path.join(configs, "external_link"))
        os.symlink(os.path.join(configs, "loop2"), os.path.join(configs, "loop1"))
        os.symlink(os.path.join(configs, "loop1"), os.path.join(configs, "loop2"))
        os.symlink(configs, os.path.join(configs, "self_link"))

        lock_file = open(lock_path, "a+")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

        process = subprocess.Popen(
            ["/bin/bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        time.sleep(1.0)

        assert process.poll() is None, "The script did not wait for the held configs.lock."
        assert not os.path.exists(new_manifest), "The script wrote the manifest before acquiring configs.lock."
        assert not os.path.exists(backup_dir), "The script created the backup before acquiring configs.lock."

        unchanged_data = f"stable-{token}\n".encode()
        changed_old_data = f"old-{token}\n".encode()
        changed_new_data = f"changed-{token}\n".encode()
        new_data = f"new-{token}\n".encode()
        nested_data = f"nested-{token}\n".encode()

        with open(unchanged_path, "wb") as f:
            f.write(unchanged_data)
        with open(changed_path, "wb") as f:
            f.write(changed_new_data)
        with open(new_path, "wb") as f:
            f.write(new_data)
        with open(nested_path, "wb") as f:
            f.write(nested_data)
        with open(old_manifest, "w") as f:
            f.write(f"{hash_bytes(unchanged_data)}  {unchanged_path}\n")
            f.write(f"{hash_bytes(changed_old_data)}  {changed_path}\n")

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        stdout, stderr = process.communicate(timeout=15)
        assert process.returncode == 0, (
            f"Executing the backup script failed with code {process.returncode}.\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )
        process = None

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

        regular_files = [unchanged_path, changed_path, new_path, nested_path]
        expected_lines = [f"{get_sha256(path)}  {path}" for path in regular_files]
        expected_lines.sort(key=lambda line: line.split("  ", 1)[1])

        assert os.path.isfile(new_manifest), "Executing the script did not create new_manifest.txt."
        with open(new_manifest, "r") as f:
            actual_lines = f.read().splitlines()
        assert actual_lines == expected_lines, (
            "The executed script did not generate an exact manifest sorted by full file path, "
            "or it included a symlink/non-regular file."
        )

        assert os.path.isdir(backup_dir), "Executing the script did not create backup_diff."
        expected_backups = {changed_name, new_name, nested_name}
        assert set(os.listdir(backup_dir)) == expected_backups, (
            "The executed script did not select changed and newly added files correctly."
        )
        for source in (changed_path, new_path, nested_path):
            copied = os.path.join(backup_dir, os.path.basename(source))
            assert os.path.isfile(copied)
            assert get_sha256(copied) == get_sha256(source)
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        if lock_file is not None:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            lock_file.close()
        for path in (backup_dir, new_manifest, old_manifest, configs):
            if os.path.islink(path) or os.path.isfile(path):
                os.unlink(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
        for original, stored in saved.items():
            os.rename(stored, original)
        shutil.rmtree(state_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
