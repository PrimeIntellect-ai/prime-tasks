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

BACKUP=/tmp/secure_quota_check.sh.verifier-backup
cp -a /app/secure_quota_check.sh "$BACKUP"
restore_quota_tool() {
    cp -a "$BACKUP" /app/secure_quota_check.sh
}
trap restore_quota_tool EXIT

DYNAMIC_USAGE=$(python3 - <<'PY'
import secrets
print(secrets.randbelow(800000) + 100000)
PY
)
export DYNAMIC_USAGE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import re
import secrets
import subprocess

import pytest
import requests

PORT = 8192
TOKEN = "AlphaTango!44"
BASE_URL = f"http://127.0.0.1:{PORT}"
LOG_FILE = "/home/user/alerts.log"
TOOL = "/app/secure_quota_check.sh"
DYNAMIC_USAGE = int(os.environ["DYNAMIC_USAGE"])
MARKER = "/tmp/quota_challenge_invocations"


def get(path, **kwargs):
    try:
        return requests.get(f"{BASE_URL}{path}", timeout=5, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to GET {path}: {exc}")


def post(path, **kwargs):
    try:
        return requests.post(f"{BASE_URL}{path}", timeout=5, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to POST {path}: {exc}")


def assert_poll_response(response, usage):
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /poll, got: {response.text}")
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("usage") == usage, f"Expected usage {usage}, got {data.get('usage')}"


def install_challenge_tool():
    script = f'''#!/bin/bash
echo -n "Enter monitoring password: "
IFS= read -r -s password
echo
if [ "$password" != "mon_alert_99" ]; then
    echo "Authentication failed."
    exit 1
fi
p=$PPID
found_expect=0
for _ in 1 2 3 4 5; do
    [ -r "/proc/$p/status" ] || break
    comm=$(cat "/proc/$p/comm" 2>/dev/null || true)
    exe=$(readlink "/proc/$p/exe" 2>/dev/null || true)
    case "$comm:$exe" in
        *expect*|*Expect*) found_expect=1; break ;;
    esac
    p=$(awk '/^PPid:/ {{print $2}}' "/proc/$p/status" 2>/dev/null)
    [ -n "$p" ] || break
done
if [ "$found_expect" -ne 1 ]; then
    echo "Authentication failed."
    exit 1
fi
echo "$PPID" >> "{MARKER}"
echo "DISK_USAGE={DYNAMIC_USAGE}"
'''
    pathlib.Path(TOOL).write_text(script)
    os.chmod(TOOL, 0o755)
    pathlib.Path(MARKER).unlink(missing_ok=True)


def find_expect_scripts():
    roots = ["/app", "/home/user", "/root", "/opt", "/usr/local/bin", "/tmp"]
    matches = []
    ignored = {TOOL, "/tmp/test_final_state.py"}
    for root in roots:
        if not os.path.exists(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {".cache", ".git", "__pycache__", "site-packages"}]
            for name in files:
                path = os.path.join(directory, name)
                if path in ignored:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    text = pathlib.Path(path).read_text(errors="ignore")
                except (OSError, UnicodeError):
                    continue
                lowered = text.lower()
                if ("/app/secure_quota_check.sh" in text
                        and re.search(r"(^|[;\n\r])\s*spawn\b", lowered)
                        and re.search(r"(^|[;\n\r])\s*expect\b", lowered)
                        and "enter monitoring password" in lowered
                        and "mon_alert_99" in text):
                    matches.append(path)
    return matches


def test_01_poll_endpoint_original_assertions():
    assert_poll_response(get("/poll"), 8492)


def test_02_alert_endpoint_unauthorized_original_assertions():
    response = post("/alert", json={"test": "data"})
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"

    response = post(
        "/alert",
        headers={"Authorization": "Bearer WrongToken"},
        json={"test": "data"},
    )
    assert response.status_code == 401, f"Expected 401 for invalid auth, got {response.status_code}"


def test_03_alert_endpoint_authorized_original_assertions():
    payload = {"message": "Disk space critical test"}
    response = post(
        "/alert",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json=payload,
    )
    assert response.status_code == 200, f"Expected 200 for valid auth, got {response.status_code}"
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} was not created"
    with open(LOG_FILE, "r") as handle:
        log_content = handle.read()
    assert "Disk space critical test" in log_content, f"Expected payload not found in {LOG_FILE}"


def test_04_expect_artifact_and_dynamic_poll():
    install_challenge_tool()
    candidates = find_expect_scripts()
    assert candidates, "No expect script automating /app/secure_quota_check.sh was found"

    working = []
    for candidate in candidates:
        pathlib.Path(MARKER).unlink(missing_ok=True)
        try:
            result = subprocess.run(
                ["/usr/bin/expect", candidate],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=7,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if (result.returncode == 0
                and re.search(rf"DISK_USAGE\s*=\s*{DYNAMIC_USAGE}\b", result.stdout)
                and pathlib.Path(MARKER).exists()):
            working.append(candidate)
    assert working, "The expect artifact did not successfully authenticate and expose the tool output"

    pathlib.Path(MARKER).unlink(missing_ok=True)
    assert_poll_response(get("/poll"), DYNAMIC_USAGE)
    assert pathlib.Path(MARKER).exists(), "/poll did not invoke the interactive quota tool through expect"


def test_05_alert_appends_arbitrary_raw_bodies_as_lines():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    pathlib.Path(LOG_FILE).touch()
    current = pathlib.Path(LOG_FILE).read_bytes()
    if current and not current.endswith(b"\n"):
        with open(LOG_FILE, "ab") as handle:
            handle.write(b"\n")

    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    }
    nonce = secrets.token_hex(18)
    bodies = [
        json.dumps({"nonce": nonce, "level": 7}, separators=(",", ":")).encode(),
        (f'{{  "second" : "{nonce[::-1]}", "enabled" : true }}').encode(),
    ]

    for body in bodies:
        before = pathlib.Path(LOG_FILE).read_bytes()
        response = post("/alert", headers=headers, data=body)
        assert response.status_code == 200, f"Expected 200 for valid auth, got {response.status_code}"
        after = pathlib.Path(LOG_FILE).read_bytes()
        assert after == before + body + b"\n", "Authorized raw POST body was not appended exactly as a new line"

    before = pathlib.Path(LOG_FILE).read_bytes()
    rejected = post(
        "/alert",
        headers={"Authorization": f"Bearer {TOKEN}x", "Content-Type": "application/json"},
        data=b'{"must_not_be_logged":true}',
    )
    assert rejected.status_code == 401, f"Expected 401 for invalid auth, got {rejected.status_code}"
    assert pathlib.Path(LOG_FILE).read_bytes() == before, "Unauthorized payload modified the alert log"
TEST_EOF

passed=0
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=1
fi

restore_quota_tool
trap - EXIT
echo "$passed" > /logs/verifier/reward.txt
