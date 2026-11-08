#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import math
import os
import re
import stat
import string
from collections import Counter

import cv2
import numpy as np

VIDEO_PATH = "/app/attack_recording.mp4"
EXPECTED_ORIGINAL_KEY = "S3cr3tK3y123!@#"


def read_regular_file(path):
    assert os.path.exists(path), f"File {path} does not exist."
    assert not os.path.islink(path), f"File {path} must not be a symbolic link."
    assert stat.S_ISREG(os.stat(path).st_mode), f"Path {path} must be a regular file."
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def decode_key_from_video():
    assert os.path.isfile(VIDEO_PATH), f"Video {VIDEO_PATH} does not exist."
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), "Could not open attack recording."

    found_blue = False
    bits = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break

        means = frame.mean(axis=(0, 1))
        spread = frame.reshape(-1, 3).std(axis=0)

        if not found_blue:
            if means[0] > 180 and means[1] < 70 and means[2] < 70 and np.max(spread) < 25:
                found_blue = True
            continue

        if len(bits) == 256:
            break

        channel_gap = float(np.max(means) - np.min(means))
        assert channel_gap < 20, f"Encoded frame {len(bits)} is not grayscale."
        intensity = float(np.mean(means))
        if intensity >= 200:
            bits.append("1")
        elif intensity <= 55:
            bits.append("0")
        else:
            raise AssertionError(f"Encoded frame {len(bits)} is neither white nor black.")

    cap.release()
    assert found_blue, "No solid blue start frame was found."
    assert len(bits) == 256, f"Expected 256 encoded bits, found {len(bits)}."

    decoded = bytes(int("".join(bits[i:i + 8]), 2) for i in range(0, 256, 8))
    text = decoded.decode("ascii")
    assert "|" in text, "Decoded transmission does not contain the KEY|PAYLOAD delimiter."
    return text.split("|", 1)[0]


def parse_csp(raw):
    assert raw, "CSP must not be empty."
    assert "\n" not in raw and "\r" not in raw and "\x00" not in raw, "CSP must be a single valid header value."

    value = raw.strip()
    if value.lower().startswith("content-security-policy:"):
        value = value.split(":", 1)[1].strip()
    assert value, "CSP header value must not be empty."

    directives = {}
    for part in value.split(";"):
        part = part.strip()
        if not part:
            continue
        tokens = part.split()
        name = tokens[0].lower()
        assert re.fullmatch(r"[a-z][a-z0-9-]*", name), f"Malformed CSP directive name: {name!r}"
        assert name not in directives, f"Duplicate CSP directive: {name}"
        assert len(tokens) > 1, f"CSP directive {name} has no source list."

        sources = []
        for token in tokens[1:]:
            lowered = token.lower()
            assert not any(ord(ch) < 0x20 for ch in token), "CSP contains a control character."
            if token.startswith("'") or token.endswith("'"):
                assert re.fullmatch(r"'(self|none|unsafe-inline|unsafe-eval|strict-dynamic|report-sample|wasm-unsafe-eval)'", lowered) or re.fullmatch(r"'(nonce-[A-Za-z0-9+/_=-]+|sha(256|384|512)-[A-Za-z0-9+/_=-]+)'", token), f"Malformed quoted CSP source: {token!r}"
            else:
                assert re.fullmatch(r"[^\s;'\"]+", token), f"Malformed CSP source: {token!r}"
            sources.append(lowered)
        directives[name] = sources

    return directives


def test_payload_decoding_and_extraction():
    decoded_key = decode_key_from_video()
    assert decoded_key == EXPECTED_ORIGINAL_KEY, "The supplied recording no longer decodes to the expected intercepted key."

    extracted_key = read_regular_file("/home/user/compromised_key.txt")
    assert extracted_key == decoded_key, "Compromised key was not exactly recovered from the recording."


def test_credential_rotation():
    new_key_path = "/home/user/new_key.txt"
    new_key = read_regular_file(new_key_path)

    assert len(new_key) == 16, f"New key must be exactly 16 characters long, got {len(new_key)}."
    assert all(c in string.ascii_letters + string.digits for c in new_key), "New key must be alphanumeric."
    assert new_key != EXPECTED_ORIGINAL_KEY, "New key must replace the compromised key."

    counts = Counter(new_key)
    assert len(counts) >= 8, "New key has insufficient character diversity for a securely random value."
    assert max(counts.values()) <= 3, "New key contains an implausibly repetitive fixed pattern."
    obvious = (string.ascii_lowercase, string.ascii_uppercase, string.digits,
               string.ascii_lowercase[::-1], string.ascii_uppercase[::-1], string.digits[::-1])
    assert not any(new_key in sequence for sequence in obvious), "New key must not be an obvious fixed sequence."


def test_strict_csp_semantics():
    raw_csp = read_regular_file("/home/user/strict_csp.txt")
    directives = parse_csp(raw_csp)

    assert directives.get("default-src") == ["'self'"], "default-src must allow only 'self'."
    assert "script-src" in directives, "script-src directive is required."
    assert len(directives["script-src"]) == 2, "script-src must allow only the two required sources."
    assert set(directives["script-src"]) == {"'self'", "https://scripts.trusted.internal"}, "script-src must allow only 'self' and https://scripts.trusted.internal."
    assert "'unsafe-inline'" not in directives["script-src"], "unsafe-inline must not be enabled for scripts."
    assert "'unsafe-eval'" not in directives["script-src"], "unsafe-eval must not be enabled for scripts."
    assert directives.get("object-src") == ["'none'"], "object-src must be exactly 'none'."


def test_metric_threshold():
    score = 0.0

    expected_key = EXPECTED_ORIGINAL_KEY
    extracted_key = read_regular_file("/home/user/compromised_key.txt")
    similarity = difflib.SequenceMatcher(None, expected_key, extracted_key).ratio()
    score += 0.5 * similarity

    csp = read_regular_file("/home/user/strict_csp.txt").lower()
    csp_score = 0.0
    if "default-src 'self'" in csp:
        csp_score += 0.1
    if "script-src" in csp and "'self'" in csp and "https://scripts.trusted.internal" in csp:
        csp_score += 0.2
    if "unsafe-inline" not in csp and "unsafe-eval" not in csp:
        csp_score += 0.1
    if "object-src 'none'" in csp:
        csp_score += 0.1

    score += min(0.5, csp_score)
    threshold = 0.90
    assert score >= threshold, f"Score {score:.2f} is below the threshold of {threshold:.2f}. Key similarity: {similarity:.2f}, CSP score: {csp_score:.2f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
