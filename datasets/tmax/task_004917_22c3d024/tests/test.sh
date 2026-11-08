#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/validator.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
SECRET = b"crimson_dynamo_88"


def test_validator_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Validator script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus missing at {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, "No files found in clean corpus directory."

    failed_files = []

    for token_file in clean_files:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, token_file],
            capture_output=True,
            text=True
        )

        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "VALID":
            failed_files.append((os.path.basename(token_file), result.returncode, stdout))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean tokens rejected/modified.\n"
        for fname, rc, out in failed_files[:10]:
            error_msg += f"  - {fname}: exit code {rc}, stdout '{out}'\n"
        if len(failed_files) > 10:
            error_msg += f"  ... and {len(failed_files) - 10} more."
        pytest.fail(error_msg)


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus missing at {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, "No files found in evil corpus directory."

    failed_files = []

    for token_file in evil_files:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, token_file],
            capture_output=True,
            text=True
        )

        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "INVALID":
            failed_files.append((os.path.basename(token_file), result.returncode, stdout))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil tokens bypassed.\n"
        for fname, rc, out in failed_files[:10]:
            error_msg += f"  - {fname}: exit code {rc}, stdout '{out}'\n"
        if len(failed_files) > 10:
            error_msg += f"  ... and {len(failed_files) - 10} more."
        pytest.fail(error_msg)


def encode_payload(payload):
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def sign(payload_b64, secret=SECRET):
    return hashlib.sha256(payload_b64.encode("ascii") + secret).hexdigest()


def make_token(payload, secret=SECRET):
    payload_b64 = encode_payload(payload)
    return payload_b64 + "." + sign(payload_b64, secret)


def oracle_valid(token):
    try:
        if token.count(".") != 1:
            return False
        payload_b64, supplied_signature = token.split(".")
        if not payload_b64 or re.fullmatch(r"[A-Za-z0-9_-]+", payload_b64) is None:
            return False
        if re.fullmatch(r"[0-9a-fA-F]{64}", supplied_signature) is None:
            return False
        padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        raw = base64.b64decode(padded, altchars=b"-_", validate=True)
        payload = json.loads(raw.decode("utf-8"))
        if not isinstance(payload, dict):
            return False
        user_id = payload.get("user_id")
        exp = payload.get("exp")
        if not isinstance(user_id, str) or not user_id.isalnum():
            return False
        if isinstance(exp, bool) or not isinstance(exp, (int, float)) or exp <= 1710000000:
            return False
        expected_signature = sign(payload_b64)
        return hmac.compare_digest(supplied_signature.lower(), expected_signature)
    except (ValueError, TypeError, UnicodeError, json.JSONDecodeError):
        return False


def test_fresh_independently_classified_tokens():
    nonce = secrets.token_hex(12)
    future = 1800000000 + secrets.randbelow(10000000)

    valid_one = make_token({"user_id": "Agent" + nonce, "exp": future, "role": "user"})
    valid_two = make_token({"role": "auditor", "exp": future + 1, "user_id": nonce.upper()})
    valid_three = make_token({"user_id": "U" + str(secrets.randbelow(10**12)), "exp": future + 2})

    original_payload = {"user_id": "Victim" + nonce, "exp": future, "role": "user"}
    original_b64 = encode_payload(original_payload)
    forged_b64 = encode_payload({"user_id": "Victim" + nonce, "exp": future, "role": "admin"})
    forged_token = forged_b64 + "." + sign(original_b64)

    candidates = [
        valid_one,
        valid_two,
        valid_three,
        make_token({"user_id": "Expired" + nonce, "exp": 1700000000, "role": "user"}),
        make_token({"user_id": "Boundary" + nonce, "exp": 1710000000, "role": "user"}),
        make_token({"user_id": "bad-user-" + nonce, "exp": future, "role": "user"}),
        make_token({"exp": future, "role": "user"}),
        make_token({"user_id": "NoExpiry" + nonce, "role": "user"}),
        forged_token,
        make_token({"user_id": "WrongKey" + nonce, "exp": future}, b"not_the_real_secret"),
        valid_one[:-1] + ("0" if valid_one[-1] != "0" else "1"),
        "not-a-token",
        "!!!!." + ("0" * 64),
        encode_payload({"user_id": "ExtraDot" + nonce, "exp": future}) + "." + ("0" * 64) + ".extra",
    ]
    random.SystemRandom().shuffle(candidates)

    expected_results = [oracle_valid(token) for token in candidates]
    assert any(expected_results), "Fresh test generation produced no valid tokens"
    assert not all(expected_results), "Fresh test generation produced no invalid tokens"

    failures = []
    with tempfile.TemporaryDirectory(prefix="validator-cases-") as case_dir:
        for token, expected_valid in zip(candidates, expected_results):
            token_path = os.path.join(case_dir, uuid.uuid4().hex)
            with open(token_path, "w", encoding="utf-8") as token_file:
                token_file.write(token)

            result = subprocess.run(
                ["python3", SCRIPT_PATH, token_path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            expected_code = 0 if expected_valid else 1
            expected_stdout = "VALID" if expected_valid else "INVALID"
            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append((expected_valid, result.returncode, result.stdout.strip()))

    if failures:
        details = "\n".join(
            f"expected {'VALID' if valid else 'INVALID'}, got exit {rc}, stdout {out!r}"
            for valid, rc, out in failures[:10]
        )
        pytest.fail(f"Validator failed {len(failures)} fresh independently classified cases:\n{details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
