#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets
import pytest

SCRIPT = "/home/user/deploy_operator.py"
MANIFEST_DIR = "/home/user/manifests"
LOG = "/home/user/monitoring.log"
EMAIL = "/home/user/deployment_email.eml"
STAGES = ["stage1", "stage2", "stage3"]


def manifest_text(stage):
    return f"""apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-{stage}
spec:
  template:
    spec:
      containers:
      - name: app
        image: myregistry.local/frontend:v1.0
"""


def reset_inputs(failed_stage):
    os.makedirs(MANIFEST_DIR, exist_ok=True)
    for stage in STAGES:
        with open(os.path.join(MANIFEST_DIR, f"{stage}.yaml"), "w") as f:
            f.write(manifest_text(stage))

    nonce = secrets.token_hex(8)
    lines = [f"2026-01-01 00:00:00 CRITICAL [unrelated-{nonce}] ignored alert"]
    for index, stage in enumerate(STAGES, 1):
        lines.append(f"2026-01-01 00:0{index}:00 INFO [{stage}] healthy {nonce}")
        if stage == failed_stage:
            lines.append(f"2026-01-01 00:0{index}:30 CRITICAL [{stage}] generated failure {nonce}")
        else:
            lines.append(f"2026-01-01 00:0{index}:30 WARN [{stage}] generated warning {nonce}")
    with open(LOG, "w") as f:
        f.write("\n".join(reversed(lines)) + "\n")

    if os.path.exists(EMAIL):
        os.remove(EMAIL)


def expected_email(successful, failed):
    return (
        "To: devops-alerts@local.domain\n"
        "Subject: Staged Deployment Report\n\n"
        f"Successful Deployments: {', '.join(successful)}\n"
        f"Failed Stage: {failed if failed is not None else 'None'}"
    )


def assert_scenario(failed_stage):
    reset_inputs(failed_stage)
    subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )

    failure_index = STAGES.index(failed_stage) if failed_stage is not None else len(STAGES)
    successful = STAGES[:failure_index]

    for index, stage in enumerate(STAGES):
        path = os.path.join(MANIFEST_DIR, f"{stage}.yaml")
        assert os.path.isfile(path), f"{path} is missing after execution"
        with open(path, "r") as f:
            content = f.read()
        if index < failure_index:
            assert "image: myregistry.local/frontend:v2.0" in content
            assert "image: myregistry.local/frontend:v1.0" not in content
        else:
            assert "image: myregistry.local/frontend:v1.0" in content
            assert "image: myregistry.local/frontend:v2.0" not in content

    assert os.path.isfile(EMAIL), f"{EMAIL} was not generated"
    with open(EMAIL, "r") as f:
        actual = f.read().strip()
    assert actual == expected_email(successful, failed_stage)


def test_script_exists_and_implements_behavior():
    assert os.path.lexists(SCRIPT), f"{SCRIPT} is missing"
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular file"
    with open(SCRIPT, "r") as f:
        source = f.read()
    assert source.strip(), f"{SCRIPT} is empty"
    compile(source, SCRIPT, "exec")

    # Exercise success and every possible abort point using freshly generated inputs.
    for failed_stage in (None, "stage1", "stage2", "stage3"):
        assert_scenario(failed_stage)

    # Restore and execute the task's original stage3-failure case for the original assertions.
    reset_inputs("stage3")
    subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def test_manifest_stage1_updated():
    filepath = "/home/user/manifests/stage1.yaml"
    assert os.path.isfile(filepath), f"{filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()
    assert "image: myregistry.local/frontend:v2.0" in content, f"{filepath} was not updated to v2.0"
    assert "image: myregistry.local/frontend:v1.0" not in content, f"{filepath} still contains v1.0"


def test_manifest_stage2_updated():
    filepath = "/home/user/manifests/stage2.yaml"
    assert os.path.isfile(filepath), f"{filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()
    assert "image: myregistry.local/frontend:v2.0" in content, f"{filepath} was not updated to v2.0"
    assert "image: myregistry.local/frontend:v1.0" not in content, f"{filepath} still contains v1.0"


def test_manifest_stage3_unchanged():
    filepath = "/home/user/manifests/stage3.yaml"
    assert os.path.isfile(filepath), f"{filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()
    assert "image: myregistry.local/frontend:v1.0" in content, f"{filepath} was incorrectly updated. It should remain v1.0"
    assert "image: myregistry.local/frontend:v2.0" not in content, f"{filepath} should not contain v2.0 due to health check failure"


def test_deployment_email_content():
    filepath = "/home/user/deployment_email.eml"
    assert os.path.isfile(filepath), f"{filepath} was not generated"

    expected_content = (
        "To: devops-alerts@local.domain\n"
        "Subject: Staged Deployment Report\n\n"
        "Successful Deployments: stage1, stage2\n"
        "Failed Stage: stage3"
    ).strip()

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {filepath} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
