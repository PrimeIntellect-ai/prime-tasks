#!/bin/bash
set -u
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

REPO=/home/user/user_registry.git
LOG=/home/user/sync.log
BASELINE=/tmp/sync.log.before-verifier-push
CLONE_ROOT=$(mktemp -d /tmp/registry-verifier.XXXXXX) || fail
CLONE="$CLONE_ROOT/clone"
TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(16))') || fail
FRESH_FILE="verifier_${TOKEN}.conf"
FRESH_CONTENT="verification-token=${TOKEN}"

# Validate that this is a functioning bare repository, not merely a directory
# containing a file named config.
git config --global --add safe.directory "$REPO" >/dev/null 2>&1 || fail
BARE=$(git --git-dir="$REPO" rev-parse --is-bare-repository 2>/dev/null) || fail
[ "$BARE" = "true" ] || fail
git --git-dir="$REPO" show-ref --verify --quiet refs/heads/master || fail

[ -f "$LOG" ] || fail
cp "$LOG" "$BASELINE" || fail
PUSH_START=$(date +%s) || fail

# Perform a fresh, unpredictable push so that the submitted post-receive ELF
# must create the deployment, archive, permissions, and new log entry.
git clone --branch master "$REPO" "$CLONE" >/tmp/verifier-clone.out 2>&1 || fail
git -C "$CLONE" config user.name "Verifier" || fail
git -C "$CLONE" config user.email "verifier@example.invalid" || fail
printf '%s\n' "$FRESH_CONTENT" > "$CLONE/$FRESH_FILE" || fail
git -C "$CLONE" add "$FRESH_FILE" || fail
git -C "$CLONE" commit -m "Verifier fresh synchronization test $TOKEN" >/tmp/verifier-commit.out 2>&1 || fail
git -C "$CLONE" push origin HEAD:master >/tmp/verifier-push.out 2>&1 || fail

export FRESH_FILE FRESH_CONTENT PUSH_START BASELINE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import os
import re
import stat
import subprocess
import tarfile
import time


def test_directories_exist():
    """Check that the required directories have been created."""
    dirs = [
        "/home/user/user_registry.git",
        "/home/user/active_users",
        "/home/user/backups"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."


def test_bare_repo_exists():
    """Check that the bare repository is initialized and functional."""
    config_path = "/home/user/user_registry.git/config"
    assert os.path.isfile(config_path), f"Git bare repo config not found at {config_path}."
    result = subprocess.run(
        ["git", "--git-dir=/home/user/user_registry.git", "rev-parse", "--is-bare-repository"],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "true", "/home/user/user_registry.git is not a functioning bare repository."


def test_hook_executable_elf():
    """Check that the post-receive hook is an executable ELF binary."""
    hook_path = "/home/user/user_registry.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Post-receive hook not found at {hook_path}."
    st = os.stat(hook_path)
    assert st.st_mode & stat.S_IXUSR, f"Post-receive hook {hook_path} is not executable."
    with open(hook_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"Post-receive hook {hook_path} is not a compiled ELF binary."


def test_deployed_file():
    """Check that the master branch was checked out to active_users."""
    conf_path = "/home/user/active_users/admin_user.conf"
    assert os.path.isfile(conf_path), f"Deployed file not found at {conf_path}."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "role=superuser" in content, f"Expected 'role=superuser' in {conf_path}."


def test_fresh_push_was_deployed():
    name = os.environ["FRESH_FILE"]
    expected = os.environ["FRESH_CONTENT"] + "\n"
    path = os.path.join("/home/user/active_users", name)
    assert os.path.isfile(path), f"Freshly pushed file was not deployed: {path}"
    with open(path, "r") as f:
        assert f.read() == expected

    committed = subprocess.run(
        ["git", "--git-dir=/home/user/user_registry.git", "show", f"master:{name}"],
        text=True,
        capture_output=True,
    )
    assert committed.returncode == 0, committed.stderr
    assert committed.stdout == expected


def test_backup_archive():
    """Check the backup tarball exists, has correct permissions, and contains the file."""
    tar_path = "/home/user/backups/latest.tar.gz"
    assert os.path.isfile(tar_path), f"Backup archive not found at {tar_path}."
    st = os.stat(tar_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions for {tar_path} must be exactly 0400, got {oct(perms)}."
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."
    with tarfile.open(tar_path, "r:gz") as tar:
        names = tar.getnames()
        found = any("admin_user.conf" in name for name in names)
        assert found, f"admin_user.conf not found inside the backup archive {tar_path}."


def test_fresh_push_was_archived():
    tar_path = "/home/user/backups/latest.tar.gz"
    name = os.environ["FRESH_FILE"]
    expected = (os.environ["FRESH_CONTENT"] + "\n").encode()
    with tarfile.open(tar_path, "r:gz") as tar:
        matches = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == name]
        assert matches, f"Freshly pushed file {name} is absent from the new backup archive."
        extracted = tar.extractfile(matches[0])
        assert extracted is not None
        assert extracted.read() == expected


def test_sync_log():
    """Check that the sync log contains the correctly formatted timestamp and message."""
    log_path = "/home/user/sync.log"
    assert os.path.isfile(log_path), f"Log file not found at {log_path}."
    with open(log_path, "r") as f:
        content = f.read()
    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST\] Registry updated$"
    match_found = False
    for line in content.splitlines():
        if re.match(pattern, line.strip()):
            match_found = True
            break
    assert match_found, f"Log file {log_path} does not contain the correctly formatted JST log entry."


def test_fresh_push_appended_current_jst_log_entry():
    with open(os.environ["BASELINE"], "rb") as f:
        before = f.read()
    with open("/home/user/sync.log", "rb") as f:
        after = f.read()
    assert after.startswith(before), "The hook did not append to the existing sync log."
    assert len(after) > len(before), "The fresh push did not add a sync log entry."

    added = after[len(before):].decode("utf-8")
    pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) JST\] Registry updated$")
    matches = [pattern.fullmatch(line.strip()) for line in added.splitlines()]
    matches = [m for m in matches if m]
    assert matches, "The fresh push did not append a correctly formatted JST log entry."

    parsed = datetime.datetime.strptime(matches[-1].group(1), "%Y-%m-%d %H:%M:%S")
    logged_epoch = calendar.timegm(parsed.timetuple()) - 9 * 60 * 60
    start = int(os.environ["PUSH_START"])
    assert start - 5 <= logged_epoch <= int(time.time()) + 5, "The new JST timestamp is not from the verifier's push."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
