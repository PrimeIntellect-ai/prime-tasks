#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
import urllib.request
import uuid

import pytest
import yaml

WORKSPACE = "/home/user/workspace"
BARE_REPO = "/home/user/cluster-state.git"
ACTIVE = "/home/user/cluster-active"
LOG = "/home/user/cluster-status.log"
OPERATOR = "/home/user/operator"


def git(repo, *args):
    return subprocess.run(
        ["git", "-c", f"safe.directory={repo}", "-C", repo, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()


def read_log():
    if not os.path.exists(LOG):
        return ""
    with open(LOG, "r", encoding="utf-8") as f:
        return f.read()


def wait_for_appended_line(prefix, expected, timeout=8):
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        last = read_log()
        if last.startswith(prefix):
            delta = last[len(prefix):]
            if delta.splitlines().count(expected) >= 1:
                assert delta.splitlines().count(expected) == 1, \
                    f"Operator emitted {expected!r} more than once for one reload"
                return
        time.sleep(0.1)
    pytest.fail(f"Expected dynamically generated log line {expected!r}; log was: {last!r}")


def test_pre_receive_hook_fixed():
    hook_path = "/home/user/cluster-state.git/hooks/pre-receive"
    if os.path.exists(hook_path):
        st = os.stat(hook_path)
        is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
        if is_executable:
            try:
                result = subprocess.run(
                    [hook_path], input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )
                assert result.returncode == 0, \
                    "The pre-receive hook is still failing (returns non-zero exit code)."
            except Exception as e:
                pytest.fail(f"Failed to execute pre-receive hook: {e}")


def test_post_receive_hook_configured():
    hook = os.path.join(BARE_REPO, "hooks", "post-receive")
    assert os.path.isfile(hook), "The post-receive hook does not exist"
    mode = os.stat(hook).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), \
        "The post-receive hook is not executable"


def test_operator_artifact_and_daemon_exist():
    assert os.path.isfile(OPERATOR), f"Operator program {OPERATOR} is missing"
    assert os.path.getsize(OPERATOR) > 0, f"Operator program {OPERATOR} is empty"

    running = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
            if OPERATOR in argv:
                running = True
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert running, "No running daemon process references /home/user/operator"


def test_manifest_checked_out():
    app_yaml_path = "/home/user/cluster-active/app.yaml"
    assert os.path.isfile(app_yaml_path), \
        f"Manifest was not checked out to {app_yaml_path}. Ensure the post-receive hook is working."


def test_original_app_was_committed_and_pushed():
    branch = git(WORKSPACE, "symbolic-ref", "--short", "HEAD")
    workspace_head = git(WORKSPACE, "rev-parse", "HEAD")
    bare_head = git(BARE_REPO, "rev-parse", f"refs/heads/{branch}")
    assert bare_head == workspace_head, "The workspace HEAD was not pushed to the bare repository"

    manifest_text = git(BARE_REPO, "show", f"refs/heads/{branch}:app.yaml")
    manifest = yaml.safe_load(manifest_text)
    assert manifest == {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": "frontend-app"},
        "spec": {"replicas": 3},
    }, "The pushed app.yaml does not contain the required manifest"


def test_operator_log_output():
    assert os.path.isfile(LOG), \
        f"Log file {LOG} not found. Did the operator run and process the webhook?"
    content = read_log()
    expected_log = "Loaded Deployment: frontend-app"
    assert expected_log in content, \
        f"Log file missing expected exact format: {expected_log!r}. Found: {content}"


def test_push_runs_hook_and_operator_parses_dynamic_yaml():
    token = uuid.uuid4().hex
    filename = f"verifier-{token}.yaml"
    workspace_path = os.path.join(WORKSPACE, filename)
    active_path = os.path.join(ACTIVE, filename)

    document = {
        "apiVersion": "audit.example/v1",
        "metadata": {
            "labels": {"purpose": "dynamic-verification"},
            "name": f"generated-{token}",
        },
        "kind": f"VerifierKind{token[:12]}",
        "spec": {"decoy": {"kind": "WrongKind", "name": "wrong-name"}},
    }
    with open(workspace_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(document, f, sort_keys=False)

    git(WORKSPACE, "add", "--", filename)
    git(WORKSPACE, "commit", "-m", f"Verifier dynamic manifest {token}", "--", filename)
    branch = git(WORKSPACE, "symbolic-ref", "--short", "HEAD")

    before = read_log()
    git(WORKSPACE, "push", "origin", f"HEAD:refs/heads/{branch}")

    assert os.path.isfile(active_path), \
        "A real push did not cause the post-receive hook to check out the new manifest"
    with open(active_path, "r", encoding="utf-8") as f:
        checked_out = yaml.safe_load(f)
    assert checked_out == document, "The hook did not check out the pushed YAML accurately"

    expected = f"Loaded {document['kind']}: {document['metadata']['name']}"
    wait_for_appended_line(before, expected)


def test_reload_endpoint_is_live_and_dynamically_parses_yaml():
    token = uuid.uuid4().hex
    path = os.path.join(ACTIVE, f"endpoint-{token}.yaml")
    document = {
        "metadata": {"annotations": {"decoy": "name: incorrect"}, "name": f"endpoint-{token}"},
        "apiVersion": "v1",
        "kind": f"EndpointKind{token[:12]}",
    }
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(document, f, sort_keys=False)

    before = read_log()
    try:
        with urllib.request.urlopen("http://127.0.0.1:9090/reload", timeout=3) as response:
            assert 200 <= response.status < 300, f"/reload returned HTTP {response.status}"
    except Exception as e:
        pytest.fail(f"Operator is not serving GET /reload on 127.0.0.1:9090: {e}")

    expected = f"Loaded {document['kind']}: {document['metadata']['name']}"
    wait_for_appended_line(before, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
