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
import json
import os
import stat

import pytest
import requests


def expected_findings():
    web_root = "/home/user/web_root"
    expected_insecure = []
    if os.path.exists(web_root):
        for root, dirs, files in os.walk(web_root):
            for filename in files:
                full_path = os.path.join(root, filename)
                if os.stat(full_path).st_mode & stat.S_IWOTH:
                    expected_insecure.append(full_path)

    return {
        "attacker_ip": "10.0.0.15",
        "compromised_user": "alice_admin",
        "insecure_files": sorted(expected_insecure),
    }


def test_findings_json():
    findings_path = "/home/user/findings.json"
    assert os.path.isfile(findings_path), f"Findings file missing: {findings_path}"

    with open(findings_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {findings_path} is not valid JSON")

    expected = expected_findings()
    assert data.get("attacker_ip") == expected["attacker_ip"], f"Incorrect attacker_ip: {data.get('attacker_ip')}"
    assert data.get("compromised_user") == expected["compromised_user"], f"Incorrect compromised_user: {data.get('compromised_user')}"

    actual_insecure = sorted(data.get("insecure_files", []))
    assert actual_insecure == expected["insecure_files"], (
        f"Incorrect insecure_files. Expected {expected['insecure_files']}, got {actual_insecure}"
    )


def test_bash_reporting_script_exists():
    roots = ["/home/user", "/app", "/root", "/tmp", "/workspace", "/opt", "/usr/local/bin"]
    required_markers = [b"8080", b"/report", b"Incident-Resp-2024", b"REPORT_RECEIVED"]
    candidates = []

    for search_root in roots:
        if not os.path.exists(search_root):
            continue
        for root, dirs, files in os.walk(search_root):
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
            for filename in files:
                path = os.path.join(root, filename)
                if path == "/tmp/test_final_state.py" or path.startswith("/tests/"):
                    continue
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        content = f.read()
                except OSError:
                    continue

                first_line = content.splitlines()[0] if content.splitlines() else b""
                is_bash = first_line.startswith(b"#!/bin/bash") or first_line.startswith(b"#!/usr/bin/env bash")
                if is_bash and all(marker in content for marker in required_markers):
                    candidates.append(path)

    assert candidates, (
        "No Bash reporting-service script was found containing the required port, route, "
        "authorization token, and response body"
    )


def request_or_fail(method, url, **kwargs):
    kwargs.setdefault("timeout", 5)
    try:
        return requests.request(method, url, **kwargs)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to communicate with reporting service for {method} {url}: {exc}")


def assert_rejected(response, description):
    assert response.status_code != 200, (
        f"{description} was incorrectly accepted with HTTP 200. Response: {response.text}"
    )
    assert "REPORT_RECEIVED" not in response.text, (
        f"{description} incorrectly returned the success body"
    )


def test_reporting_service():
    base = "http://127.0.0.1:8080"
    url = base + "/report"
    token_headers = {
        "Authorization": "Bearer Incident-Resp-2024",
        "Content-Type": "application/json",
        "Connection": "close",
    }
    payload = expected_findings()

    # Authorization must be present and exact.
    response = request_or_fail(
        "POST", url,
        headers={"Content-Type": "application/json", "Connection": "close"},
        json=payload,
    )
    assert_rejected(response, "POST without Authorization")

    response = request_or_fail(
        "POST", url,
        headers={
            "Authorization": "Bearer wrong-token",
            "Content-Type": "application/json",
            "Connection": "close",
        },
        json=payload,
    )
    assert_rejected(response, "POST with an incorrect Authorization token")

    # A body must be valid JSON and must contain the findings.
    response = request_or_fail("POST", url, headers=token_headers, data=b"")
    assert_rejected(response, "POST with no JSON body")

    response = request_or_fail("POST", url, headers=token_headers, data=b"{not valid json")
    assert_rejected(response, "POST with malformed JSON")

    response = request_or_fail("POST", url, headers=token_headers, json={})
    assert_rejected(response, "POST with JSON that does not contain the findings")

    incorrect_payload = dict(payload)
    incorrect_payload["attacker_ip"] = "192.0.2.1"
    response = request_or_fail("POST", url, headers=token_headers, json=incorrect_payload)
    assert_rejected(response, "POST containing incorrect findings")

    # Only POST /report is accepted.
    response = request_or_fail("GET", url, headers=token_headers)
    assert_rejected(response, "GET /report")

    response = request_or_fail("PUT", url, headers=token_headers, json=payload)
    assert_rejected(response, "PUT /report")

    response = request_or_fail("POST", base + "/", headers=token_headers, json=payload)
    assert_rejected(response, "POST to an unrelated path")

    response = request_or_fail("POST", base + "/report/extra", headers=token_headers, json=payload)
    assert_rejected(response, "POST to a path other than /report")

    # Preserve the original positive behavior check.
    response = request_or_fail("POST", url, headers=token_headers, json=payload)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    assert "REPORT_RECEIVED" in response.text, (
        f"Expected 'REPORT_RECEIVED' in response body, got: {response.text}"
    )
    assert response.text.strip() == "REPORT_RECEIVED", (
        f"Expected exact response body 'REPORT_RECEIVED', got: {response.text!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
