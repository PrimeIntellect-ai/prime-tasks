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
import json
import secrets

import cv2
import numpy as np
import pytest
import requests
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

BASE_URL = "http://127.0.0.1:8000/api/v1/evidence"


def recover_expected_evidence():
    cap = cv2.VideoCapture("/app/security_cam.mp4")
    assert cap.isOpened(), "Could not open /app/security_cam.mp4"

    red_frame_count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        assert frame.shape[0] >= 10 and frame.shape[1] >= 10
        block = frame[0:10, 0:10]
        blue = block[:, :, 0]
        green = block[:, :, 1]
        red = block[:, :, 2]
        # MP4 compression can slightly perturb the encoded RGB values.
        red_pixels = (red >= 200) & (green <= 60) & (blue <= 60)
        if np.count_nonzero(red_pixels) >= 95:
            red_frame_count += 1
    cap.release()

    key = hashlib.sha256(f"PIN:{red_frame_count}".encode("utf-8")).digest()
    with open("/app/evidence.enc", "rb") as evidence_file:
        encrypted = evidence_file.read()

    assert len(encrypted) >= 32 and (len(encrypted) - 16) % 16 == 0
    iv, ciphertext = encrypted[:16], encrypted[16:]
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()

    pad_len = padded[-1]
    assert 1 <= pad_len <= 16
    assert padded[-pad_len:] == bytes([pad_len]) * pad_len
    document = json.loads(padded[:-pad_len].decode("utf-8"))

    assert set(document) == {"auth_token", "recovered_data"}
    assert isinstance(document["auth_token"], str)
    return document["auth_token"], document["recovered_data"]


VALID_TOKEN, EXPECTED_DATA = recover_expected_evidence()


def get_evidence(headers=None):
    try:
        return requests.get(BASE_URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API at {BASE_URL}: {exc}")


def test_api_valid_token():
    """Verify the API returns the decrypted data with the recovered token."""
    response = get_evidence({"Authorization": f"Bearer {VALID_TOKEN}"})
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        json_data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse. Response: {response.text}")
    assert json_data == EXPECTED_DATA, f"Expected data {EXPECTED_DATA}, but got {json_data}"


def test_api_invalid_token():
    """Retain the original explicit invalid-token assertion."""
    response = get_evidence({"Authorization": "Bearer invalid_token"})
    assert response.status_code == 401, (
        f"Expected status code 401 for invalid token, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_api_random_and_near_match_invalid_tokens():
    """Reject arbitrary incorrect credentials, including near-matches."""
    invalid_tokens = [
        VALID_TOKEN + "x",
        "x" + VALID_TOKEN,
        VALID_TOKEN[:-1] if VALID_TOKEN else "x",
    ]
    while len(invalid_tokens) < 19:
        candidate = secrets.token_urlsafe(32)
        if candidate != VALID_TOKEN:
            invalid_tokens.append(candidate)

    for token in invalid_tokens:
        response = get_evidence({"Authorization": f"Bearer {token}"})
        assert response.status_code == 401, (
            f"Expected 401 for incorrect bearer token {token!r}, got "
            f"{response.status_code}. Response: {response.text}"
        )


def test_api_missing_token():
    """Verify the API returns 401 Unauthorized when the token is missing."""
    response = get_evidence()
    assert response.status_code == 401, (
        f"Expected status code 401 for missing token, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_api_malformed_or_wrong_auth_scheme():
    for authorization in ("Bearer", "Basic " + VALID_TOKEN, "Token " + VALID_TOKEN):
        response = get_evidence({"Authorization": authorization})
        assert response.status_code == 401, (
            f"Expected 401 for Authorization {authorization!r}, got "
            f"{response.status_code}. Response: {response.text}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
