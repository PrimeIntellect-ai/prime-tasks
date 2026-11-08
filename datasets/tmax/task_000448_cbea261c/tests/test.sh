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
import stat
import time
import secrets
import subprocess

import pytest
import requests

LAB_DIR = "/home/user/forensics_lab"
EVIDENCE_ENC = os.path.join(LAB_DIR, "evidence.enc")
FIREWALL = os.path.join(LAB_DIR, "firewall.py")
NGINX_CONF = os.path.join(LAB_DIR, "nginx.conf")
DECRYPT = os.path.join(LAB_DIR, "decrypt.sh")
EXPECTED_ORIGINAL = "EVIDENCE_RECOVERED_C2_IP_10.10.10.55"
PROXY_URL = "http://127.0.0.1:8000/evidence"
NGINX_URL = "http://127.0.0.1:8080/evidence"
BACKEND_URL = "http://127.0.0.1:8081/evidence"


def assert_regular_file(path):
    assert os.path.exists(path), f"Required artifact is missing: {path}"
    assert not os.path.islink(path), f"Required artifact must not be a symlink: {path}"
    assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact is not a regular file: {path}"


def decrypt_with_reference(path):
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-k", "f0r3ns1cs!", "-in", path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            "Failed to decrypt the evidence file independently: "
            + exc.stderr.decode(errors="replace")
        )


def request(url, **kwargs):
    try:
        return requests.get(url, timeout=5, **kwargs)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to {url}. Are the required services running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")


def wait_for_backend():
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            response = requests.get(BACKEND_URL, timeout=0.5)
            if response.status_code in (200, 401):
                return
        except requests.RequestException:
            pass
        time.sleep(0.2)
    pytest.fail("Backend did not start on port 8081")


def start_artifacts():
    subprocess.run("pkill -f 'python3 backend.py' || true", shell=True)
    subprocess.run("pkill -f 'python3 firewall.py' || true", shell=True)
    subprocess.run("killall nginx 2>/dev/null || true", shell=True)
    time.sleep(0.5)

    subprocess.Popen(
        ["python3", BACKEND_URL.replace("http://127.0.0.1:8081/evidence", os.path.join(LAB_DIR, "backend.py"))],
        cwd=LAB_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_backend()

    nginx_check = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert nginx_check.returncode == 0, (
        "nginx.conf is invalid: " + nginx_check.stdout + nginx_check.stderr
    )
    nginx_start = subprocess.run(
        ["nginx", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert nginx_start.returncode == 0, (
        "Nginx failed to start: " + nginx_start.stdout + nginx_start.stderr
    )

    subprocess.Popen(
        ["python3", FIREWALL],
        cwd=LAB_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1)


def test_pipeline_end_to_end_and_artifacts():
    for path in (EVIDENCE_ENC, FIREWALL, NGINX_CONF, DECRYPT):
        assert_regular_file(path)

    # Preserve the original assertion, but anchor it to the immutable evidence truth.
    original_ciphertext = open(EVIDENCE_ENC, "rb").read()
    original_plaintext = decrypt_with_reference(EVIDENCE_ENC).decode().strip()
    assert original_plaintext == EXPECTED_ORIGINAL, (
        f"Original encrypted evidence was replaced or altered: {original_plaintext!r}"
    )

    headers = {"X-Forensics": "true"}
    cookies = {"Auth-Token": "admin_access"}

    # The agent was required to leave the repaired services running.
    initial = request(PROXY_URL, headers=headers, cookies=cookies)
    assert initial.status_code == 200, (
        f"Expected HTTP 200 OK, got {initial.status_code}. "
        f"Response body: {initial.text[:200]}"
    )
    assert initial.text.strip() == original_plaintext, (
        f"Decrypted evidence mismatch. Expected: {original_plaintext}, "
        f"Got: {initial.text.strip()}"
    )

    challenge = ("VERIFIER_CHALLENGE_" + secrets.token_hex(24) + "\n").encode()
    challenge_file = "/tmp/verifier_challenge_plaintext"
    with open(challenge_file, "wb") as stream:
        stream.write(challenge)

    subprocess.run("pkill -f 'python3 backend.py' || true", shell=True)
    subprocess.run("pkill -f 'python3 firewall.py' || true", shell=True)
    subprocess.run("killall nginx 2>/dev/null || true", shell=True)

    try:
        encrypted = subprocess.run(
            [
                "openssl", "enc", "-aes-256-cbc", "-pbkdf2",
                "-k", "f0r3ns1cs!", "-in", challenge_file,
                "-out", EVIDENCE_ENC,
            ],
            capture_output=True,
            text=True,
        )
        assert encrypted.returncode == 0, encrypted.stderr

        # Execute the submitted decrypt.sh on a fresh unpredictable ciphertext.
        decrypt_result = subprocess.run(
            ["bash", DECRYPT], cwd=LAB_DIR, capture_output=True
        )
        assert decrypt_result.returncode == 0, (
            "decrypt.sh failed: " + decrypt_result.stderr.decode(errors="replace")
        )
        assert decrypt_result.stdout == challenge, (
            "decrypt.sh did not decrypt the verifier-generated evidence to STDOUT"
        )

        # Start the submitted artifacts, then exercise each actual pipeline layer.
        start_artifacts()

        backend_unauthorized = request(BACKEND_URL)
        assert backend_unauthorized.status_code == 401
        backend_ok = request(BACKEND_URL, cookies=cookies)
        assert backend_ok.status_code == 200
        assert backend_ok.content == challenge

        nginx_unauthorized = request(NGINX_URL)
        assert nginx_unauthorized.status_code == 401
        nginx_ok = request(NGINX_URL, cookies=cookies)
        assert nginx_ok.status_code == 200
        assert nginx_ok.content == challenge, "Nginx did not preserve the Cookie header"

        proxy_unauthorized = request(PROXY_URL, headers=headers)
        assert proxy_unauthorized.status_code == 401
        proxy_ok = request(PROXY_URL, headers=headers, cookies=cookies)
        assert proxy_ok.status_code == 200, (
            f"Firewall rejected or failed to forward X-Forensics: true: {proxy_ok.status_code}"
        )
        assert proxy_ok.content == challenge
    finally:
        with open(EVIDENCE_ENC, "wb") as stream:
            stream.write(original_ciphertext)
        try:
            os.remove(challenge_file)
        except FileNotFoundError:
            pass

    # Services remain running and must now serve the restored original evidence.
    restored = request(PROXY_URL, headers=headers, cookies=cookies)
    assert restored.status_code == 200
    assert restored.text.strip() == EXPECTED_ORIGINAL
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
