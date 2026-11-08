#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

TOKEN = "S3CR3T-AL3RT-T0K3N"
BASE_URL = "http://127.0.0.1:8000"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def request(method, path, payload=None, headers=None, timeout=5):
    body = None
    request_headers = dict(headers or {})
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        BASE_URL + path, data=body, headers=request_headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read()
            return response.status, raw
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except OSError as error:
        pytest.fail(f"Failed to connect to the Alert Dashboard Server on {BASE_URL}: {error}")


def json_request(method, path, payload=None, headers=None):
    status, raw = request(method, path, payload, headers)
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception as error:
        pytest.fail(f"{method} {path} did not return valid JSON: {error}; body={raw!r}")
    return status, data


def run(command, **kwargs):
    return subprocess.run(command, text=True, capture_output=True, **kwargs)


def git(*args, cwd=None, check=True):
    result = run(["git", *args], cwd=cwd)
    if check and result.returncode != 0:
        pytest.fail(
            f"git {' '.join(args)} failed with code {result.returncode}:\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result


def current_alerts():
    status, data = json_request("GET", "/alerts", headers=AUTH)
    assert status == 200, f"Expected status code 200, got {status}"
    assert isinstance(data, list), f"Expected response to be a list, got {type(data)}"
    return data


def wait_for_alert(expected, previous_count=0, timeout=8):
    deadline = time.time() + timeout
    latest = []
    while time.time() < deadline:
        latest = current_alerts()
        if expected in latest and latest.count(expected) > previous_count:
            return
        time.sleep(0.2)
    pytest.fail(f"Expected a new {expected!r} alert; dashboard contained {latest!r}")


def remote_master():
    result = git("--git-dir=/home/user/alerts.git", "rev-parse", "--verify", "refs/heads/master", check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def test_server_status():
    status, data = json_request("GET", "/status")
    assert status == 200, f"Expected status code 200, got {status}"
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    assert data.get("tz") == "Europe/Berlin", f"Expected tz 'Europe/Berlin', got {data.get('tz')}"
    assert data.get("locale") == "de_DE.UTF-8", f"Expected locale 'de_DE.UTF-8', got {data.get('locale')}"


def test_server_alert_unauthorized():
    payload = {"level": "TEST", "message": "Test Message"}
    status, _ = request("POST", "/alert", payload)
    assert status == 401, f"Expected status code 401 for unauthorized request, got {status}"

    status, _ = request(
        "POST", "/alert", payload,
        {"Authorization": "Bearer definitely-not-the-token"},
    )
    assert status == 401, f"Expected status code 401 for an invalid token, got {status}"


def test_server_alert_authorized():
    payload = {"level": "TEST", "message": "Test Message"}
    status, _ = request("POST", "/alert", payload, AUTH)
    assert status == 200, f"Expected status code 200, got {status}"


def test_server_alerts_get():
    status, _ = request("GET", "/alerts")
    assert status == 401, f"Expected unauthorized GET /alerts to return 401, got {status}"

    status, _ = request(
        "GET", "/alerts", headers={"Authorization": "Bearer wrong-token"}
    )
    assert status == 401, f"Expected invalid-token GET /alerts to return 401, got {status}"

    data = current_alerts()
    expected_alert = {"level": "TEST", "message": "Test Message"}
    assert expected_alert in data, f"Expected {expected_alert} to be in the alerts list, got {data}"


def test_server_handles_derived_alert_data():
    expected = {
        "level": "DYNAMIC_" + uuid.uuid4().hex[:10],
        "message": "message-" + uuid.uuid4().hex,
    }
    before = current_alerts().count(expected)
    status, _ = request("POST", "/alert", expected, AUTH)
    assert status == 200, f"Expected status code 200, got {status}"
    wait_for_alert(expected, before)


def test_git_bare_repo():
    repo_path = "/home/user/alerts.git"
    assert os.path.isdir(repo_path), f"Directory {repo_path} does not exist"

    config_path = os.path.join(repo_path, "config")
    assert os.path.isfile(config_path), f"Git config file missing in {repo_path}"
    with open(config_path, "r", encoding="utf-8") as config_file:
        content = config_file.read()
    assert "bare = true" in content.lower(), f"Repository at {repo_path} is not configured as bare"

    result = git("--git-dir=" + repo_path, "rev-parse", "--is-bare-repository")
    assert result.stdout.strip() == "true", f"{repo_path} is not a valid bare Git repository"


def test_post_receive_hook():
    hook_path = "/home/user/alerts.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable"
    with open(hook_path, "r", encoding="utf-8", errors="replace") as hook_file:
        first_line = hook_file.readline().lower()
    assert first_line.startswith("#!") and ("python" in first_line or "bash" in first_line), \
        "post-receive must be an executable Python or Bash hook"


def test_expect_script_and_local_clone_work():
    script_path = "/home/user/auto_alert.exp"
    local_repo = "/home/user/alerts_local"
    assert os.path.isfile(script_path), f"Expect script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Expect script at {script_path} is not executable"

    with open(script_path, "r", encoding="utf-8", errors="replace") as script_file:
        script = script_file.read()
    first_line = script.splitlines()[0].lower() if script.splitlines() else ""
    assert first_line.startswith("#!") and "expect" in first_line, "auto_alert.exp is not an Expect script"
    assert re.search(r"\bspawn\b[^\n]*/app/interactive_submit\.sh", script), \
        "Expect script does not spawn /app/interactive_submit.sh"
    for required in ("/home/user/alerts_local", "WARNING", "Memory usage high"):
        assert required in script, f"Expect script does not provide required value {required!r}"

    assert os.path.isdir(local_repo), f"Local repository {local_repo} does not exist"
    result = git("-C", local_repo, "rev-parse", "--is-inside-work-tree")
    assert result.stdout.strip() == "true", f"{local_repo} is not a valid working Git repository"
    origin = git("-C", local_repo, "remote", "get-url", "origin").stdout.strip()
    origin_path = origin[7:] if origin.startswith("file://") else origin
    assert os.path.realpath(origin_path) == "/home/user/alerts.git", \
        f"Expected origin to point to /home/user/alerts.git, got {origin!r}"

    expected = {"level": "WARNING", "message": "Memory usage high"}
    previous_alert_count = current_alerts().count(expected)
    before = remote_master()
    result = run([
        "runuser", "-u", "user", "--", "env",
        "HOME=/home/user", "PATH=/usr/local/bin:/usr/bin:/bin",
        "/usr/bin/expect", script_path,
    ], timeout=30)
    assert result.returncode == 0, (
        f"Executing auto_alert.exp failed with code {result.returncode}:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    after = remote_master()
    assert after is not None and after != before, "Expect automation did not push a new commit to master"
    changed = git(
        "--git-dir=/home/user/alerts.git", "diff-tree", "--root", "--no-commit-id",
        "--name-only", "-r", after,
    ).stdout.splitlines()
    matching = []
    for filename in changed:
        if filename.endswith(".alert"):
            shown = git("--git-dir=/home/user/alerts.git", "show", f"{after}:{filename}").stdout.strip()
            if shown == "WARNING:Memory usage high":
                matching.append(filename)
    assert matching, "Expect automation did not commit the required WARNING alert file"
    wait_for_alert(expected, previous_alert_count)


def test_post_receive_hook_end_to_end_for_added_and_modified_files():
    suffix = uuid.uuid4().hex
    filename = f"audit_{suffix}.alert"
    first = {"level": "CRITICAL", "message": f"Disk-{suffix}"}
    second = {"level": "RECOVERED", "message": f"Disk-{suffix}"}
    first_count = current_alerts().count(first)
    second_count = current_alerts().count(second)

    with tempfile.TemporaryDirectory() as tempdir:
        work = os.path.join(tempdir, "work")
        git("clone", "/home/user/alerts.git", work)
        git("config", "user.name", "Verifier", cwd=work)
        git("config", "user.email", "verifier@example.invalid", cwd=work)

        alert_path = os.path.join(work, filename)
        with open(alert_path, "w", encoding="utf-8") as alert_file:
            alert_file.write(f"{first['level']}:{first['message']}\n")
        git("add", filename, cwd=work)
        git("commit", "-m", "Add verifier alert", cwd=work)
        git("push", "origin", "HEAD:refs/heads/master", cwd=work)
        wait_for_alert(first, first_count)

        with open(alert_path, "w", encoding="utf-8") as alert_file:
            alert_file.write(f"{second['level']}:{second['message']}\n")
        git("add", filename, cwd=work)
        git("commit", "-m", "Modify verifier alert", cwd=work)
        git("push", "origin", "HEAD:refs/heads/master", cwd=work)
        wait_for_alert(second, second_count)


def test_cron_job():
    result = run(["crontab", "-u", "user", "-l"])
    assert result.returncode == 0, f"Failed to read crontab for user: {result.stderr}"
    crontab_content = result.stdout
    assert "auto_alert.exp" in crontab_content, "auto_alert.exp not found in user crontab"

    active_lines = [
        line.strip() for line in crontab_content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    found_schedule = False
    for line in active_lines:
        fields = line.split()
        if len(fields) >= 6 and fields[:5] == ["*/5", "*", "*", "*", "*"]:
            command = " ".join(fields[5:])
            if "/home/user/auto_alert.exp" in command:
                found_schedule = True
                break
    assert found_schedule, (
        "Cron job for /home/user/auto_alert.exp is not scheduled every 5 minutes "
        f"in the user crontab. Crontab content: {crontab_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
