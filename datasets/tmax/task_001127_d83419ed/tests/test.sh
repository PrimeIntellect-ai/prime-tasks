#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import hmac
import hashlib
import json
import secrets
import string
import subprocess

SCRIPT_PATH = "/home/user/audit_redactor.py"
RAW_LOG_PATH = "/home/user/raw_audit.log"
CLEAN_LOG_PATH = "/home/user/clean_audit.log"
BINARY_PATH = "/home/user/legacy_worker"


def extract_secret(binary_path):
    with open(binary_path, "rb") as f:
        data = f.read()
    match = re.search(b"COMPLIANCE_KEY_[A-Za-z0-9_]+", data)
    if not match:
        raise ValueError("Could not find COMPLIANCE_KEY_ in binary")
    return match.group(0)


def is_valid_jwt(token, secret):
    parts = token.split('.')
    if len(parts) != 3:
        return False
    header_payload = f"{parts[0]}.{parts[1]}".encode('utf-8')
    expected_sig = base64.urlsafe_b64encode(
        hmac.new(secret, header_payload, hashlib.sha256).digest()
    ).decode('utf-8').rstrip('=')
    return hmac.compare_digest(expected_sig, parts[2])


def process_line(line, secret):
    def replacer(m):
        token = m.group(1)
        if is_valid_jwt(token, secret):
            return "--token [REDACTED]"
        return m.group(0)
    return re.sub(r'--token\s+(\S+)', replacer, line)


def run_script():
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=15,
    )


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def make_token(secret, payload):
    header = b64url(json.dumps(
        {"alg": "HS256", "typ": "JWT"}, separators=(",", ":")
    ).encode("utf-8"))
    body = b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header}.{body}"
    signature = b64url(hmac.new(
        secret, signing_input.encode("utf-8"), hashlib.sha256
    ).digest())
    return f"{signing_input}.{signature}"


def test_audit_redactor_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not found."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} should be a file."


def test_clean_audit_log_correctness_and_script_behavior():
    with open(RAW_LOG_PATH, "rb") as f:
        original_raw = f.read()
    with open(BINARY_PATH, "rb") as f:
        original_binary = f.read()
    original_clean = None
    if os.path.exists(CLEAN_LOG_PATH):
        with open(CLEAN_LOG_PATH, "rb") as f:
            original_clean = f.read()

    try:
        # Execute the submitted artifact on the original task input. Removing any
        # prewritten output ensures the script itself must create the result.
        secret = extract_secret(BINARY_PATH)
        raw_lines = original_raw.decode("utf-8").splitlines(keepends=True)
        expected_content = "".join(process_line(line, secret) for line in raw_lines)

        if os.path.exists(CLEAN_LOG_PATH):
            os.remove(CLEAN_LOG_PATH)
        run_script()

        assert os.path.exists(CLEAN_LOG_PATH), (
            f"The output log {CLEAN_LOG_PATH} was not found."
        )
        with open(CLEAN_LOG_PATH, "r") as f:
            actual_content = f.read()
        assert actual_content == expected_content, (
            f"The content of {CLEAN_LOG_PATH} does not match the expected redacted output. "
            "Ensure only valid JWTs signed with the extracted secret are redacted."
        )

        # Replace the embedded key with an unpredictable same-length key and use
        # newly generated log entries, proving the script extracts and uses it.
        old_secret = extract_secret(BINARY_PATH)
        prefix = b"COMPLIANCE_KEY_"
        suffix_len = len(old_secret) - len(prefix)
        alphabet = string.ascii_letters + string.digits
        new_secret = prefix + "".join(
            secrets.choice(alphabet) for _ in range(suffix_len)
        ).encode("ascii")
        while new_secret == old_secret:
            new_secret = prefix + "".join(
                secrets.choice(alphabet) for _ in range(suffix_len)
            ).encode("ascii")

        patched_binary = original_binary.replace(old_secret, new_secret)
        assert patched_binary != original_binary
        with open(BINARY_PATH, "wb") as f:
            f.write(patched_binary)

        valid_one = make_token(new_secret, {
            "user": "dynamic-" + secrets.token_hex(8), "role": "auditor"
        })
        valid_two = make_token(new_secret, {
            "job": secrets.token_hex(10), "count": 7
        })
        invalid = valid_one[:-1] + ("A" if valid_one[-1] != "A" else "B")
        dynamic_raw = (
            "2031-04-05 01:02:03 /bin/echo no-sensitive-arguments\n"
            f"2031-04-05 01:03:04 /home/user/legacy_worker --token {valid_one} --task alpha\n"
            f"2031-04-05 01:04:05 /home/user/legacy_worker --task beta --token {invalid} --force\n"
            "2031-04-05 01:05:06 /bin/tool --token not.a.jwt.with.too.many.parts --keep\n"
            f"2031-04-05 01:06:07 /bin/tool --first x --token {valid_two}\n"
        )
        with open(RAW_LOG_PATH, "w") as f:
            f.write(dynamic_raw)
        if os.path.exists(CLEAN_LOG_PATH):
            os.remove(CLEAN_LOG_PATH)

        run_script()
        assert os.path.exists(CLEAN_LOG_PATH), (
            f"The output log {CLEAN_LOG_PATH} was not created by the script."
        )
        expected_dynamic = "".join(
            process_line(line, new_secret)
            for line in dynamic_raw.splitlines(keepends=True)
        )
        with open(CLEAN_LOG_PATH, "r") as f:
            actual_dynamic = f.read()
        assert actual_dynamic == expected_dynamic, (
            "The script failed on dynamically generated JWTs or did not extract "
            "the current secret from the legacy binary."
        )
    finally:
        with open(RAW_LOG_PATH, "wb") as f:
            f.write(original_raw)
        with open(BINARY_PATH, "wb") as f:
            f.write(original_binary)
        if original_clean is None:
            if os.path.exists(CLEAN_LOG_PATH):
                os.remove(CLEAN_LOG_PATH)
        else:
            with open(CLEAN_LOG_PATH, "wb") as f:
                f.write(original_clean)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
