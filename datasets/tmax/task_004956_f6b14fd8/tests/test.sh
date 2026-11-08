#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import signal
import stat
import subprocess
import time
import uuid

import pytest

HOME = "/home/user"
REPO = f"{HOME}/migration_repo.git"
WORKSPACE = f"{HOME}/workspace"
DEPLOY = f"{HOME}/deploy_worktree"
BINARY = f"{DEPLOY}/migrator/target/release/migrator"
PID_FILE = f"{HOME}/run/migrator.pid"
LOG_FILE = f"{HOME}/logs/migration.log"
FSTAB = f"{HOME}/config/virtual_fstab"
MOUNT = f"{HOME}/new_data/mnt"
EXPECTED_MAPPING = "/home/user/old_data /home/user/new_data/mnt"
EXPECTED_LOG = "MOUNTED /home/user/old_data TO /home/user/new_data/mnt"


def run(cmd, *, timeout=180, check=True, **kwargs):
    return subprocess.run(cmd, timeout=timeout, check=check, **kwargs)


def git_as_user(*args, timeout=180):
    return run(
        ["runuser", "-u", "user", "--", "git", "-c", "safe.directory=*", *args],
        timeout=timeout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def wait_for(predicate, timeout=30, interval=0.1):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except (OSError, ValueError) as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"condition was not met: {last_error}")
    raise AssertionError("condition was not met before timeout")


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def read_pid():
    with open(PID_FILE, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file {PID_FILE} does not contain a valid PID."
    return int(value)


def process_is_binary(pid, binary=BINARY):
    try:
        return os.path.samefile(f"/proc/{pid}/exe", binary)
    except (FileNotFoundError, PermissionError, OSError):
        return False


def stop_if_our_binary():
    if not os.path.isfile(PID_FILE) or not os.path.isfile(BINARY):
        return
    try:
        pid = read_pid()
    except (AssertionError, OSError):
        return
    if process_is_binary(pid):
        os.kill(pid, signal.SIGTERM)
        wait_for(lambda: not process_is_binary(pid), timeout=10)


def demote_to_user():
    entry = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(entry.pw_gid)
    os.setuid(entry.pw_uid)


def test_directories_exist():
    directories = [
        "/home/user/logs",
        "/home/user/config",
        "/home/user/bin",
        "/home/user/run",
        "/home/user/old_data",
        "/home/user/deploy_worktree",
    ]
    for directory in directories:
        assert os.path.isdir(directory), f"Required directory {directory} is missing or not a directory."


def test_initial_files_content():
    hello_path = "/home/user/old_data/hello.txt"
    assert os.path.isfile(hello_path), f"{hello_path} does not exist."
    with open(hello_path, "r") as f:
        assert f.read().strip() == "MIGRATION_READY", f"Content of {hello_path} is incorrect."

    assert os.path.isfile(FSTAB), f"{FSTAB} does not exist."
    with open(FSTAB, "r") as f:
        assert f.read().strip() == EXPECTED_MAPPING, f"Content of {FSTAB} is incorrect."


def test_git_repo_and_hook():
    result = run(
        ["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.stdout.strip() == "true", f"{REPO} is not a bare Git repository."

    hook_path = f"{REPO}/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert stat.S_ISREG(os.lstat(hook_path).st_mode), f"Git hook {hook_path} is not a regular file."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Git hook {hook_path} is not executable."

    run(["git", "--git-dir", REPO, "rev-parse", "--verify", "refs/heads/master"])
    tracked = run(
        ["git", "--git-dir", REPO, "ls-tree", "-r", "--name-only", "refs/heads/master"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.splitlines()
    assert "migrator/Cargo.toml" in tracked, "The pushed master branch does not contain migrator/Cargo.toml."
    assert "migrator/src/main.rs" in tracked, "The pushed master branch does not contain migrator/src/main.rs."


def test_service_management_script():
    script_path = "/home/user/bin/restart_service.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Script {script_path} is not a regular file."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_log_file_content():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    with open(LOG_FILE, "r") as f:
        content = f.read()
    assert EXPECTED_LOG in content, f"Log file {LOG_FILE} does not contain the expected string."


def test_symlink_and_mount_content():
    assert os.path.islink(MOUNT), f"{MOUNT} is not a symlink."
    target = os.readlink(MOUNT)
    assert target == "/home/user/old_data", f"Symlink points to {target} instead of /home/user/old_data."

    hello_mnt_path = os.path.join(MOUNT, "hello.txt")
    assert os.path.isfile(hello_mnt_path), f"{hello_mnt_path} cannot be accessed through the symlink."
    with open(hello_mnt_path, "r") as f:
        assert f.read().strip() == "MIGRATION_READY", "Content read through symlink is incorrect."


def test_daemon_is_running():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {PID_FILE} is not running.")


def test_end_to_end_pipeline_and_artifacts_are_functional():
    assert os.path.isdir(os.path.join(WORKSPACE, ".git")), f"{WORKSPACE} is not a Git workspace."
    workspace_head = git_as_user("-C", WORKSPACE, "rev-parse", "HEAD").stdout.strip()
    bare_head = run(
        ["git", "--git-dir", REPO, "rev-parse", "refs/heads/master"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    assert workspace_head == bare_head, "The workspace commit was not pushed to the bare repository before verification."

    stop_if_our_binary()

    # Put a known user-owned process in the PID file. A functional hook and restart
    # script must terminate it and replace it with the newly built migrator.
    sleeper = subprocess.Popen(
        ["sleep", "300"],
        preexec_fn=demote_to_user,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(PID_FILE, "w") as f:
        f.write(str(sleeper.pid) + "\n")
    os.chown(PID_FILE, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)

    # Force the push hook to perform a fresh checkout and build.
    remove_path(DEPLOY)
    os.makedirs(DEPLOY)
    user_entry = pwd.getpwnam("user")
    os.chown(DEPLOY, user_entry.pw_uid, user_entry.pw_gid)
    remove_path(MOUNT)
    if os.path.lexists(LOG_FILE):
        remove_path(LOG_FILE)

    token = uuid.uuid4().hex
    probe_rel = "migrator/verifier_pipeline_probe.txt"
    probe_path = os.path.join(WORKSPACE, probe_rel)
    with open(probe_path, "w") as f:
        f.write(token + "\n")
    os.chown(probe_path, user_entry.pw_uid, user_entry.pw_gid)

    git_as_user("-C", WORKSPACE, "config", "user.name", "Verifier")
    git_as_user("-C", WORKSPACE, "config", "user.email", "verifier@example.invalid")
    git_as_user("-C", WORKSPACE, "add", probe_rel)
    git_as_user("-C", WORKSPACE, "commit", "-m", f"verifier pipeline probe {token}")
    pushed_head = git_as_user("-C", WORKSPACE, "rev-parse", "HEAD").stdout.strip()
    git_as_user("-C", WORKSPACE, "push", REPO, "HEAD:master", timeout=240)

    actual_bare_head = run(
        ["git", "--git-dir", REPO, "rev-parse", "refs/heads/master"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    assert actual_bare_head == pushed_head, "The new workspace commit was not received on master."
    with open(os.path.join(DEPLOY, probe_rel), "r") as f:
        assert f.read().strip() == token, "The post-receive hook did not check out the pushed commit."

    assert os.path.isfile(BINARY), "The post-receive hook did not build the release migrator binary."
    assert os.access(BINARY, os.X_OK), "The built migrator binary is not executable."
    wait_for(lambda: os.path.islink(MOUNT) and os.path.isfile(LOG_FILE), timeout=30)
    wait_for(lambda: sleeper.poll() is not None, timeout=10)
    deployed_pid = read_pid()
    assert deployed_pid != sleeper.pid, "The restart script did not replace the old PID."
    assert process_is_binary(deployed_pid), "The PID file does not identify the built migrator executable."
    with open(LOG_FILE, "r") as f:
        assert EXPECTED_LOG in f.read(), "The daemon started by the push did not write the expected log entry."

    # Exercise the compiled daemon on verifier-derived paths, proving that it
    # parses the configuration instead of merely reproducing the fixed final state.
    os.kill(deployed_pid, signal.SIGTERM)
    wait_for(lambda: not process_is_binary(deployed_pid), timeout=10)

    probe_root = f"{HOME}/verifier_migration_{token}"
    source = os.path.join(probe_root, "source")
    destination = os.path.join(probe_root, "created_parent", "mnt")
    os.makedirs(source)
    probe_content = f"DATA_{token}"
    with open(os.path.join(source, "payload.txt"), "w") as f:
        f.write(probe_content)
    shutil.chown(probe_root, user="user", group="user")
    shutil.chown(source, user="user", group="user")
    shutil.chown(os.path.join(source, "payload.txt"), user="user", group="user")

    with open(FSTAB, "w") as f:
        f.write(f"{source} {destination}\n")
    os.chown(FSTAB, user_entry.pw_uid, user_entry.pw_gid)
    if os.path.lexists(LOG_FILE):
        remove_path(LOG_FILE)

    probe_daemon = subprocess.Popen(
        [BINARY],
        preexec_fn=demote_to_user,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    derived_log = f"MOUNTED {source} TO {destination}"
    wait_for(lambda: os.path.islink(destination) and os.path.isfile(LOG_FILE), timeout=20)
    assert os.readlink(destination) == source, "The daemon did not use the verifier-provided source path."
    with open(os.path.join(destination, "payload.txt"), "r") as f:
        assert f.read() == probe_content, "Data is not exposed through the daemon-created symlink."
    with open(LOG_FILE, "r") as f:
        assert derived_log in f.read(), "The daemon did not derive its log entry from the test configuration."
    time.sleep(1)
    assert probe_daemon.poll() is None, "The migrator did not remain running as a daemon."
    probe_daemon.terminate()
    probe_daemon.wait(timeout=10)

    # Restore the required configuration and actively exercise restart_service.sh.
    with open(FSTAB, "w") as f:
        f.write(EXPECTED_MAPPING + "\n")
    os.chown(FSTAB, user_entry.pw_uid, user_entry.pw_gid)
    remove_path(MOUNT)
    if os.path.lexists(LOG_FILE):
        remove_path(LOG_FILE)
    with open(PID_FILE, "w") as f:
        f.write(str(probe_daemon.pid) + "\n")
    os.chown(PID_FILE, user_entry.pw_uid, user_entry.pw_gid)

    run(
        ["runuser", "-u", "user", "--", "/home/user/bin/restart_service.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    wait_for(lambda: os.path.islink(MOUNT) and os.path.isfile(LOG_FILE), timeout=20)
    final_pid = read_pid()
    assert process_is_binary(final_pid), "restart_service.sh did not launch the compiled migrator binary."
    assert os.readlink(MOUNT) == "/home/user/old_data"
    with open(os.path.join(MOUNT, "hello.txt"), "r") as f:
        assert f.read().strip() == "MIGRATION_READY"
    with open(LOG_FILE, "r") as f:
        assert EXPECTED_LOG in f.read()
    time.sleep(1)
    assert process_is_binary(final_pid), "The restarted migrator did not remain running."

    shutil.rmtree(probe_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
