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
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests


def derive_expected_values():
    video = Path("/app/intercept.mp4")
    assert video.is_file(), f"Missing intercepted video: {video}"

    qr_text = None
    with tempfile.TemporaryDirectory() as temp_dir:
        for index, timestamp in enumerate(("0", "0.25", "0.5", "0.75")):
            frame = Path(temp_dir) / f"frame-{index}.png"
            extracted = subprocess.run(
                [
                    "ffmpeg", "-loglevel", "error", "-y", "-ss", timestamp,
                    "-i", str(video), "-frames:v", "1", str(frame),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if extracted.returncode != 0 or not frame.is_file():
                continue

            decoded = subprocess.run(
                ["zbarimg", "--quiet", "--raw", str(frame)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if decoded.returncode == 0 and "HASH:" in decoded.stdout and "DATA:" in decoded.stdout:
                qr_text = decoded.stdout
                break

    assert qr_text is not None, "Could not decode a QR code from /app/intercept.mp4"

    hash_match = re.search(r"^HASH:([0-9a-fA-F]{64})\s*$", qr_text, re.MULTILINE)
    data_match = re.search(r"^DATA:([A-Za-z0-9+/=]+)\s*$", qr_text, re.MULTILINE)
    assert hash_match, "Decoded QR code does not contain a valid HASH line"
    assert data_match, "Decoded QR code does not contain a valid DATA line"

    expected_hash = hash_match.group(1).lower()
    pin = next(
        (
            candidate
            for number in range(10000)
            for candidate in (f"{number:04d}",)
            if hashlib.sha256(candidate.encode()).hexdigest() == expected_hash
        ),
        None,
    )
    assert pin is not None, "No four-digit PIN matches the QR code's SHA-256 hash"

    decrypted = subprocess.run(
        [
            "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-a",
            "-pass", f"pass:{pin}",
        ],
        input=data_match.group(1) + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert decrypted.returncode == 0, f"Failed to decrypt QR DATA: {decrypted.stderr}"

    plaintext_match = re.fullmatch(
        r"PORT=([0-9]+);TOKEN=([^;\r\n]+);PAYLOAD=(.*)",
        decrypted.stdout,
        re.DOTALL,
    )
    assert plaintext_match, "Decrypted data is not in PORT=...;TOKEN=...;PAYLOAD=... format"

    port = int(plaintext_match.group(1))
    assert 1 <= port <= 65535, f"Decrypted port is invalid: {port}"
    return port, plaintext_match.group(2), plaintext_match.group(3)


PORT, TOKEN, PAYLOAD = derive_expected_values()
URL = f"http://127.0.0.1:{PORT}/download"


def request(headers=None):
    try:
        return requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(
            f"Failed to connect to the server at {URL}. "
            f"Ensure the server is running on port {PORT}. Error: {exc}"
        )


def test_server_responds_with_correct_payload():
    response = request({"X-Auth": TOKEN})
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"
    )
    assert response.text.strip() == PAYLOAD, (
        f"Expected payload {PAYLOAD!r}, got {response.text!r}"
    )


def test_server_rejects_missing_header():
    response = request()
    assert response.status_code == 403, (
        f"Expected HTTP 403 Forbidden for missing header, got {response.status_code}. "
        f"Response body: {response.text}"
    )


def invalid_tokens():
    values = ["InvalidToken123"]
    values.extend(f"invalid-{secrets.token_hex(16)}" for _ in range(8))
    if TOKEN:
        values.extend([TOKEN + "x", "x" + TOKEN, TOKEN.swapcase()])
    return list(dict.fromkeys(value for value in values if value != TOKEN))


@pytest.mark.parametrize("invalid_token", invalid_tokens())
def test_server_rejects_incorrect_header(invalid_token):
    response = request({"X-Auth": invalid_token})
    assert response.status_code == 403, (
        f"Expected HTTP 403 Forbidden for incorrect X-Auth value {invalid_token!r}, "
        f"got {response.status_code}. Response body: {response.text}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
