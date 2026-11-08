#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import stat
import subprocess
import time
import uuid

import pytest

NGINX_CONF = "/home/user/nginx/nginx.conf"
SUPERVISOR_CONF = "/home/user/supervisor/supervisord.conf"
HOOK = "/home/user/cost-data.git/hooks/post-receive"
BARE_REPO = "/home/user/cost-data.git"
SOCKET_PATH = "/home/user/run/app.sock"


def run(command, cwd=None, input_text=None, check=True):
    return subprocess.run(
        command,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
        timeout=30,
    )


def run_as_user(command, cwd=None, input_text=None, check=True):
    return run(["runuser", "-u", "user", "--"] + command, cwd, input_text, check)


def supervisorctl(*args, check=True):
    return run(
        ["supervisorctl", "-c", SUPERVISOR_CONF] + list(args),
        check=check,
    )


def app_pid():
    result = supervisorctl("pid", "finops_app")
    value = result.stdout.strip()
    assert value.isdigit() and int(value) > 0, f"Invalid finops_app PID: {value!r}"
    return int(value)


def curl_json(url, unix_socket=None, attempts=1):
    command = ["curl", "--fail", "--silent", "--show-error", "--max-time", "3"]
    if unix_socket:
        command += ["--unix-socket", unix_socket]
    command.append(url)

    last = None
    for _ in range(attempts):
        last = run(command, check=False)
        if last.returncode == 0:
            try:
                return json.loads(last.stdout)
            except json.JSONDecodeError:
                pass
        time.sleep(0.25)
    pytest.fail(
        f"Request failed or returned invalid JSON: stdout={last.stdout!r}, stderr={last.stderr!r}"
    )


def test_socket_configuration_fixed():
    """Verify both configurations use the required UNIX socket."""
    assert os.path.isfile(NGINX_CONF), f"Nginx config is missing: {NGINX_CONF}"
    assert os.path.isfile(SUPERVISOR_CONF), f"Supervisor config is missing: {SUPERVISOR_CONF}"

    with open(NGINX_CONF, "r") as f:
        nginx_content = f.read()
    with open(SUPERVISOR_CONF, "r") as f:
        supervisor_content = f.read()

    socket_path = "/home/user/run/app.sock"
    nginx_has_socket = f"unix:{socket_path}" in nginx_content
    supervisor_has_socket = (
        f"unix:{socket_path}" in supervisor_content
        or f"bind {socket_path}" in supervisor_content
        or f"bind=unix:{socket_path}" in supervisor_content.replace(" ", "")
    )

    assert nginx_has_socket and supervisor_has_socket, (
        "Both Nginx and Supervisor must be configured to use the UNIX socket at /home/user/run/app.sock"
    )


def test_git_hook_executable():
    """Verify that the post-receive hook exists, is executable, and is Python."""
    assert os.path.isfile(HOOK), f"Git hook is missing at {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Git hook at {HOOK} is not executable"

    with open(HOOK, "r", encoding="utf-8") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "python" in first_line.lower(), (
        "The executable post-receive hook must use a Python interpreter"
    )
    compile(source, HOOK, "exec")


def test_verification_log_content():
    """Verify that the verification log contains the instructed JSON data."""
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Verification log is missing at {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content, "Verification log is empty"

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Verification log does not contain valid JSON. Content: {content}")

    assert data.get("status") == "optimized", f"Expected status 'optimized', got {data.get('status')}"
    assert data.get("total") == 150.50, f"Expected total 150.50, got {data.get('total')}"


def test_instructed_push_and_live_services_exist():
    workspace = "/home/user/workspace"
    assert os.path.isdir(os.path.join(workspace, ".git")), (
        "/home/user/workspace is not a clone of the cost-data repository"
    )
    origin = run_as_user(["git", "-C", workspace, "remote", "get-url", "origin"]).stdout.strip()
    assert os.path.realpath(origin) == os.path.realpath(BARE_REPO)

    committed = run_as_user(
        ["git", "--git-dir", BARE_REPO, "show", "refs/heads/main:cost.json"]
    ).stdout
    assert json.loads(committed) == {"status": "optimized", "total": 150.50}

    status_result = supervisorctl("status", "finops_app")
    assert "RUNNING" in status_result.stdout, status_result.stdout + status_result.stderr
    app_pid()

    nginx_test = run(["nginx", "-p", "/home/user/nginx", "-c", NGINX_CONF, "-t"], check=False)
    assert nginx_test.returncode == 0, nginx_test.stdout + nginx_test.stderr
    nginx_pid_file = "/home/user/run/nginx.pid"
    assert os.path.isfile(nginx_pid_file), "Nginx PID file is missing"
    with open(nginx_pid_file) as f:
        nginx_pid = int(f.read().strip())
    os.kill(nginx_pid, 0)

    assert os.path.exists(SOCKET_PATH), "Application UNIX socket does not exist"
    assert stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode), f"{SOCKET_PATH} is not a UNIX socket"

    expected = {"status": "optimized", "total": 150.50}
    assert curl_json("http://localhost:8080/api/costs", attempts=8) == expected
    assert curl_json("http://localhost/api/costs", unix_socket=SOCKET_PATH, attempts=8) == expected


def test_post_receive_hook_on_real_push_and_invalid_revision():
    token = uuid.uuid4().hex
    checkout = f"/home/user/verifier-hook-test-{token}"
    expected = {
        "status": f"verified-{token}",
        "total": int(token[:6], 16) / 100.0,
    }
    marker_content = f"archive-marker-{token}\n"

    old_pid = app_pid()
    old_target = os.path.realpath("/home/user/app_data/current")

    run_as_user(["git", "clone", "--branch", "main", BARE_REPO, checkout])
    run_as_user(["git", "config", "user.name", "Verifier"], cwd=checkout)
    run_as_user(["git", "config", "user.email", "verifier@example.invalid"], cwd=checkout)
    run_as_user(["bash", "-c", "cat > cost.json"], cwd=checkout, input_text=json.dumps(expected) + "\n")
    run_as_user(["bash", "-c", "cat > verifier-marker.txt"], cwd=checkout, input_text=marker_content)
    run_as_user(["git", "add", "cost.json", "verifier-marker.txt"], cwd=checkout)
    run_as_user(["git", "commit", "-m", f"verifier deployment {token}"], cwd=checkout)
    newrev = run_as_user(["git", "rev-parse", "HEAD"], cwd=checkout).stdout.strip()

    push = run_as_user(["git", "push", "origin", "HEAD:main"], cwd=checkout, check=False)
    assert push.returncode == 0, push.stdout + push.stderr

    release = f"/home/user/app_data/releases/{newrev}"
    assert os.path.isdir(release), f"Hook did not extract pushed revision into {release}"
    with open(os.path.join(release, "cost.json")) as f:
        assert json.load(f) == expected
    with open(os.path.join(release, "verifier-marker.txt")) as f:
        assert f.read() == marker_content

    assert os.path.islink("/home/user/app_data/current"), "current must be a symlink"
    assert os.path.realpath("/home/user/app_data/current") == os.path.realpath(release), (
        "current symlink does not point to the pushed revision"
    )
    assert os.path.realpath("/home/user/app_data/current") != old_target

    assert curl_json("http://localhost:8080/api/costs", attempts=20) == expected
    assert curl_json("http://localhost/api/costs", unix_socket=SOCKET_PATH, attempts=20) == expected
    restarted_pid = app_pid()
    assert restarted_pid != old_pid, "The hook did not restart finops_app after the push"

    # Build a reachable commit without cost.json, copy its object to the bare repo
    # without invoking receive hooks, then execute the hook exactly as Git would.
    run_as_user(["git", "rm", "cost.json"], cwd=checkout)
    run_as_user(["git", "commit", "-m", f"invalid deployment {token}"], cwd=checkout)
    badrev = run_as_user(["git", "rev-parse", "HEAD"], cwd=checkout).stdout.strip()
    invalid_ref = f"refs/heads/verifier-invalid-{token}"
    run_as_user(
        ["git", "-C", BARE_REPO, "fetch", checkout, f"{badrev}:{invalid_ref}"]
    )

    before_invalid_target = os.path.realpath("/home/user/app_data/current")
    before_invalid_pid = app_pid()
    hook_result = run_as_user(
        [HOOK],
        cwd=BARE_REPO,
        input_text=f"{newrev} {badrev} {invalid_ref}\n",
        check=False,
    )
    assert hook_result.returncode != 0, "Hook accepted a revision that has no cost.json"
    assert "cost.json" in (hook_result.stdout + hook_result.stderr), (
        "Hook did not report the missing cost.json"
    )
    assert os.path.realpath("/home/user/app_data/current") == before_invalid_target, (
        "Hook switched current to an invalid release"
    )
    assert app_pid() == before_invalid_pid, (
        "Hook restarted the application even though validation failed"
    )
    assert curl_json("http://localhost:8080/api/costs", attempts=5) == expected

    shutil.rmtree(checkout, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
