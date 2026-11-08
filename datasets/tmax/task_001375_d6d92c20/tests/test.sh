#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import secrets
import string
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/process"


def encode_payload(text: str) -> str:
    # Shift +3 to simulate the input that will be unshifted (-3) by the service.
    shifted = bytes((b + 3) % 256 for b in text.encode("utf-8"))
    return base64.b64encode(shifted).decode("ascii")


def expected_sanitizations(text: str):
    expected = text.replace("&", "&amp;") \
                   .replace("<", "&lt;") \
                   .replace(">", "&gt;") \
                   .replace("\"", "&quot;") \
                   .replace("'", "&#x27;")
    alternate = text.replace("&", "&amp;") \
                    .replace("<", "&lt;") \
                    .replace(">", "&gt;") \
                    .replace("\"", "&quot;") \
                    .replace("'", "&#39;")
    return expected, alternate


def assert_processed(payload: str, original_text: str):
    try:
        response = requests.post(URL, json={"payload": payload}, timeout=3)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {URL}: {exc}")

    assert response.status_code == 200, \
        f"Expected status code 200, got {response.status_code}"

    try:
        resp_json = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "status" in resp_json, "Response JSON missing 'status' key"
    assert resp_json["status"] == "success", \
        f"Expected status 'success', got {resp_json['status']}"
    assert "safe_log" in resp_json, "Response JSON missing 'safe_log' key"

    expected, alternate = expected_sanitizations(original_text)
    actual = resp_json["safe_log"]
    assert isinstance(actual, str), "safe_log must be a JSON string"
    assert actual in (expected, alternate), \
        f"Sanitization failed. Expected '{expected}' or '{alternate}', got '{actual}'"


def listening_processes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                rows = handle.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if port == 8080:
                    inodes.add(fields[9])

    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        owns_socket = False
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owns_socket = True
                break
        if owns_socket:
            try:
                exe = os.readlink(f"/proc/{pid}/exe")
            except OSError:
                exe = ""
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as handle:
                    cmdline = handle.read().replace(b"\0", b" ").decode("utf-8", "replace")
            except OSError:
                cmdline = ""
            owners.append((pid, exe, cmdline))
    return owners


def test_python_service_is_listening():
    # The requested replacement is specifically a Python HTTP service.
    owners = listening_processes()
    assert owners, "No process is listening on port 8080"
    assert any("python" in (exe + " " + cmd).lower() for _, exe, cmd in owners), \
        f"The port 8080 listener is not a Python service: {owners}"


def test_service_processing():
    # Retain the original verifier's cases and assertions.
    test_cases = [
        "Normal log entry without special chars",
        "<script>alert(\"XSS & 'injection'\")</script>",
        "Another test < > & \" '",
    ]
    for original_text in test_cases:
        assert_processed(encode_payload(original_text), original_text)


def test_randomized_binary_compatible_processing():
    # Generate fresh cases at verification time so fixed response tables cannot pass.
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + string.punctuation + " \t" \
               + "éΩ中🙂"

    cases = [
        "dynamic-" + secrets.token_hex(24),
        "<&'\">" + secrets.token_urlsafe(31) + "<&'\">",
        "~}|{" + secrets.token_hex(12) + " éΩ中🙂",
    ]
    for _ in range(15):
        length = rng.randint(20, 180)
        text = "".join(rng.choice(alphabet) for _ in range(length))
        # Ensure every randomized case exercises all required HTML escapes.
        insert_at = rng.randint(0, len(text))
        cases.append(text[:insert_at] + "<&'\">" + text[insert_at:])

    for original_text in cases:
        payload = encode_payload(original_text)

        # Confirm each fresh expected plaintext against the recovered executable,
        # rather than trusting a response or a fixed table.
        recovered = subprocess.run(
            ["/app/log_processor", payload],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
            check=True,
        ).stdout.decode("utf-8")
        assert recovered == original_text, "Generated oracle case did not match the binary"
        assert_processed(payload, recovered)


def test_payload_cannot_trigger_original_shell_injection():
    # The recovered binary interpolates its argument into a shell command. A secure
    # replacement must decode data itself and must not pass attacker input to it.
    marker = f"/tmp/verifier_injection_{secrets.token_hex(16)}"
    malicious_payload = f"'; /usr/bin/touch {marker}; printf '"
    try:
        try:
            requests.post(URL, json={"payload": malicious_payload}, timeout=3)
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.3)
        assert not os.path.exists(marker), \
            "The service passed attacker-controlled payload data into a shell"

        # The malformed request must not have killed the replacement service.
        probe = "post-injection-health-" + secrets.token_hex(16)
        assert_processed(encode_payload(probe), probe)
    finally:
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
