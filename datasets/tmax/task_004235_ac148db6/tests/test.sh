#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import time
import uuid


def test_fix_hook_script_exists():
    script_path = "/home/user/fix_hook.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_hook_creation_and_execution():
    script_path = "/home/user/fix_hook.sh"

    # 1. Run the agent's script.
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Executing {script_path} failed with output: {result.stderr}"

    # 2. Check if hook exists and is executable.
    hook_path = "/home/user/account_repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"The hook file {hook_path} was not created."
    assert os.access(hook_path, os.X_OK), f"The hook file {hook_path} is not executable."

    with open(hook_path, "r", errors="replace") as f:
        hook_text = f.read()
    assert re.search(r"\bexport\s+LOG_DIR=(?:/home/user/logs|'\/home\/user\/logs'|\"/home/user/logs\")(?:\s|;|$)", hook_text), \
        "The hook must export LOG_DIR=/home/user/logs."
    assert re.search(r"/usr/bin/python3\s+/home/user/scripts/sync_accounts\.py", hook_text), \
        "The hook must execute the synchronization script with /usr/bin/python3."

    sync_script = "/home/user/scripts/sync_accounts.py"
    with open(sync_script, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(sync_script).st_mode)

    nonce = uuid.uuid4().hex
    probe = f'''import os
import sys
import time

time.sleep(3)
nonce = {nonce!r}
log_dir = os.environ.get("LOG_DIR")
if log_dir != "/home/user/logs":
    print("Incorrect LOG_DIR: " + repr(log_dir), file=sys.stderr)
    sys.exit(23)
with open(os.path.join(log_dir, "sync.log"), "a") as f:
    f.write("Sync triggered\\n")
    f.write("SYNC_NONCE=" + nonce + "\\n")
print("Sync completed successfully.")
print("STDOUT_NONCE=" + nonce)
print("STDERR_NONCE=" + nonce, file=sys.stderr)
'''

    sync_log = "/home/user/logs/sync.log"
    hook_output_log = "/home/user/logs/hook_output.log"
    wrong_log = "/home/user/account_repo.git/sync.log"

    try:
        # Install a randomized probe only after fix_hook.sh has returned. This makes
        # pre-created log contents insufficient and verifies that the hook launches
        # the required script with the required environment and redirections.
        with open(sync_script, "w") as f:
            f.write(probe)
        os.chmod(sync_script, original_mode)

        # Remove any output planted by fix_hook.sh before triggering the hook.
        for path in (sync_log, hook_output_log, wrong_log):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        # 3. Trigger a push from a fresh repository.
        with tempfile.TemporaryDirectory(prefix="dummy_repo_") as dummy_repo:
            subprocess.run(["git", "init"], cwd=dummy_repo, check=True, capture_output=True)
            subprocess.run(["git", "remote", "add", "origin", "/home/user/account_repo.git"], cwd=dummy_repo, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=dummy_repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=dummy_repo, check=True)

            test_file = os.path.join(dummy_repo, "testfile")
            with open(test_file, "w") as f:
                f.write(nonce)
            subprocess.run(["git", "add", "testfile"], cwd=dummy_repo, check=True)
            subprocess.run(["git", "commit", "-m", "verification"], cwd=dummy_repo, check=True, capture_output=True)

            branch = "verify-" + nonce
            started = time.monotonic()
            push_result = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
                cwd=dummy_repo, capture_output=True, text=True
            )
            elapsed = time.monotonic() - started
            assert push_result.returncode == 0, f"Git push failed: {push_result.stderr}"
            assert elapsed < 2.5, "Git push waited for the synchronization script; it was not launched in the background."

        # 4. Wait for the background probe to finish.
        deadline = time.monotonic() + 8
        sync_content = ""
        hook_content = ""
        while time.monotonic() < deadline:
            if os.path.isfile(sync_log):
                with open(sync_log, "r") as f:
                    sync_content = f.read()
            if os.path.isfile(hook_output_log):
                with open(hook_output_log, "r") as f:
                    hook_content = f.read()
            if (f"SYNC_NONCE={nonce}" in sync_content and
                    f"STDOUT_NONCE={nonce}" in hook_content and
                    f"STDERR_NONCE={nonce}" in hook_content):
                break
            time.sleep(0.1)

        # 5. Preserve the original log assertions and require fresh probe evidence.
        assert os.path.isfile(sync_log), f"{sync_log} was not created. The hook might not be exporting LOG_DIR correctly."
        assert "Sync triggered" in sync_content, f"Expected 'Sync triggered' in {sync_log}, but got: {sync_content}"
        assert f"SYNC_NONCE={nonce}" in sync_content, "sync.log was not produced by the hook-triggered synchronization process."

        assert os.path.isfile(hook_output_log), f"{hook_output_log} was not created. Output redirection might be missing."
        assert "Sync completed successfully." in hook_content, f"Expected 'Sync completed successfully.' in {hook_output_log}, but got: {hook_content}"
        assert f"STDOUT_NONCE={nonce}" in hook_content, "Standard output was not redirected to hook_output.log."
        assert f"STDERR_NONCE={nonce}" in hook_content, "Standard error was not redirected to hook_output.log."
        assert not os.path.exists(wrong_log), "The synchronization log was written inside the bare repository."
    finally:
        with open(sync_script, "wb") as f:
            f.write(original_script)
        os.chmod(sync_script, original_mode)


def test_idempotency():
    script_path = "/home/user/fix_hook.sh"
    hook_path = "/home/user/account_repo.git/hooks/post-receive"

    first = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert first.returncode == 0, f"Executing {script_path} failed: {first.stderr}"
    assert os.path.isfile(hook_path), f"The hook file {hook_path} was removed or not created."
    assert os.access(hook_path, os.X_OK), f"The hook file {hook_path} is not executable."
    with open(hook_path, "rb") as f:
        before = f.read()
    before_mode = stat.S_IMODE(os.stat(hook_path).st_mode)

    # Run the script a second time.
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Executing {script_path} a second time failed (not idempotent). Output: {result.stderr}"
    assert os.path.isfile(hook_path), f"The hook file {hook_path} was removed or not created on second run."
    assert os.access(hook_path, os.X_OK), f"The hook file {hook_path} lost executable permissions on second run."
    with open(hook_path, "rb") as f:
        after = f.read()
    after_mode = stat.S_IMODE(os.stat(hook_path).st_mode)
    assert after == before and after_mode == before_mode, "Repeated execution did not leave the hook in the exact same state."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
