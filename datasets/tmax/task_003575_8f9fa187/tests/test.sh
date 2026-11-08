#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import uuid
import pytest

SRC = "/home/user/app-src"
DEPLOY = "/home/user/deploy.git"
HOOK = "/home/user/deploy.git/hooks/post-receive"
APP_SCRIPT = "/home/user/app/start-service.sh"
LOG = "/home/user/app.log"


@pytest.fixture(scope="session", autouse=True)
def perform_fresh_push():
    """Create and push a fresh commit whose service records its actual environment."""
    subprocess.run(
        ["git", "checkout", "-f", "master"],
        cwd=SRC,
        capture_output=True,
        text=True,
        check=True,
    )

    nonce = uuid.uuid4().hex
    proof_path = f"/tmp/deploy-env-proof-{nonce}"
    script = f'''#!/bin/bash
if [ "${{TZ:-}}" != "UTC" ]; then
    echo "FATAL: Service requires UTC timezone to start. Currently: ${{TZ:-UNSET}}" >&2
    exit 1
fi
if [ "${{LC_ALL:-}}" != "C.UTF-8" ]; then
    echo "FATAL: Service requires LC_ALL=C.UTF-8 to start." >&2
    exit 1
fi
printf '%s\\n' "${{TZ}}|${{LC_ALL}}|{nonce}" > {proof_path}
echo "READY" > /home/user/app.log
'''

    with open(os.path.join(SRC, "start-service.sh"), "w") as f:
        f.write(script)
    os.chmod(os.path.join(SRC, "start-service.sh"), 0o755)

    for path in (LOG, proof_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(["git", "add", "start-service.sh"], cwd=SRC, check=True)
    commit = subprocess.run(
        [
            "git", "-c", "user.name=Verifier", "-c",
            "user.email=verifier@local", "commit", "--no-verify",
            "-m", f"Verifier deployment {nonce}",
        ],
        cwd=SRC,
        capture_output=True,
        text=True,
    )
    assert commit.returncode == 0, f"Failed to create a fresh deployment commit: {commit.stderr}"

    # Do not let the verifier's own environment satisfy the service requirements.
    push_env = os.environ.copy()
    push_env.pop("TZ", None)
    push_env.pop("LC_ALL", None)
    push = subprocess.run(
        ["git", "push", "deploy", "master"],
        cwd=SRC,
        env=push_env,
        capture_output=True,
        text=True,
    )
    assert push.returncode == 0, (
        "A fresh `git push deploy master` failed.\n"
        f"stdout:\n{push.stdout}\nstderr:\n{push.stderr}"
    )

    assert os.path.isfile(proof_path), "The service was not executed by the fresh push."
    with open(proof_path, "r") as f:
        proof = f.read().strip()
    assert proof == f"UTC|C.UTF-8|{nonce}", (
        "The service did not receive TZ=UTC and LC_ALL=C.UTF-8 from the deployment hook."
    )

    expected = subprocess.run(
        ["git", "show", "master:start-service.sh"],
        cwd=SRC,
        capture_output=True,
        check=True,
    ).stdout
    with open(APP_SCRIPT, "rb") as f:
        deployed = f.read()
    assert deployed == expected, "The fresh commit was not checked out to /home/user/app."


def test_app_log_ready():
    log_path = "/home/user/app.log"
    assert os.path.isfile(log_path), (
        f"Log file {log_path} does not exist. The service did not start successfully or the push failed."
    )
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "READY", (
        f"Expected 'READY' in {log_path}, but found '{content}'. "
        "The environment variables might not be set correctly."
    )


def test_git_push_successful():
    src_result = subprocess.run(
        ["git", "rev-parse", "master"], cwd=SRC, capture_output=True, text=True
    )
    assert src_result.returncode == 0, "Failed to get commit hash from /home/user/app-src master branch."
    src_commit = src_result.stdout.strip()

    deploy_result = subprocess.run(
        ["git", "rev-parse", "master"], cwd=DEPLOY, capture_output=True, text=True
    )
    assert deploy_result.returncode == 0, (
        "The /home/user/deploy.git repository does not have a master branch. The push likely failed."
    )
    deploy_commit = deploy_result.stdout.strip()
    assert src_commit == deploy_commit, (
        f"The commit in deploy.git ({deploy_commit}) does not match app-src ({src_commit}). "
        "The push was not successful."
    )


def test_hook_robustness():
    assert os.path.isfile(HOOK), f"Hook file {HOOK} is missing."
    assert os.access(HOOK, os.X_OK), f"Hook file {HOOK} is not executable."
    with open(HOOK, "r") as f:
        content = f.read()

    # Preserve the original robustness assertion.
    is_robust = "set -e" in content or "|| exit" in content or "set -u" in content
    assert is_robust, (
        "The post-receive hook does not appear to handle errors gracefully "
        "(e.g., missing 'set -e')."
    )


def test_z_hook_stops_after_checkout_error():
    """A checkout failure must stop the hook rather than starting stale code."""
    marker = f"/tmp/hook-continued-{uuid.uuid4().hex}"
    with open(APP_SCRIPT, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(APP_SCRIPT).st_mode)

    try:
        with open(APP_SCRIPT, "w") as f:
            f.write(f"#!/bin/bash\necho continued > {marker}\n")
        os.chmod(APP_SCRIPT, 0o755)

        invalid_old = "0" * 40
        invalid_new = "f" * 40
        result = subprocess.run(
            [HOOK],
            input=f"{invalid_old} {invalid_new} refs/heads/master\n",
            cwd=DEPLOY,
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0, "The hook reported success after its checkout command failed."
        assert not os.path.exists(marker), (
            "The hook continued to the service command after a checkout failure; "
            "error handling is not active."
        )
    finally:
        with open(APP_SCRIPT, "wb") as f:
            f.write(original)
        os.chmod(APP_SCRIPT, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
