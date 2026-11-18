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
import os
import secrets
import stat
import subprocess
import sys
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
UPLOAD_ROOT = Path("/app/uploads").resolve()


def request(method, path, **kwargs):
    try:
        return requests.request(method, BASE_URL + path, timeout=5, allow_redirects=False, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL + path}. Are the services running? Error: {exc}")


def test_security_headers():
    response = request("GET", "/")
    headers = response.headers

    sts = headers.get("Strict-Transport-Security", "")
    assert "max-age=31536000" in sts, f"Strict-Transport-Security header missing or incorrect max-age. Got: '{sts}'"
    assert "includeSubDomains" in sts.replace(" ", ""), f"Strict-Transport-Security header missing includeSubDomains. Got: '{sts}'"

    xcto = headers.get("X-Content-Type-Options", "")
    assert xcto.lower() == "nosniff", f"X-Content-Type-Options header missing or incorrect. Got: '{xcto}'"


def test_cookie_security():
    response = request("GET", "/login")
    try:
        cookies = response.raw.headers.getlist("Set-Cookie")
    except AttributeError:
        value = response.headers.get("Set-Cookie", "")
        cookies = [value] if value else []

    assert cookies, "/login did not return the backend's expected Set-Cookie header"
    for cookie in cookies:
        lower = cookie.lower()
        assert "secure" in lower, f"Set-Cookie header missing Secure flag. Got: '{cookie}'"
        assert "httponly" in lower, f"Set-Cookie header missing HttpOnly flag. Got: '{cookie}'"


def files_containing(marker):
    matches = []
    for root, dirs, files in os.walk(UPLOAD_ROOT, followlinks=False):
        for name in files:
            path = Path(root) / name
            try:
                if path.read_bytes() == marker:
                    matches.append(path)
            except OSError:
                pass
    return matches


def test_path_traversal_mitigation():
    token = secrets.token_hex(12)

    safe_name = f"safe-{token}.txt"
    safe_path = UPLOAD_ROOT / safe_name
    safe_content = ("safe-" + token).encode()
    safe_path.unlink(missing_ok=True)
    response = request("POST", "/upload", files={"file": (safe_name, safe_content)})
    assert response.status_code == 200, f"A normal upload failed with status {response.status_code}"
    assert safe_path.is_file(), f"Normal upload was not saved at {safe_path}"
    assert safe_path.read_bytes() == safe_content, "Normal upload content was not saved correctly"

    cases = [
        (f"../../../tmp/{token}.txt", Path(f"/tmp/{token}.txt")),
        (f"/tmp/{token}-absolute.txt", Path(f"/tmp/{token}-absolute.txt")),
        (f"../{token}-parent.txt", Path(f"/app/{token}-parent.txt")),
    ]

    for index, (filename, outside_path) in enumerate(cases):
        marker = f"traversal-{token}-{index}".encode()
        outside_path.unlink(missing_ok=True)
        response = request("POST", "/upload", files={"file": (filename, marker)})

        assert not outside_path.exists(), f"Path traversal successful: {filename!r} wrote to {outside_path}"
        matches = files_containing(marker)
        for saved_path in matches:
            resolved = saved_path.resolve()
            assert resolved == UPLOAD_ROOT or UPLOAD_ROOT in resolved.parents, f"Upload escaped the upload directory via {saved_path}"
        if response.status_code < 400:
            assert matches, f"Upload of {filename!r} reported success but was not safely saved under {UPLOAD_ROOT}"

    safe_path.unlink(missing_ok=True)


def run_detector(script_path, output_path):
    output_path.unlink(missing_ok=True)
    result = subprocess.run(
        [sys.executable, str(script_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Detection script failed with exit code {result.returncode}: {result.stderr}"
    assert output_path.is_file(), f"File {output_path} does not exist. The intrusion detection script may not have run or failed to output to the correct location."
    return [line.strip() for line in output_path.read_text().splitlines() if line.strip()]


def test_compromised_ips_file_and_detector():
    script_path = Path("/home/user/detect_traversal.py")
    output_path = Path("/home/user/compromised_ips.txt")
    log_path = Path("/app/logs/access.log")

    assert script_path.is_file(), f"Required detection script {script_path} does not exist"
    assert stat.S_ISREG(script_path.stat().st_mode), f"{script_path} is not a regular file"

    content = run_detector(script_path, output_path)
    expected_ips = ["10.0.0.42", "172.16.0.100", "192.168.1.55"]
    assert content == expected_ips, f"Expected IPs {expected_ips}, but got {content} in {output_path}. Ensure IPs are sorted and deduplicated."

    original_log = log_path.read_bytes()
    random_ips = [
        f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}",
        f"172.{secrets.randbelow(15) + 16}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}",
        f"192.0.2.{secrets.randbelow(250) + 1}",
    ]
    benign_ip = f"198.51.100.{secrets.randbelow(250) + 1}"
    payloads = [
        "/private/../secret.txt",
        "/download?file=%2e%2e%2fetc%2fpasswd",
        "/api?path=..%2F..%2Fvar%2Flog",
    ]

    lines = []
    for ip, uri in zip(random_ips, payloads):
        lines.append(f'{ip} - - [11/Sep/2026:12:00:00 +0000] "GET {uri} HTTP/1.1" 400 12 "-" "audit"')
    lines.append(f'{random_ips[0]} - - [11/Sep/2026:12:00:01 +0000] "POST /upload?name=../again HTTP/1.1" 403 7 "-" "audit"')
    lines.append(f'{benign_ip} - - [11/Sep/2026:12:00:02 +0000] "GET /docs/v1.2/index.html HTTP/1.1" 200 20 "-" "benign ../ user-agent"')

    try:
        with log_path.open("w") as log_file:
            log_file.write("\n".join(lines) + "\n")
        dynamic_content = run_detector(script_path, output_path)
        dynamic_expected = sorted(set(random_ips))
        assert dynamic_content == dynamic_expected, f"Expected dynamically derived attacker IPs {dynamic_expected}, but got {dynamic_content}"
    finally:
        with log_path.open("wb") as log_file:
            log_file.write(original_log)

    restored_content = run_detector(script_path, output_path)
    assert restored_content == expected_ips, f"Expected IPs {expected_ips}, but got {restored_content} after restoring the access log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
