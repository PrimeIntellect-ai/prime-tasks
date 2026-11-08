#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import uuid


def test_fstab_simulation():
    fstab_path = "/home/user/my_fstab"
    assert os.path.exists(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read()

    pattern = r"^/home/user/remote_share\s+/home/user/mnt/backup\s+nfs\s+defaults,ro"
    match = re.search(pattern, content, re.MULTILINE)
    assert match is not None, f"The fstab file does not contain the correct mount configuration. Found: {content}"


def test_directories_exist():
    remote_share = "/home/user/remote_share"
    mnt_backup = "/home/user/mnt/backup"

    assert os.path.isdir(remote_share), f"Directory {remote_share} does not exist."
    assert os.path.isdir(mnt_backup), f"Directory {mnt_backup} does not exist."


def test_git_bare_repo():
    repo_path = "/home/user/monitor.git"
    assert os.path.isdir(repo_path), f"Directory {repo_path} does not exist."

    result = subprocess.run(
        ["git", "-C", repo_path, "rev-parse", "--is-bare-repository"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Git command failed on the bare repository."
    assert result.stdout.strip() == "true", f"The repository at {repo_path} is not a bare repository."


def test_git_post_receive_hook():
    hook_path = "/home/user/monitor.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"The post-receive hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"The post-receive hook {hook_path} is not executable."


def test_alerts_log_generated():
    log_path = "/home/user/alerts.log"
    assert os.path.exists(log_path), f"The alerts log {log_path} does not exist. Did the git push trigger the hook?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "ALERT: Network configuration changed" in content, "The alerts log does not contain the expected alert message."


def test_monitor_local_and_status():
    local_repo = "/home/user/monitor_local"
    status_file = os.path.join(local_repo, "status.txt")

    assert os.path.isdir(local_repo), f"The local repository {local_repo} does not exist."
    assert os.path.exists(status_file), f"The status file {status_file} does not exist."

    with open(status_file, "r") as f:
        content = f.read()

    expected_status = "Network check passed for /home/user/my_fstab"
    assert expected_status in content, f"The status file does not contain the expected output. Found: {content}"


def test_git_push_occurred():
    repo_path = "/home/user/monitor.git"
    result = subprocess.run(
        ["git", "-C", repo_path, "ls-tree", "-r", "HEAD", "--name-only"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to inspect the bare repository HEAD."
    assert "status.txt" in result.stdout.splitlines(), "status.txt was not pushed to the bare repository."


def _automation_command(path):
    with open(path, "r", errors="replace") as f:
        content = f.read()
    first = content.splitlines()[0] if content.splitlines() else ""
    if first.startswith("#!"):
        return shlex.split(first[2:].strip()) + [path]
    if "pexpect" in content or re.search(r"^\s*(from|import)\s+", content, re.MULTILINE):
        return ["python3", path]
    return ["expect", path]


def _run(cmd, **kwargs):
    env = os.environ.copy()
    env.update({
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "safe.directory",
        "GIT_CONFIG_VALUE_0": "*",
    })
    return subprocess.run(cmd, env=env, **kwargs)


def test_fresh_automation_and_functional_hook():
    automation = "/home/user/run_check.exp"
    tool = "/home/user/tools/check_net.sh"
    local_repo = "/home/user/monitor_local"
    bare_repo = "/home/user/monitor.git"
    status_file = os.path.join(local_repo, "status.txt")
    alert_log = "/home/user/alerts.log"
    expected_alert = "ALERT: Network configuration changed"

    assert os.path.isfile(automation), f"Automation script {automation} does not exist or is not a regular file."
    assert os.path.isfile(tool), f"Interactive diagnostic tool {tool} is missing."

    nonce = uuid.uuid4().hex
    marker = f"/tmp/check_net_invocation_{nonce}"
    dynamic_output = f"Network check passed for /home/user/my_fstab :: verification-{nonce}"

    with open(tool, "rb") as f:
        original_tool = f.read()
    original_mode = stat.S_IMODE(os.stat(tool).st_mode)

    challenge = f'''#!/bin/bash
printf "Enter username: "
IFS= read -r user
printf "Enter pin: "
IFS= read -r pin
printf "Enter target file: "
IFS= read -r target
printf 'user=%s\\npin=%s\\ntarget=%s\\n' "$user" "$pin" "$target" > {shlex.quote(marker)}
if [ "$user" != "admin" ]; then
    echo "Access denied."
    exit 1
fi
if [ "$pin" != "8492" ]; then
    echo "Invalid pin."
    exit 1
fi
if [ "$target" != "/home/user/my_fstab" ] || [ ! -f "$target" ]; then
    echo "File not found: $target"
    exit 1
fi
echo {shlex.quote(dynamic_output)}
'''

    try:
        with open(tool, "w") as f:
            f.write(challenge)
        os.chmod(tool, 0o755)

        before = _run(
            ["git", "-C", bare_repo, "rev-parse", "refs/heads/master"],
            capture_output=True, text=True
        )
        assert before.returncode == 0, "The bare repository has no master branch to update."
        before_head = before.stdout.strip()

        with open(alert_log, "w") as f:
            f.write("AUTOMATION_SENTINEL\n")

        result = _run(
            _automation_command(automation),
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, (
            "The automation script failed when executed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.exists(marker), "The automation did not execute the interactive diagnostic tool."
        with open(marker, "r") as f:
            invocation = f.read().splitlines()
        assert invocation == [
            "user=admin",
            "pin=8492",
            "target=/home/user/my_fstab",
        ], f"The diagnostic tool received incorrect interactive answers: {invocation}"

        assert os.path.isfile(status_file), "The automation did not create status.txt."
        with open(status_file, "r") as f:
            local_status = f.read().strip()
        assert local_status == dynamic_output, (
            "status.txt was not populated with the fresh successful output from the diagnostic tool. "
            f"Found: {local_status!r}"
        )

        after = _run(
            ["git", "-C", bare_repo, "rev-parse", "refs/heads/master"],
            capture_output=True, text=True
        )
        assert after.returncode == 0, "Failed to inspect master after running the automation."
        after_head = after.stdout.strip()
        assert after_head != before_head, "Running the automation did not produce a fresh push to master."

        committed_status = _run(
            ["git", "-C", bare_repo, "show", "refs/heads/master:status.txt"],
            capture_output=True, text=True
        )
        assert committed_status.returncode == 0, "The fresh push did not contain status.txt."
        assert committed_status.stdout.strip() == dynamic_output, "The pushed status.txt did not contain the fresh diagnostic output."

        message = _run(
            ["git", "-C", bare_repo, "log", "-1", "--format=%s", "refs/heads/master"],
            capture_output=True, text=True
        )
        assert message.returncode == 0 and message.stdout.strip() == "Update status", "The automation did not use the required commit message."

        with open(alert_log, "r") as f:
            automation_alerts = f.read().splitlines()
        assert "AUTOMATION_SENTINEL" in automation_alerts, "The alert action overwrote the log instead of appending to it."
        assert expected_alert in automation_alerts, "The automation's fresh push did not generate the required alert."

        # Independently push another commit, proving the installed post-receive
        # hook itself is functional rather than relying on a pre-created log.
        with tempfile.TemporaryDirectory(prefix="hook-probe-") as probe:
            clone = _run(
                ["git", "clone", bare_repo, probe],
                capture_output=True, text=True
            )
            assert clone.returncode == 0, f"Could not clone repository for hook test: {clone.stderr}"
            _run(["git", "-C", probe, "config", "user.name", "Verifier"], check=True)
            _run(["git", "-C", probe, "config", "user.email", "verifier@example.invalid"], check=True)
            probe_name = f"hook_probe_{nonce}.txt"
            with open(os.path.join(probe, probe_name), "w") as f:
                f.write(nonce + "\n")
            _run(["git", "-C", probe, "add", probe_name], check=True)
            commit = _run(
                ["git", "-C", probe, "commit", "-m", f"Hook probe {nonce}"],
                capture_output=True, text=True
            )
            assert commit.returncode == 0, f"Could not create hook probe commit: {commit.stderr}"

            with open(alert_log, "w") as f:
                f.write("HOOK_SENTINEL\n")
            push = _run(
                ["git", "-C", probe, "push", "origin", "HEAD:master"],
                capture_output=True, text=True
            )
            assert push.returncode == 0, f"Fresh hook probe push failed: {push.stderr}"

        with open(alert_log, "r") as f:
            hook_alerts = f.read().splitlines()
        assert "HOOK_SENTINEL" in hook_alerts, "The post-receive hook overwrote alerts.log instead of appending."
        assert expected_alert in hook_alerts, "A fresh independent push did not trigger the required post-receive alert."
    finally:
        with open(tool, "wb") as f:
            f.write(original_tool)
        os.chmod(tool, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
