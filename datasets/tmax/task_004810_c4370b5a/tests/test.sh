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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = f"{BASE_URL}/policy-check"


def read_badge_token():
    result = subprocess.run(
        ["tesseract", "/app/auth_badge.png", "stdout", "--psm", "7"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


VALID_TOKEN = read_badge_token()


def wait_for_service(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(BASE_URL, timeout=1)
            return
        except requests.exceptions.RequestException:
            pass
        try:
            requests.post(ENDPOINT, json={}, timeout=1)
            return
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.25)
    raise AssertionError("Service did not become available on port 8080")


@pytest.fixture(scope="module", autouse=True)
def setup():
    wait_for_service()


def test_missing_token():
    payload = {"user": "alice", "script_name": "deploy.sh"}
    response = requests.post(ENDPOINT, json=payload, timeout=2)
    assert response.status_code == 401, f"Expected HTTP 401 for missing token, got {response.status_code}. Response: {response.text}"


def test_incorrect_token():
    headers = {"Authorization": "Bearer WRONG-TOKEN"}
    payload = {"user": "alice", "script_name": "deploy.sh"}
    response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=2)
    assert response.status_code == 401, f"Expected HTTP 401 for incorrect token, got {response.status_code}. Response: {response.text}"


def test_valid_request_allow():
    headers = {"Authorization": f"Bearer {VALID_TOKEN}"}
    payload = {"user": "alice", "script_name": "deploy.sh"}
    response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("status") == "allow", f"Expected status 'allow', got {data}"


def test_privilege_escalation_attempt():
    headers = {"Authorization": f"Bearer {VALID_TOKEN}"}
    payload = {"user": "mallory", "script_name": "deploy.sh"}
    response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("status") == "deny", f"Expected status 'deny', got {data}"
    assert data.get("reason") == "escalation_attempt", f"Expected reason 'escalation_attempt', got {data}"


def test_checksum_mismatch():
    headers = {"Authorization": f"Bearer {VALID_TOKEN}"}
    payload = {"user": "alice", "script_name": "backdoor.sh"}
    response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("status") == "deny", f"Expected status 'deny', got {data}"
    assert data.get("reason") == "checksum_mismatch", f"Expected reason 'checksum_mismatch', got {data}"


def test_missing_file():
    headers = {"Authorization": f"Bearer {VALID_TOKEN}"}
    payload = {"user": "alice", "script_name": "nonexistent.sh"}
    response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("status") == "deny", f"Expected status 'deny', got {data}"
    assert data.get("reason") == "checksum_mismatch", f"Expected reason 'checksum_mismatch', got {data}"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    raise AssertionError("Could not identify the process listening on port 8080")


def restart_service():
    pid = listener_pid()
    procdir = Path(f"/proc/{pid}")
    args = procdir.joinpath("cmdline").read_bytes().rstrip(b"\0").split(b"\0")
    args = [a.decode(errors="surrogateescape") for a in args]
    cwd = os.readlink(procdir / "cwd")
    env = os.environ.copy()
    try:
        for item in procdir.joinpath("environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass

    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not Path(f"/proc/{pid}").exists():
            break
        time.sleep(0.1)
    if Path(f"/proc/{pid}").exists():
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.2)

    subprocess.Popen(
        args,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_service()


def assert_policy(token, user, script_name, status, reason=None):
    response = requests.post(
        ENDPOINT,
        headers={"Authorization": f"Bearer {token}"},
        json={"user": user, "script_name": script_name},
        timeout=3,
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("status") == status, data
    if reason is not None:
        assert data.get("reason") == reason, data


def test_randomized_policy_state_and_badge_are_actually_used():
    suffix = secrets.token_hex(8)
    clean_user = f"clean_{suffix}"
    blocked_user = f"blocked_{suffix}"
    good_name = f"good_{suffix}.sh"
    second_name = f"second_{suffix}.sh"
    bad_name = f"bad_{suffix}.sh"
    unlisted_name = f"unlisted_{suffix}.sh"
    missing_name = f"missing_{suffix}.sh"

    scripts = Path("/app/scripts")
    good_data = secrets.token_bytes(57)
    second_data = secrets.token_bytes(61)
    bad_data = secrets.token_bytes(43)
    (scripts / good_name).write_bytes(good_data)
    (scripts / second_name).write_bytes(second_data)
    (scripts / bad_name).write_bytes(bad_data)
    (scripts / unlisted_name).write_bytes(secrets.token_bytes(39))

    with open("/app/manifest.sha256", "a") as manifest:
        manifest.write(f"{hashlib.sha256(good_data).hexdigest()}  {good_name}\n")
        manifest.write(f"{hashlib.sha256(second_data).hexdigest()}  {second_name}\n")
        manifest.write(f"{'0' * 64}  {bad_name}\n")

    with open("/app/auth.log", "a") as auth_log:
        auth_log.write(
            f"Sep 11 11:22:33 server sudo: {blocked_user} : command not allowed ; "
            "TTY=pts/9 ; PWD=/tmp ; USER=root ; COMMAND=/bin/sh\n"
        )

    new_token = VALID_TOKEN
    while new_token == VALID_TOKEN:
        new_token = f"AUTH-{secrets.randbelow(900000) + 100000}"
    image = Image.new("RGB", (500, 150), color="white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 50)
    draw.text((20, 40), new_token, fill="black", font=font)
    image.save("/app/auth_badge.png")

    restart_service()

    response = requests.post(
        ENDPOINT,
        headers={"Authorization": f"Bearer {VALID_TOKEN}"},
        json={"user": clean_user, "script_name": good_name},
        timeout=3,
    )
    assert response.status_code == 401, "The token from the replaced badge was not enforced"

    assert_policy(new_token, clean_user, good_name, "allow")
    assert_policy(new_token, blocked_user, second_name, "deny", "escalation_attempt")
    assert_policy(new_token, clean_user, bad_name, "deny", "checksum_mismatch")
    assert_policy(new_token, clean_user, unlisted_name, "deny", "checksum_mismatch")
    assert_policy(new_token, clean_user, missing_name, "deny", "checksum_mismatch")
    assert_policy(new_token, blocked_user, missing_name, "deny", "escalation_attempt")

    (scripts / good_name).write_bytes(good_data + b"tampered")
    assert_policy(new_token, clean_user, good_name, "deny", "checksum_mismatch")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
