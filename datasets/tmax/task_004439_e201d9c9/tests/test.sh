#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import secrets
import random
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/detect_attacks.py"
JSON_PATH = "/home/user/http_traffic.json"
LOG_PATH = "/home/user/alerts.log"


def get_expected_alerts(json_path):
    with open(json_path, 'r') as f:
        data = json.load(f)

    expected_alerts = []
    for req in data:
        ip = req.get("ip", "")
        path = req.get("path", "")

        # Rule 1: CWE-22
        if "../" in path or "%2E%2E%2F" in path:
            expected_alerts.append(f"{ip} - CWE-22")

        # Rule 2: CWE-269
        headers = req.get("headers", {})
        cookie = headers.get("Cookie", "")
        if "session=" in cookie:
            session_val = cookie.split("session=")[1].split(";")[0]
            try:
                decoded = base64.b64decode(session_val).decode('utf-8')
                session_data = json.loads(decoded)
                role = session_data.get("role")
                if role in ["admin", "administrator"]:
                    expected_alerts.append(f"{ip} - CWE-269")
            except Exception:
                pass

    return expected_alerts


def test_alerts_log_exists():
    """Check if the alerts.log file was created."""
    assert os.path.exists(LOG_PATH), f"{LOG_PATH} does not exist."
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is not a file."


def test_alerts_log_content():
    """Check if the alerts.log contains the correct flagged requests."""
    assert os.path.exists(JSON_PATH), f"Source file {JSON_PATH} is missing."
    assert os.path.exists(LOG_PATH), f"Output file {LOG_PATH} is missing."

    expected_alerts = get_expected_alerts(JSON_PATH)

    with open(LOG_PATH, 'r') as f:
        actual_alerts = [line.strip() for line in f if line.strip()]

    assert actual_alerts == expected_alerts, (
        f"Contents of {LOG_PATH} do not match the expected output.\n"
        f"Expected: {expected_alerts}\n"
        f"Actual: {actual_alerts}"
    )


def test_script_exists():
    """Check if the script was created."""
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def encode_session(role):
    payload = {
        "user": "user-" + secrets.token_hex(8),
        "role": role,
        "nonce": secrets.token_hex(12),
    }
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def make_behavioral_input():
    prefix = "/" + secrets.token_hex(8)
    cases = [
        (prefix + "/safe", "session=" + encode_session("user")),
        (prefix + "/a/../b/" + secrets.token_hex(3), "session=" + encode_session("guest")),
        (prefix + "/%2E%2E%2Fprivate/" + secrets.token_hex(3), "session=" + encode_session("admin")),
        (prefix + "/account/" + secrets.token_hex(3), "session=" + encode_session("admin")),
        (prefix + "/settings/" + secrets.token_hex(3), "theme=dark; session=" + encode_session("administrator")),
        (prefix + "/ordinary/" + secrets.token_hex(3), "session=" + encode_session("Admin")),
        (prefix + "/malformed/" + secrets.token_hex(3), "session=not-valid-base64^&*"),
        (prefix + "/no-cookie/" + secrets.token_hex(3), None),
    ]
    random.SystemRandom().shuffle(cases)

    requests = []
    for index, (path, cookie) in enumerate(cases):
        headers = {"User-Agent": "Verifier/" + secrets.token_hex(4)}
        if cookie is not None:
            headers["Cookie"] = cookie
        requests.append({
            "ip": f"198.51.{secrets.randbelow(100) + 1}.{index + 20}",
            "method": random.SystemRandom().choice(["GET", "POST"]),
            "path": path,
            "headers": headers,
        })
    return requests


def test_script_behavior_on_fresh_inputs():
    """Execute the submitted script against unpredictable inputs."""
    with open(JSON_PATH, "rb") as f:
        original_json = f.read()
    original_log_exists = os.path.exists(LOG_PATH)
    original_log = None
    if original_log_exists:
        with open(LOG_PATH, "rb") as f:
            original_log = f.read()

    try:
        for _ in range(2):
            requests = make_behavioral_input()
            with open(JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(requests, f)
            expected = get_expected_alerts(JSON_PATH)

            if os.path.lexists(LOG_PATH):
                os.remove(LOG_PATH)

            result = subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Detector exited with status {result.returncode}.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(LOG_PATH), "Detector did not create alerts.log."

            with open(LOG_PATH, "r", encoding="utf-8") as f:
                actual = [line.strip() for line in f if line.strip()]
            assert actual == expected, (
                "Detector produced incorrect alerts on a fresh input.\n"
                f"Expected: {expected}\nActual: {actual}"
            )

            with open(JSON_PATH, "r", encoding="utf-8") as f:
                assert json.load(f) == requests, "Detector modified the input traffic file."
    finally:
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)
        if original_log_exists:
            with open(LOG_PATH, "wb") as f:
                f.write(original_log)
        elif os.path.lexists(LOG_PATH):
            os.remove(LOG_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
