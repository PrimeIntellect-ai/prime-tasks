#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import smtplib
import subprocess
import tempfile
import time
import uuid

import pytest
import requests


def normalized(text):
    return re.sub(r'[^\w\s]', '', text.lower()).split()


def assert_loopback_listener(port):
    expected = f"0100007F:{port:04X}"
    listeners = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 4 and fields[3] == "0A":
                    listeners.append(fields[1].upper())
    assert expected in listeners, f"Port {port} is not listening specifically on 127.0.0.1"


def request_transcript():
    url = "http://127.0.0.1:8080/transcript"
    try:
        response = requests.get(url, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain"), \
        f"Transcript response is not plain text: {response.headers.get('Content-Type')}"
    return response


def test_http_service():
    assert_loopback_listener(8080)
    access_log = "/home/user/logs/access.log"
    initial_size = os.path.getsize(access_log) if os.path.isfile(access_log) else 0

    response = request_transcript()
    expected_transcript = "Attention, the system update has been deployed successfully."
    expected_clean = re.sub(r'[^\w\s]', '', expected_transcript.lower())
    actual_clean = re.sub(r'[^\w\s]', '', response.text.lower())
    assert expected_clean in actual_clean, \
        f"Expected transcript '{expected_transcript}' not found in response: {response.text}"

    assert os.path.isfile(access_log), f"Access log missing at {access_log}"
    assert os.path.getsize(access_log) > initial_size, "Access log was not appended for the request"
    with open(access_log) as f:
        assert len(f.read().strip()) > 0, "Access log is empty after request"

    # Replace the recording after service startup with a verifier-generated fixture.
    # This proves that /transcript reads and transcribes the actual audio rather than
    # returning the one sentence originally shipped in the image.
    rng = __import__('random').SystemRandom()
    phrase = "Please confirm the {} {} is {}.".format(
        rng.choice(["green", "silver", "yellow", "purple"]),
        rng.choice(["server", "database", "network", "backup"]),
        rng.choice(["ready", "stable", "online", "complete"]),
    )
    fd, wav_tmp = tempfile.mkstemp(prefix="verifier-voicemail-", suffix=".wav", dir="/app")
    os.close(fd)
    try:
        subprocess.run(["espeak", "-s", "135", "-w", wav_tmp, phrase], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.replace(wav_tmp, "/app/voicemail.wav")
    finally:
        if os.path.exists(wav_tmp):
            os.unlink(wav_tmp)

    before_second = os.path.getsize(access_log)
    response = request_transcript()
    assert normalized(response.text) == normalized(phrase), \
        f"Service did not transcribe the generated audio. Expected {phrase!r}, got {response.text!r}"
    assert os.path.getsize(access_log) > before_second, \
        "Access log was not appended for the second request"


def test_smtp_service():
    assert_loopback_listener(2525)
    maillog_path = "/home/user/maillog.txt"
    initial_size = os.path.getsize(maillog_path) if os.path.exists(maillog_path) else 0
    token = uuid.uuid4().hex
    test_subject = f"Test Verifier Email {token}"
    test_body = f"This is verifier payload {token}."
    message = f"Subject: {test_subject}\r\nX-Verifier-Token: {token}\r\n\r\n{test_body}"

    try:
        with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as server:
            server.ehlo("localhost")
            server.sendmail("test@verifier.local", ["admin@localhost"], message)
    except Exception as e:
        pytest.fail(f"Failed to communicate with SMTP server on 2525: {e}")

    time.sleep(0.5)
    assert os.path.isfile(maillog_path), f"Maillog missing at {maillog_path}"
    assert os.path.getsize(maillog_path) > initial_size, "SMTP transaction did not append to maillog"
    with open(maillog_path, "rb") as f:
        f.seek(initial_size)
        appended = f.read().decode(errors="replace")
    assert test_subject in appended, f"New SMTP subject not appended to {maillog_path}"
    assert test_body in appended, f"New SMTP body not appended to {maillog_path}"


def test_git_hook():
    deploy_git = "/home/user/deploy.git"
    app_code = "/home/user/app_code"
    deploy_log = "/home/user/logs/deploy.log"
    maillog = "/home/user/maillog.txt"
    hook = os.path.join(deploy_git, "hooks", "post-receive")

    assert os.path.isdir(deploy_git), f"Bare git repository missing at {deploy_git}"
    result = subprocess.run(["git", "-C", deploy_git, "rev-parse", "--is-bare-repository"],
                            check=True, text=True, capture_output=True)
    assert result.stdout.strip() == "true", f"Repository at {deploy_git} is not bare"
    assert os.path.isfile(hook), f"post-receive hook missing at {hook}"
    assert os.access(hook, os.X_OK), "post-receive hook is not executable"

    deploy_before = os.path.getsize(deploy_log) if os.path.isfile(deploy_log) else 0
    mail_before = os.path.getsize(maillog) if os.path.isfile(maillog) else 0
    token = uuid.uuid4().hex

    with tempfile.TemporaryDirectory() as temp_dir:
        subprocess.run(["git", "clone", deploy_git, temp_dir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@verifier.local"], cwd=temp_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Verifier"], cwd=temp_dir, check=True)

        dummy_file = os.path.join(temp_dir, "dummy.txt")
        with open(dummy_file, "w") as f:
            f.write(f"test commit {token}\n")
        subprocess.run(["git", "add", "dummy.txt"], cwd=temp_dir, check=True)
        subprocess.run(["git", "commit", "-m", f"Verifier commit {token}"],
                       cwd=temp_dir, check=True, capture_output=True)
        branch = subprocess.run(["git", "symbolic-ref", "--short", "HEAD"], cwd=temp_dir,
                                check=True, text=True, capture_output=True).stdout.strip()
        subprocess.run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=temp_dir,
                       check=True, capture_output=True)

    time.sleep(0.5)
    deployed_file = os.path.join(app_code, "dummy.txt")
    assert os.path.isdir(app_code), f"App code directory missing at {app_code}"
    assert os.path.isfile(deployed_file), "Pushed file not found in app_code directory"
    with open(deployed_file) as f:
        assert token in f.read(), "app_code contains a preexisting file, not the newly pushed content"

    assert os.path.isfile(deploy_log), f"Deploy log missing at {deploy_log}"
    assert os.path.getsize(deploy_log) > deploy_before, "Git push did not append a deployment log entry"
    with open(deploy_log) as f:
        assert len(f.read().strip()) > 0, "Deploy log is empty"

    assert os.path.isfile(maillog), f"Maillog missing at {maillog}"
    assert os.path.getsize(maillog) > mail_before, "Git push did not append a notification email"
    with open(maillog, "rb") as f:
        f.seek(mail_before)
        appended_mail = f.read().decode(errors="replace")
    assert "Subject: Code Pushed" in appended_mail, \
        "New maillog content lacks 'Subject: Code Pushed' after git push"


def test_logrotate_config():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config missing at {conf_path}"
    with open(conf_path) as f:
        original = f.read()

    assert "/home/user/logs/*.log" in original, \
        "Target /home/user/logs/*.log not found in logrotate.conf"

    # Validate the file with logrotate itself, as the unprivileged service user.
    checked = subprocess.run(
        ["runuser", "-u", "user", "--", "logrotate", "--debug", conf_path],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert checked.returncode == 0 and "error:" not in checked.stdout.lower(), \
        f"Invalid logrotate configuration:\n{checked.stdout}"

    # Strip comments before inspecting directives, so keywords in comments do not count.
    uncommented = "\n".join(line.split("#", 1)[0] for line in original.splitlines())
    target = re.search(r'(?m)^\s*["\']?/home/user/logs/\*\.log["\']?\s*\{(.*?)^\s*\}',
                       uncommented, re.DOTALL)
    assert target, "No logrotate stanza for /home/user/logs/*.log"
    body = target.group(1)

    def directive(pattern):
        return re.search(rf"(?m)^\s*{pattern}\s*$", body) is not None

    assert directive("daily"), "daily directive missing from the logs stanza"
    assert directive(r"rotate\s+5"), "rotate 5 directive missing from the logs stanza"
    assert directive("compress"), "compress directive missing from the logs stanza"
    assert directive("missingok"), "missingok directive missing from the logs stanza"
    assert not directive(r"(?:hourly|weekly|monthly|yearly)"), "Conflicting rotation frequency found"
    assert not directive("nocompress"), "nocompress conflicts with required compression"
    assert re.search(r"(?m)^\s*su(?:\s|$)", uncommented) is None, \
        "Found forbidden su directive in logrotate.conf"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
