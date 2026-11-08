#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

REPO_PATH = "/home/user/operator-repo"
HOOK_PATH = os.path.join(REPO_PATH, ".git/hooks/post-commit")
MANIFEST_PATH = os.path.join(REPO_PATH, "manifest.yaml")
LOG_PATH = "/home/user/operator.log"
ALERT_PATH = "/home/user/alerts.mail"


def read_lines(path):
    with open(path, "r") as f:
        return f.read().splitlines()


def commit_replicas(value):
    manifest = (
        "apiVersion: apps/v1\n"
        "kind: Deployment\n"
        "metadata:\n"
        "  name: test-app\n"
        "spec:\n"
        f"  replicas: {value}\n"
    )
    with open(MANIFEST_PATH, "w") as f:
        f.write(manifest)

    git = ["git", "-c", f"safe.directory={REPO_PATH}"]
    subprocess.run(git + ["add", "manifest.yaml"], cwd=REPO_PATH, check=True)
    subprocess.run(
        git + ["commit", "--allow-empty", "-m", f"Update replicas to {value}"],
        cwd=REPO_PATH,
        check=True,
    )


def test_hook_exists_and_executable():
    assert os.path.isfile(HOOK_PATH), f"Git hook file does not exist at {HOOK_PATH}"
    st = os.stat(HOOK_PATH)
    assert st.st_mode & stat.S_IXUSR, f"Git hook file at {HOOK_PATH} is not executable"
    with open(HOOK_PATH, "rb") as f:
        assert f.readline().rstrip(b"\r\n") == b"#!/usr/bin/env python3"


def test_hook_behavior():
    for path in (LOG_PATH, ALERT_PATH):
        if os.path.exists(path):
            os.remove(path)

    # Original normal-replica check.
    commit_replicas(3)
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created after commit."
    log_content = "\n".join(read_lines(LOG_PATH))
    assert "DEPLOY: replicas=3" in log_content, f"Expected 'DEPLOY: replicas=3' in {LOG_PATH}"
    assert read_lines(LOG_PATH) == ["DEPLOY: replicas=3"]
    if os.path.exists(ALERT_PATH):
        alert_content = "\n".join(read_lines(ALERT_PATH))
        assert "ALERT: High replica count detected (3)" not in alert_content, "Alert should NOT be generated for replicas=3"
        assert read_lines(ALERT_PATH) == []

    # Original high-replica check.
    commit_replicas(8)
    log_content = "\n".join(read_lines(LOG_PATH))
    assert "DEPLOY: replicas=8" in log_content, f"Expected 'DEPLOY: replicas=8' in {LOG_PATH}"
    assert read_lines(LOG_PATH) == ["DEPLOY: replicas=3", "DEPLOY: replicas=8"]
    assert os.path.isfile(ALERT_PATH), f"Alert file {ALERT_PATH} was not created after high-replica commit."
    alert_content = "\n".join(read_lines(ALERT_PATH))
    assert "ALERT: High replica count detected (8)" in alert_content, f"Expected 'ALERT: High replica count detected (8)' in {ALERT_PATH}"
    assert read_lines(ALERT_PATH) == ["ALERT: High replica count detected (8)"]

    # Exercise the strict threshold boundary; this must not add an alert.
    commit_replicas(5)
    assert read_lines(LOG_PATH) == [
        "DEPLOY: replicas=3",
        "DEPLOY: replicas=8",
        "DEPLOY: replicas=5",
    ]
    assert read_lines(ALERT_PATH) == ["ALERT: High replica count detected (8)"]

    # Use an unpredictable value so fixed output cannot satisfy the verifier.
    random_high = 6 + secrets.randbelow(1_000_000)
    while random_high == 8:
        random_high = 6 + secrets.randbelow(1_000_000)
    commit_replicas(random_high)

    assert read_lines(LOG_PATH) == [
        "DEPLOY: replicas=3",
        "DEPLOY: replicas=8",
        "DEPLOY: replicas=5",
        f"DEPLOY: replicas={random_high}",
    ]
    assert read_lines(ALERT_PATH) == [
        "ALERT: High replica count detected (8)",
        f"ALERT: High replica count detected ({random_high})",
    ]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
