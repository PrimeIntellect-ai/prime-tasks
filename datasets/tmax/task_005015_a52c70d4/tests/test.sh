#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import collections
import os
import stat
import subprocess
import tempfile
import uuid


def test_hook_alerts_log():
    log_path = "/home/user/hook_alerts.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 1, f"Log file {log_path} is empty."
    assert "ALERT: File critical.txt was modified" in lines, f"Log file {log_path} does not contain the expected alert message."


def test_setup_hook_py_exists_and_idempotent():
    script_path = "/home/user/setup_hook.py"
    assert os.path.isfile(script_path), f"Setup script {script_path} is missing."

    hook_path = "/home/user/alerts_repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook file {hook_path} is missing."

    # Read original hook content
    with open(hook_path, "r") as f:
        original_hook_content = f.read()

    # Run the setup script again to check idempotency
    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {script_path} failed on repeated execution."

    # Check if hook content remains valid/uncorrupted
    with open(hook_path, "r") as f:
        new_hook_content = f.read()

    # It shouldn't just infinitely append the same script
    assert len(new_hook_content) < len(original_hook_content) * 2, "Setup script does not appear to be idempotent (it might be appending to the hook file indefinitely)."


def test_post_receive_hook_executable():
    hook_path = "/home/user/alerts_repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook file {hook_path} is missing."

    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook file {hook_path} is not executable."


def test_trigger_exp_exists():
    exp_path = "/home/user/trigger.exp"
    assert os.path.isfile(exp_path), f"Expect script {exp_path} is missing."


def test_workspace_state():
    workspace_file = "/home/user/workspace/critical.txt"
    assert os.path.isfile(workspace_file), f"File {workspace_file} was not created in the workspace."

    with open(workspace_file, "r") as f:
        content = f.read().strip()

    assert content == "HIGH: Database connection lost", f"Content of {workspace_file} is incorrect."

    # Check if it was pushed to the bare repo
    bare_repo = "/home/user/alerts_repo.git"
    result = subprocess.run(["git", "-C", bare_repo, "ls-tree", "-r", "master", "--name-only"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to inspect bare repository."
    assert "critical.txt" in result.stdout.splitlines(), "critical.txt was not pushed to the bare repository."


def test_trigger_exp_interacts_with_make_alert():
    exp_path = "/home/user/trigger.exp"
    make_alert_path = "/home/user/workspace/make_alert.sh"
    marker = f"/tmp/trigger-success-{uuid.uuid4().hex}"

    with open(make_alert_path, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(make_alert_path).st_mode)

    probe = f'''#!/bin/bash
read -r -p "Enter alert filename: " filename
read -r -p "Enter severity: " severity
read -r -p "Enter message: " message
if [ "$filename" = "critical.txt" ] && [ "$severity" = "HIGH" ] && [ "$message" = "Database connection lost" ]; then
    : > "{marker}"
    exit 0
fi
exit 42
'''

    try:
        with open(make_alert_path, "w") as f:
            f.write(probe)
        os.chmod(make_alert_path, 0o755)
        try:
            result = subprocess.run(
                ["expect", exp_path], capture_output=True, text=True, timeout=15
            )
        except subprocess.TimeoutExpired as exc:
            raise AssertionError("The Expect script timed out while answering the prompts.") from exc

        assert result.returncode == 0, (
            f"Running {exp_path} failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(marker), (
            "The Expect script did not spawn make_alert.sh and answer all three prompts correctly."
        )
    finally:
        with open(make_alert_path, "wb") as f:
            f.write(original)
        os.chmod(make_alert_path, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)


def test_post_receive_hook_on_fresh_multi_commit_push():
    bare_repo = "/home/user/alerts_repo.git"
    log_path = "/home/user/hook_alerts.log"
    token = uuid.uuid4().hex
    first_txt = f"fresh_first_{token}.txt"
    second_txt = f"fresh_second_{token}.txt"
    non_txt = f"fresh_other_{token}.cfg"

    # The original-state assertion above has already checked the required alert.
    # Start with a clean log so this push's output can be checked exactly.
    with open(log_path, "w"):
        pass

    with tempfile.TemporaryDirectory(prefix="hook-verifier-") as tmp:
        clone = os.path.join(tmp, "clone")

        result = subprocess.run(
            ["git", "clone", bare_repo, clone], capture_output=True, text=True
        )
        assert result.returncode == 0, f"Failed to clone test repository: {result.stderr}"

        subprocess.run(["git", "-C", clone, "config", "user.name", "Verifier"], check=True)
        subprocess.run(["git", "-C", clone, "config", "user.email", "verifier@example.com"], check=True)

        with open(os.path.join(clone, first_txt), "w") as f:
            f.write("first revision\n")
        subprocess.run(["git", "-C", clone, "add", first_txt], check=True)
        subprocess.run(
            ["git", "-C", clone, "commit", "-m", f"Add {first_txt}"],
            check=True,
            capture_output=True,
            text=True,
        )

        # Remove the first file in the next commit. A hook that only compares the
        # old and new tips will miss that it was added in an intermediate commit.
        os.unlink(os.path.join(clone, first_txt))
        with open(os.path.join(clone, second_txt), "w") as f:
            f.write("second revision\n")
        with open(os.path.join(clone, non_txt), "w") as f:
            f.write("not an alert file\n")
        subprocess.run(["git", "-C", clone, "add", "-A"], check=True)
        subprocess.run(
            ["git", "-C", clone, "commit", "-m", f"Replace with {second_txt}"],
            check=True,
            capture_output=True,
            text=True,
        )

        result = subprocess.run(
            ["git", "-C", clone, "push", "origin", "master"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Fresh push failed: {result.stderr}"

    with open(log_path, "r") as f:
        actual = [line.rstrip("\n") for line in f if line.rstrip("\n")]

    expected = [
        f"ALERT: File {first_txt} was modified",
        f"ALERT: File {second_txt} was modified",
    ]
    assert collections.Counter(actual) == collections.Counter(expected), (
        f"The hook did not derive the exact alerts from every commit in the fresh push. "
        f"Expected {expected!r}, got {actual!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
