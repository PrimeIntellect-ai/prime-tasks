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
import base64
import hashlib
import json
import os
import re
import secrets
import string
import subprocess

import cv2
import numpy as np
import pytest
import pytesseract
import requests
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

URL = "http://127.0.0.1:8080/report"
KEY = b"0123456789abcdef0123456789abcdef"
IV = b"abcdef9876543210"


def recover_token_from_video():
    cap = cv2.VideoCapture("/app/surveillance_capture.mp4")
    assert cap.isOpened(), "Could not open surveillance capture"
    frames = []
    for index in range(120, 151):
        cap.set(cv2.CAP_PROP_POS_FRAMES, index)
        ok, frame = cap.read()
        if ok:
            frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    cap.release()
    assert frames, "Could not read overlay frames 120-150"

    images = [frames[len(frames) // 2], np.median(np.stack(frames), axis=0).astype(np.uint8)]
    ocr_texts = []
    for image in images:
        for crop in (image, image[195:265, :]):
            enlarged = cv2.resize(crop, None, fx=5, fy=5, interpolation=cv2.INTER_CUBIC)
            variants = [enlarged]
            _, thresholded = cv2.threshold(enlarged, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            variants.extend([thresholded, cv2.bitwise_not(thresholded)])
            for variant in variants:
                for psm in (6, 7, 13):
                    text = pytesseract.image_to_string(
                        variant,
                        config=f"--psm {psm} -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",
                    )
                    ocr_texts.append(text)

    encoded_candidates = set()
    for text in ocr_texts:
        for run in re.findall(r"[A-Za-z0-9+/=]{24,80}", text.replace("\n", "")):
            run = run.rstrip("=")
            for start in range(len(run)):
                for end in range(start + 32, min(len(run), start + 64) + 1):
                    candidate = run[start:end]
                    candidate += "=" * ((-len(candidate)) % 4)
                    encoded_candidates.add(candidate)

    plaintext_candidates = set()
    for encoded in encoded_candidates:
        try:
            ciphertext = base64.b64decode(encoded, validate=True)
            if not ciphertext or len(ciphertext) % 16:
                continue
            decryptor = Cipher(algorithms.AES(KEY), modes.CBC(IV)).decryptor()
            padded = decryptor.update(ciphertext) + decryptor.finalize()
            unpadder = padding.PKCS7(128).unpadder()
            plaintext = unpadder.update(padded) + unpadder.finalize()
            decoded = plaintext.decode("utf-8")
            if len(decoded) >= 8 and all(ch in string.printable and ch not in "\r\n\t" for ch in decoded):
                # Re-encryption and canonical base64 verify the recovered ciphertext's integrity.
                padder = padding.PKCS7(128).padder()
                repadded = padder.update(plaintext) + padder.finalize()
                encryptor = Cipher(algorithms.AES(KEY), modes.CBC(IV)).encryptor()
                round_trip = encryptor.update(repadded) + encryptor.finalize()
                if round_trip == ciphertext:
                    plaintext_candidates.add(decoded)
        except Exception:
            pass

    assert len(plaintext_candidates) == 1, (
        "Failed to derive a unique authentication token from the video overlay; "
        f"found {len(plaintext_candidates)} candidates"
    )
    return plaintext_candidates.pop()


TOKEN = recover_token_from_video()


def post(token, payload):
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = token
    try:
        return requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")


def assert_valid_response(response, payload):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert data.get("status") == "analyzed", f"Expected status 'analyzed', got {data.get('status')}"
    assert data.get("redacted_email") == "[REDACTED]", (
        f"Expected redacted_email '[REDACTED]', got {data.get('redacted_email')}"
    )
    expected_hash = hashlib.sha256(payload["xss_payload"].encode("utf-8")).hexdigest()
    assert data.get("payload_hash") == expected_hash, (
        f"Expected payload_hash {expected_hash}, got {data.get('payload_hash')}"
    )
    assert payload["victim_email"] not in response.text, "Victim email was not completely redacted"


def test_repaired_decryptor_executes_and_reveals_video_token():
    path = "/home/user/decryptor.py"
    assert os.path.isfile(path), f"Expected repaired decryptor at {path}"
    result = subprocess.run(
        ["python3", path], capture_output=True, text=True, timeout=15, cwd="/home/user"
    )
    assert result.returncode == 0, f"decryptor.py failed: {result.stderr}"
    assert TOKEN in result.stdout + result.stderr, (
        "decryptor.py did not reveal the token independently recovered from the video"
    )


def test_server_valid_request():
    payload = {
        "xss_payload": "<script>alert(1)</script>",
        "victim_email": "ceo@company.local",
    }
    assert_valid_response(post(f"Bearer {TOKEN}", payload), payload)


def test_server_randomized_payloads_and_script_tag_variants():
    nonce = secrets.token_hex(18)
    payloads = [
        {
            "xss_payload": f'<script data-a="{nonce}">window["x"]="{nonce}";</script>',
            "victim_email": f"{nonce}@company.local",
        },
        {
            "xss_payload": f'<ScRiPt type="text/javascript">console.log("{nonce[::-1]}")</sCrIpT>',
            "victim_email": f"victim+{nonce}@example.net",
        },
        {
            "xss_payload": f"ordinary text without tags {nonce} <b>safe</b>",
            "victim_email": f"plain-{nonce}@example.org",
        },
    ]
    for payload in payloads:
        assert_valid_response(post(f"Bearer {TOKEN}", payload), payload)


def test_server_invalid_auth():
    payload = {"xss_payload": "test", "victim_email": "test@test.com"}
    response = post("Bearer WRONG_TOKEN", payload)
    assert response.status_code == 401, (
        f"Expected status code 401 for invalid auth, got {response.status_code}. Response: {response.text}"
    )


def test_server_rejects_unpredictable_and_near_match_tokens():
    payload = {
        "xss_payload": f"<script>{secrets.token_hex(12)}</script>",
        "victim_email": "random-auth@example.com",
    }
    invalid_headers = [
        f"Bearer {secrets.token_urlsafe(32)}",
        f"Bearer {TOKEN}x",
        f"Bearer x{TOKEN}",
        f"bearer {TOKEN}",
        f"Bearer  {TOKEN}",
        TOKEN,
    ]
    for authorization in invalid_headers:
        response = post(authorization, payload)
        assert response.status_code == 401, (
            f"Expected 401 for non-exact Authorization header {authorization!r}, "
            f"got {response.status_code}. Response: {response.text}"
        )


def test_server_missing_auth():
    payload = {"xss_payload": "test", "victim_email": "test@test.com"}
    response = post(None, payload)
    assert response.status_code == 401, (
        f"Expected status code 401 for missing auth, got {response.status_code}. Response: {response.text}"
    )


def test_server_bound_exactly_to_ipv4_loopback():
    listeners = []
    with open("/proc/net/tcp", "r", encoding="ascii") as handle:
        for line in handle.readlines()[1:]:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            address, port = local_address.split(":")
            if port.upper() == "1F90" and state == "0A":
                listeners.append(address.upper())
    assert "0100007F" in listeners, "No listener found on exactly 127.0.0.1:8080"
    assert "00000000" not in listeners, "Server must not listen on 0.0.0.0:8080"


def test_server_log_exists():
    log_path = "/home/user/server.log"
    assert os.path.isfile(log_path), (
        f"Expected server log file not found at {log_path}. Ensure logs are written to this exact path."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
