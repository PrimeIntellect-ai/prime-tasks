#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import time

REPO_PATH = "/home/user/iot-hub.git"
ACTIVE_PATH = "/home/user/iot-active"
LOG_PATH = "/home/user/daemon-status.log"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, **kwargs)


def daemon_pids():
    result = run(["pgrep", "-f", "edge-daemon"], capture_output=True)
    if result.returncode != 0:
        return []
    return [pid for pid in result.stdout.strip().split() if pid]


def daemon_tz(pid):
    path = f"/proc/{pid}/environ"
    if not os.path.exists(path):
        return None
    try:
        with open(path, "rb") as f:
            entries = f.read().split(b"\0")
    except (FileNotFoundError, ProcessLookupError):
        return None
    values = [e[3:].decode("utf-8") for e in entries if e.startswith(b"TZ=")]
    return values[0] if len(values) == 1 else None


def assert_deployed(expected_files, expected_tz, previous_pid=None):
    deadline = time.time() + 10
    while time.time() < deadline:
        pids = daemon_pids()
        log_content = ""
        try:
            with open(LOG_PATH, "r") as f:
                log_content = f.read()
        except FileNotFoundError:
            pass
        if len(pids) == 1 and daemon_tz(pids[0]) == expected_tz and expected_tz in log_content:
            break
        time.sleep(0.25)

    for relative_path, expected_content in expected_files.items():
        active_file = os.path.join(ACTIVE_PATH, relative_path)
        assert os.path.isfile(active_file), f"Checked out file {active_file} is missing."
        with open(active_file, "r") as f:
            actual = f.read()
        assert actual == expected_content, f"Content of {active_file} is incorrect."

    active_tz_file = os.path.join(ACTIVE_PATH, "TIMEZONE")
    assert os.path.isfile(active_tz_file), f"Checked out file {active_tz_file} is missing."
    with open(active_tz_file, "r") as f:
        assert f.read().strip() == expected_tz, f"Content of {active_tz_file} is incorrect."

    try:
        pgrep_out = subprocess.check_output(["pgrep", "-f", "edge-daemon"], text=True)
    except subprocess.CalledProcessError:
        pgrep_out = ""
    pids = [pid for pid in pgrep_out.strip().split() if pid]
    assert len(pids) == 1, f"Expected exactly 1 edge-daemon process running, found {len(pids)}."
    pid = pids[0]

    if previous_pid is not None:
        assert pid != previous_pid, "The prior edge-daemon was not replaced after the push."
        assert not os.path.exists(f"/proc/{previous_pid}"), "The prior edge-daemon process is still running."

    environ_path = f"/proc/{pid}/environ"
    assert os.path.exists(environ_path), f"Process environment file {environ_path} does not exist."
    with open(environ_path, "rb") as f:
        env_data = f.read().split(b"\0")
    tz_env = [e.decode("utf-8") for e in env_data if e.startswith(b"TZ=")]
    assert len(tz_env) == 1, "TZ environment variable not found in the new edge-daemon process."
    assert tz_env[0] == f"TZ={expected_tz}", f"Incorrect TZ env var in daemon process: {tz_env[0]}"

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", errors="replace")
    assert "/home/user/bin/edge-daemon" in cmdline, "Running process is not /home/user/bin/edge-daemon."

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()
    assert expected_tz in log_content, f"Log file {LOG_PATH} does not contain expected timezone {expected_tz}."
    return pid


def test_git_repo_and_hook():
    assert os.path.isdir(REPO_PATH), f"Bare repo directory {REPO_PATH} is missing."
    out = run(["git", "-C", REPO_PATH, "rev-parse", "--is-bare-repository"], capture_output=True)
    assert out.stdout.strip() == "true", f"{REPO_PATH} is not a bare Git repository."

    hook_path = os.path.join(REPO_PATH, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"Hook file {hook_path} is missing."
    assert os.access(hook_path, os.X_OK), f"Hook file {hook_path} is not executable."


def test_repeated_pushes_and_daemon_behavior():
    token = secrets.token_hex(8).upper()
    timezones = [
        f"<AUD{token}A>+01",
        f"<AUD{token}B>-02",
        f"<AUD{token}C>+03",
    ]
    assert len(set(timezones)) == 3

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_path = os.path.join(tmpdir, "test-clone")
        res = run(["git", "clone", REPO_PATH, clone_path], capture_output=True)
        assert res.returncode == 0, f"Failed to clone repository: {res.stderr}"

        run(["git", "-C", clone_path, "config", "user.email", "test@example.com"], check=True)
        run(["git", "-C", clone_path, "config", "user.name", "Test User"], check=True)
        run(["git", "-C", clone_path, "checkout", "--orphan", "verifier-root"], check=True, capture_output=True)
        run(["git", "-C", clone_path, "rm", "-rf", "--ignore-unmatch", "."], check=True, capture_output=True)
        run(["git", "-C", clone_path, "clean", "-fdx"], check=True, capture_output=True)

        initial_payload = f"master-initial-{secrets.token_hex(16)}"
        with open(os.path.join(clone_path, "TIMEZONE"), "w") as f:
            f.write(timezones[0])
        with open(os.path.join(clone_path, "payload.txt"), "w") as f:
            f.write(initial_payload)
        run(["git", "-C", clone_path, "add", "TIMEZONE", "payload.txt"], check=True)
        run(["git", "-C", clone_path, "commit", "-m", "Initial verifier configuration"], check=True, capture_output=True)
        res = run(["git", "-C", clone_path, "push", "--force", "origin", "HEAD:refs/heads/master"], capture_output=True)
        assert res.returncode == 0, f"Git push failed. Ensure the hook doesn't crash. Error: {res.stderr}"
        pid = assert_deployed(
            {"TIMEZONE": timezones[0], "payload.txt": initial_payload},
            timezones[0],
        )

        updated_payload = f"master-update-{secrets.token_hex(16)}"
        with open(os.path.join(clone_path, "TIMEZONE"), "w") as f:
            f.write(timezones[1])
        with open(os.path.join(clone_path, "payload.txt"), "w") as f:
            f.write(updated_payload)
        run(["git", "-C", clone_path, "add", "TIMEZONE", "payload.txt"], check=True)
        run(["git", "-C", clone_path, "commit", "-m", "Update master configuration"], check=True, capture_output=True)
        res = run(["git", "-C", clone_path, "push", "origin", "HEAD:refs/heads/master"], capture_output=True)
        assert res.returncode == 0, f"Second Git push failed: {res.stderr}"
        pid = assert_deployed(
            {"TIMEZONE": timezones[1], "payload.txt": updated_payload},
            timezones[1],
            pid,
        )

        branch_name = f"audit-{secrets.token_hex(6)}"
        branch_payload = f"branch-update-{secrets.token_hex(16)}"
        branch_marker = f"branch-marker-{secrets.token_hex(16)}"
        with open(os.path.join(clone_path, "TIMEZONE"), "w") as f:
            f.write(timezones[2])
        with open(os.path.join(clone_path, "payload.txt"), "w") as f:
            f.write(branch_payload)
        with open(os.path.join(clone_path, "branch-marker.txt"), "w") as f:
            f.write(branch_marker)
        run(["git", "-C", clone_path, "add", "TIMEZONE", "payload.txt", "branch-marker.txt"], check=True)
        run(["git", "-C", clone_path, "commit", "-m", "Add branch configuration"], check=True, capture_output=True)
        res = run(["git", "-C", clone_path, "push", "origin", f"HEAD:refs/heads/{branch_name}"], capture_output=True)
        assert res.returncode == 0, f"Branch Git push failed: {res.stderr}"
        assert_deployed(
            {
                "TIMEZONE": timezones[2],
                "payload.txt": branch_payload,
                "branch-marker.txt": branch_marker,
            },
            timezones[2],
            pid,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
