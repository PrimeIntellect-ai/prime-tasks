#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import select
import signal
import subprocess
import time
import urllib.error
import urllib.request
import pytest

PROMPT = b"Enter deployment key: "
KEY = b"rollout-2024\n"
URL = "http://127.0.0.1:8080/status"
APP = "/home/user/deploy/v2/app"
SOURCE = "/home/user/src/app_v2.go"
START_SCRIPT = "/home/user/scripts/start_service.exp"
DEPLOY_SCRIPT = "/home/user/scripts/deploy.sh"
EMAIL = "/home/user/mail/new/deployment_report.eml"
EXPECTED_EMAIL = b"To: team@local\nFrom: deploy@local\nSubject: Deployment Success\n\nService v2 is live.\n"


def test_symlink_updated():
    symlink_path = "/home/user/deploy/current"
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} is missing."
    target = os.readlink(symlink_path)
    assert target == "/home/user/deploy/v2", f"Symlink {symlink_path} points to {target}, expected /home/user/deploy/v2."


def test_service_running():
    url = "http://127.0.0.1:8080/status"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode('utf-8').strip()
            assert body == "OK-v2", f"Expected response 'OK-v2', got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")


def test_email_file():
    email_path = "/home/user/mail/new/deployment_report.eml"
    assert os.path.isfile(email_path), f"Email file {email_path} is missing."

    with open(email_path, 'r') as f:
        content = f.read()

    assert "To: team@local" in content, "Email is missing 'To: team@local'"
    assert "From: deploy@local" in content, "Email is missing 'From: deploy@local'"
    assert "Subject: Deployment Success" in content, "Email is missing 'Subject: Deployment Success'"
    assert "Service v2 is live." in content, "Email is missing the required body text 'Service v2 is live.'"


def test_scripts_exist():
    expect_script = "/home/user/scripts/start_service.exp"
    deploy_script = "/home/user/scripts/deploy.sh"

    assert os.path.isfile(expect_script), f"Expect script {expect_script} is missing."
    assert os.path.isfile(deploy_script), f"Deploy script {deploy_script} is missing."


def test_v2_app_exists():
    app_path = "/home/user/deploy/v2/app"
    assert os.path.isfile(app_path), f"v2 app {app_path} is missing."
    assert os.access(app_path, os.X_OK), f"v2 app {app_path} is not executable."


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        result.add(fields[9])
        except OSError:
            pass
    return result


def stop_port(port=8080):
    inodes = listener_inodes(port)
    pids = set()
    if inodes:
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) == os.getpid():
                continue
            fd_dir = f"/proc/{name}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        link = os.readlink(f"{fd_dir}/{fd}")
                    except OSError:
                        continue
                    if link.startswith("socket:[") and link[8:-1] in inodes:
                        pids.add(int(name))
                        break
            except OSError:
                continue
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.25)
        if not listener_inodes(port):
            return
    assert not listener_inodes(port), f"Could not free TCP port {port}"


def exact_status(timeout=5):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(URL, timeout=0.5) as response:
                body = response.read()
                if response.status == 200 and body == b"OK-v2":
                    return
                last = AssertionError(f"status={response.status}, body={body!r}")
        except Exception as exc:
            last = exc
        time.sleep(0.1)
    raise AssertionError(f"Service did not return the exact response: {last}")


def read_exact_prompt(proc):
    data = b""
    deadline = time.monotonic() + 3
    while len(data) < len(PROMPT) and time.monotonic() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], 0.2)
        if ready:
            chunk = os.read(proc.stdout.fileno(), len(PROMPT) - len(data))
            if not chunk:
                break
            data += chunk
    assert data == PROMPT, f"Expected exact prompt {PROMPT!r}, got {data!r}"
    ready, _, _ = select.select([proc.stdout], [], [], 0.1)
    if ready:
        extra = os.read(proc.stdout.fileno(), 4096)
        assert extra == b"", f"Unexpected startup output after prompt: {extra!r}"


def exercise_binary(path):
    bad = subprocess.run(
        [path], input=b"incorrect-key\n", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert bad.returncode == 1, f"Wrong key returned status {bad.returncode}, not 1; stderr={bad.stderr!r}"
    assert bad.stdout == PROMPT, f"Wrong-key startup emitted {bad.stdout!r}, expected only {PROMPT!r}"

    stop_port()
    proc = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        read_exact_prompt(proc)
        proc.stdin.write(KEY)
        proc.stdin.flush()
        exact_status()
        assert proc.poll() is None, "Application exited after accepting the deployment key"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_port()


def test_artifacts_and_rollout_behavior():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} is missing"
    assert os.path.getsize(SOURCE) > 0, f"Go source {SOURCE} is empty"
    assert os.access(START_SCRIPT, os.X_OK), f"Startup script {START_SCRIPT} is not executable"
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"Deployment script {DEPLOY_SCRIPT} is not executable"

    go_info = subprocess.run(["go", "version", "-m", APP], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert go_info.returncode == 0 and b"go1" in go_info.stdout, "The deployed app is not a Go executable"

    rebuilt = "/tmp/app_v2_rebuilt"
    build = subprocess.run(["go", "build", "-o", rebuilt, SOURCE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert build.returncode == 0, f"app_v2.go does not compile: {build.stderr.decode(errors='replace')}"

    exercise_binary(APP)
    exercise_binary(rebuilt)

    with open(START_SCRIPT, "r", errors="replace") as f:
        start_text = f.read()
    start_lower = start_text.lower()
    assert "expect" in start_lower, "Startup script does not use Expect automation"
    assert APP in start_text, "Startup script does not execute the required v2 application"
    assert "Enter deployment key: " in start_text, "Startup script does not wait for the exact prompt"
    assert "rollout-2024" in start_text, "Startup script does not send the deployment key"

    with open(DEPLOY_SCRIPT, "r", errors="replace") as f:
        deploy_text = f.read()
    assert START_SCRIPT in deploy_text, "deploy.sh does not execute start_service.exp"
    assert re.search(r"\b(for|while|until)\b", deploy_text), "deploy.sh has no connectivity retry loop"
    assert re.search(r"\b(curl|nc)\b", deploy_text), "deploy.sh does not use curl or nc for diagnostics"
    assert "127.0.0.1:8080/status" in deploy_text, "deploy.sh does not check the required status endpoint"
    assert "OK-v2" in deploy_text, "deploy.sh does not validate the exact successful response"
    assert "10" in deploy_text, "deploy.sh does not implement the required 10-second limit"

    stop_port()
    launched = subprocess.run([START_SCRIPT], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=8)
    assert launched.returncode == 0, f"start_service.exp exited with status {launched.returncode}"
    exact_status()
    stop_port()

    current = "/home/user/deploy/current"
    if os.path.lexists(current):
        os.unlink(current)
    os.symlink("/home/user/deploy/v1", current)
    try:
        os.unlink(EMAIL)
    except FileNotFoundError:
        pass

    rollout = subprocess.run([DEPLOY_SCRIPT], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=15)
    assert rollout.returncode == 0, f"deploy.sh failed: {rollout.stderr.decode(errors='replace')}"
    exact_status()
    assert os.path.islink(current), "deploy.sh did not leave current as a symlink"
    assert os.readlink(current) == "/home/user/deploy/v2", "deploy.sh did not switch current to v2"
    assert os.path.isfile(EMAIL), "deploy.sh did not create the deployment email"
    with open(EMAIL, "rb") as f:
        email_bytes = f.read()
    assert email_bytes == EXPECTED_EMAIL, f"Email structure is not exact: {email_bytes!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
