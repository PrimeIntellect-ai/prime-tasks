#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import subprocess
import tempfile

import cv2

DETECTOR = "/home/user/detector.py"
VIDEO = "/app/rotation_alert.mp4"
BLOCKED = (b"drop table", b"1=1", b"<script>")


def recover_token():
    capture = cv2.VideoCapture(VIDEO)
    assert capture.isOpened(), f"Could not open {VIDEO}"
    qr = cv2.QRCodeDetector()
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            value, _, _ = qr.detectAndDecode(frame)
            if value:
                return value
    finally:
        capture.release()
    raise AssertionError("No QR token could be decoded from the rotation video")


def expected_result(request, token):
    headers = request.get("headers") or {}
    cookies = request.get("cookies") or {}
    authenticated = (
        headers.get("Authorization") == "Bearer " + token
        or cookies.get("session_id") == token
    )
    if not authenticated:
        return 1

    encoded = headers.get("X-Encoded-Payload")
    if encoded is not None:
        try:
            decoded = base64.b64decode(encoded, validate=True).lower()
        except Exception:
            return 1
        if any(marker in decoded for marker in BLOCKED):
            return 1
    return 0


def mixed_case(value):
    return "".join(
        char.upper() if char.isalpha() and secrets.randbelow(2) else char.lower()
        for char in value
    )


def encode_payload(value):
    return base64.b64encode(value.encode()).decode()


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR), f"Detector script is missing at {DETECTOR}"


def test_adversarial_requests_on_unpredictable_paths():
    token = recover_token()
    wrong_tokens = ["invalid-" + secrets.token_hex(12) for _ in range(4)]

    auth_variants = [
        ({"Authorization": "Bearer " + token}, {}),
        ({}, {"session_id": token}),
        ({"Authorization": "Bearer " + token}, {"session_id": wrong_tokens[0]}),
        ({"Authorization": "Bearer " + wrong_tokens[1]}, {"session_id": token}),
        ({"Authorization": "Bearer " + wrong_tokens[2]}, {}),
        ({}, {"session_id": wrong_tokens[3]}),
        ({}, {}),
        ({"Authorization": token}, {}),
        ({"Authorization": "bearer " + token}, {}),
    ]

    benign_payloads = [
        None,
        "",
        "hello-" + secrets.token_hex(16),
        "SELECT name FROM users WHERE id=2 " + secrets.token_hex(8),
    ]
    malicious_payloads = [
        "prefix " + mixed_case("drop table") + " accounts " + secrets.token_hex(5),
        secrets.token_hex(5) + " " + mixed_case("1=1") + " suffix",
        "text " + mixed_case("<script>") + "alert(7)</script>",
    ]

    requests = []
    for headers, cookies in auth_variants:
        for payload in benign_payloads + malicious_payloads:
            current_headers = dict(headers)
            if payload is not None:
                current_headers["X-Encoded-Payload"] = encode_payload(payload)
            requests.append({
                "method": random.choice(["GET", "POST", "PUT"]),
                "headers": current_headers,
                "cookies": dict(cookies),
            })

    # Preserve checks for gracefully handled missing authentication fields.
    requests.extend([
        {"method": "POST"},
        {"method": "POST", "headers": {}, "cookies": {}},
        {"method": "POST", "headers": {"Authorization": "Bearer " + token}},
        {"method": "POST", "cookies": {"session_id": token}},
    ])
    random.SystemRandom().shuffle(requests)

    failures = []
    with tempfile.TemporaryDirectory(prefix="request-inputs-") as directory:
        for index, request in enumerate(requests):
            path = os.path.join(directory, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(request, handle)

            expected = expected_result(request, token)
            try:
                result = subprocess.run(
                    ["python3", DETECTOR, path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"

            if actual != expected:
                failures.append(
                    f"case {index}: expected exit {expected}, got {actual}"
                )

    assert not failures, " | ".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
