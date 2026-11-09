#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import stat
import subprocess
import tarfile
import tempfile
import uuid

SCRIPTS_DIR = "/home/user/scripts"
BACKUPS_DIR = "/home/user/backups"
DATA_DIR = "/home/user/device_data"
BACKUP_SCRIPT = "/home/user/scripts/edge_backup.py"
BACKUP_ARCHIVE = "/home/user/backups/state_backup.tar.gz"
GIT_DIR = "/home/user/edge_config.git"
HOOK_PATH = "/home/user/edge_config.git/hooks/post-receive"
CRON_FILE = "/home/user/cron.txt"
CRON_PATTERN = re.compile(
    r"^\s*(?:\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+/home/user/scripts/sync_data\.sh\s*$",
    re.MULTILINE,
)


def assert_regular_executable(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def source_tree():
    files = {}
    directories = set()
    for root, dirnames, filenames in os.walk(DATA_DIR):
        rel_root = os.path.relpath(root, DATA_DIR)
        if rel_root != ".":
            directories.add(rel_root.replace(os.sep, "/"))
        for dirname in dirnames:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f"Unexpected symlink in test data: {path}"
        for filename in filenames:
            path = os.path.join(root, filename)
            assert os.path.isfile(path) and not os.path.islink(path), f"Unexpected non-regular test file: {path}"
            rel = os.path.relpath(path, DATA_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                files[rel] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
    return files, directories


def member_relative_name(name):
    normalized = name.replace("\\", "/").lstrip("/")
    parts = [part for part in normalized.split("/") if part not in ("", ".")]
    assert ".." not in parts, f"Unsafe path in archive: {name}"
    if "device_data" in parts:
        parts = parts[parts.index("device_data") + 1:]
    return "/".join(parts)


def assert_archive_matches_data():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} was not created."
    expected_files, expected_dirs = source_tree()
    archived_files = {}
    archived_dirs = set()

    with tarfile.open(BACKUP_ARCHIVE, "r:gz") as archive:
        for member in archive.getmembers():
            rel = member_relative_name(member.name)
            if not rel:
                assert member.isdir(), f"Archive root is not a directory: {member.name}"
                continue
            if member.isdir():
                archived_dirs.add(rel.rstrip("/"))
            elif member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None, f"Could not read archived file {member.name}"
                assert rel not in archived_files, f"Duplicate archived file path: {rel}"
                archived_files[rel] = (extracted.read(), member.mode & 0o7777)
            else:
                raise AssertionError(f"Unexpected archive member type for {member.name}")

    assert set(archived_files) == set(expected_files), (
        f"Archive file set differs from {DATA_DIR}. "
        f"Expected {sorted(expected_files)}, got {sorted(archived_files)}"
    )
    for rel, (expected_data, expected_mode) in expected_files.items():
        actual_data, actual_mode = archived_files[rel]
        assert actual_data == expected_data, f"Archived data differs for {rel}"
        assert actual_mode == expected_mode, f"Archived permissions differ for {rel}"
    assert archived_dirs == expected_dirs, (
        f"Archive directory set differs from {DATA_DIR}. "
        f"Expected {sorted(expected_dirs)}, got {sorted(archived_dirs)}"
    )


def test_directories_and_permissions():
    assert os.path.isdir(SCRIPTS_DIR), f"Directory {SCRIPTS_DIR} does not exist."
    assert os.path.isdir(BACKUPS_DIR), f"Directory {BACKUPS_DIR} does not exist."
    perms = stat.S_IMODE(os.stat(BACKUPS_DIR).st_mode)
    assert perms == 0o700, f"Permissions for {BACKUPS_DIR} are {oct(perms)}, expected 0o700."


def test_backup_script_exists_uses_tarfile_and_backs_up_entire_tree():
    assert_regular_executable(BACKUP_SCRIPT)
    with open(BACKUP_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=BACKUP_SCRIPT)
    imports_tarfile = any(
        (isinstance(node, ast.Import) and any(alias.name == "tarfile" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "tarfile")
        for node in ast.walk(tree)
    )
    assert imports_tarfile, f"{BACKUP_SCRIPT} does not import Python's tarfile module."

    nested = os.path.join(DATA_DIR, "audit_nested")
    os.makedirs(nested, exist_ok=True)
    nonce = os.urandom(73)
    with open(os.path.join(nested, "random payload.bin"), "wb") as f:
        f.write(nonce)
    with open(os.path.join(DATA_DIR, "audit-extra.txt"), "wb") as f:
        f.write(b"full-tree-check\x00" + os.urandom(41))

    if os.path.exists(BACKUP_ARCHIVE):
        os.remove(BACKUP_ARCHIVE)
    result = subprocess.run([BACKUP_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"Backup script failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert_archive_matches_data()


def test_git_repo_is_bare():
    assert os.path.isdir(GIT_DIR), f"Git repo directory {GIT_DIR} does not exist."
    config_file = os.path.join(GIT_DIR, "config")
    assert os.path.isfile(config_file), f"Git config file {config_file} does not exist."
    try:
        output = subprocess.check_output(
            ["git", "-C", GIT_DIR, "config", "--get", "core.bare"],
            stderr=subprocess.STDOUT,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        output = ""
    assert output == "true", f"Git repository at {GIT_DIR} is not bare (core.bare={output})."


def test_post_receive_hook_exists_executable_python_and_invokes_script():
    assert_regular_executable(HOOK_PATH)
    with open(HOOK_PATH, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "python" in first_line.lower(), (
        f"Hook {HOOK_PATH} does not have a Python shebang: {first_line}"
    )

    marker = os.path.join(tempfile.gettempdir(), "edge_backup_marker_" + uuid.uuid4().hex)
    with open(BACKUP_SCRIPT, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(BACKUP_SCRIPT).st_mode)
    replacement = (
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        f"Path({marker!r}).write_text('invoked', encoding='utf-8')\n"
    )
    try:
        with open(BACKUP_SCRIPT, "w", encoding="utf-8") as f:
            f.write(replacement)
        os.chmod(BACKUP_SCRIPT, 0o755)
        hook_input = "0" * 40 + " " + "1" * 40 + " refs/heads/verifier\n"
        result = subprocess.run(
            [HOOK_PATH], input=hook_input, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True,
        )
        assert result.returncode == 0, f"Hook failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert result.stdout == "Deployment received, backing up...\n", (
            f"Hook stdout was not exactly the required message: {result.stdout!r}"
        )
        assert os.path.isfile(marker), f"Hook did not execute {BACKUP_SCRIPT}."
    finally:
        with open(BACKUP_SCRIPT, "wb") as f:
            f.write(original_script)
        os.chmod(BACKUP_SCRIPT, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def test_crontab_schedule_and_source_file():
    assert os.path.isfile(CRON_FILE), f"Cron source file {CRON_FILE} does not exist."
    with open(CRON_FILE, "r", encoding="utf-8") as f:
        cron_contents = f.read()
    assert CRON_PATTERN.search(cron_contents), (
        f"{CRON_FILE} does not contain the expected schedule. Contents:\n{cron_contents}"
    )
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        output = ""
    assert CRON_PATTERN.search(output), (
        f"Crontab does not contain the expected schedule for sync_data.sh. Current crontab:\n{output}"
    )


def test_git_push_triggers_real_complete_backup():
    push_payload = b"push-time-state\x00" + os.urandom(59)
    with open(os.path.join(DATA_DIR, "push-state.bin"), "wb") as f:
        f.write(push_payload)
    if os.path.exists(BACKUP_ARCHIVE):
        os.remove(BACKUP_ARCHIVE)

    with tempfile.TemporaryDirectory() as temp_dir:
        clone_dir = os.path.join(temp_dir, "edge_config")
        subprocess.check_call(
            ["git", "clone", GIT_DIR, clone_dir],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        test_file = os.path.join(clone_dir, "test.conf")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write("new_config=" + uuid.uuid4().hex + "\n")
        subprocess.check_call(["git", "-C", clone_dir, "add", "test.conf"])
        subprocess.check_call(["git", "-C", clone_dir, "config", "user.email", "test@example.com"])
        subprocess.check_call(["git", "-C", clone_dir, "config", "user.name", "Test User"])
        subprocess.check_call(
            ["git", "-C", clone_dir, "commit", "-m", "Verifier test commit"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        branch = "verifier-" + uuid.uuid4().hex
        push = subprocess.run(
            ["git", "-C", clone_dir, "push", "origin", f"HEAD:refs/heads/{branch}"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        assert push.returncode == 0, f"Git push failed:\n{push.stdout}"
        assert "Deployment received, backing up..." in push.stdout, (
            f"Expected hook output not found in git push. Output was:\n{push.stdout}"
        )
    assert_archive_matches_data()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
