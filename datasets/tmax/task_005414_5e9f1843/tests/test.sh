#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod 700 "$0" 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pwd
import secrets
import subprocess
import tempfile

import pytest

AGENT_SCRIPT = "/home/user/jwt_analyzer.py"
BACKDOOR_SUBJECT = "delta_epsilon_99"
RUN_AS = pwd.getpwnam("user")


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def randomized_json(fields):
    items = list(fields.items())
    secrets.SystemRandom().shuffle(items)
    obj = dict(items)
    if secrets.randbelow(2):
        encoded = json.dumps(obj, separators=(",", ":"))
    else:
        encoded = json.dumps(obj, separators=(", ", ": "))
    return encoded.encode("utf-8")


def make_token(algorithm, subject, stripped_signature=False):
    marker = secrets.token_hex(12)
    header = {"alg": algorithm, "typ": "JWT", "kid": secrets.token_hex(5)}
    payload = {
        "sub": subject,
        "jti": secrets.token_hex(12),
        "aud": "gateway-" + marker,
    }
    encoded_header = b64url(randomized_json(header))
    encoded_payload = b64url(randomized_json(payload))
    signature = "" if stripped_signature else b64url(secrets.token_bytes(32))
    return f"{encoded_header}.{encoded_payload}.{signature}"


def demote():
    os.setgroups([])
    os.setgid(RUN_AS.pw_gid)
    os.setuid(RUN_AS.pw_uid)


def test_jwt_analyzer_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."


def test_adversarial_dynamic_evaluation():
    assert os.path.isfile(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."

    cases = []
    for _ in range(14):
        algorithm = secrets.choice(["HS256", "RS256"])
        subject = secrets.choice([
            "user-" + secrets.token_hex(8),
            "delta_epsilon_98",
            "delta-epsilon-99",
        ])
        cases.append((make_token(algorithm, subject), 0))

    for variant in ["none", "None", "NONE", "NoNe"]:
        for _ in range(3):
            subject = "user-" + secrets.token_hex(8)
            cases.append((make_token(variant, subject, stripped_signature=True), 1))

    for _ in range(12):
        algorithm = secrets.choice(["HS256", "RS256"])
        cases.append((make_token(algorithm, BACKDOOR_SUBJECT), 1))

    for _ in range(4):
        variant = secrets.choice(["none", "None", "NONE", "nOnE"])
        cases.append((make_token(variant, BACKDOOR_SUBJECT, stripped_signature=True), 1))

    secrets.SystemRandom().shuffle(cases)
    failures = []

    with tempfile.TemporaryDirectory(prefix="jwt-inputs-") as directory:
        os.chmod(directory, 0o755)
        for token, expected in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(token)
                if secrets.randbelow(2):
                    handle.write("\n")
            os.chmod(path, 0o644)

            try:
                result = subprocess.run(
                    ["python3", AGENT_SCRIPT, path],
                    capture_output=True,
                    timeout=5,
                    preexec_fn=demote,
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"

            if actual != expected:
                failures.append((expected, actual))

    if failures:
        pytest.fail(
            f"{len(failures)} of {len(cases)} dynamically generated JWTs were "
            f"misclassified; first failures: {failures[:10]}"
        )
TEST_EOF
chmod 700 /tmp/test_final_state.py

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
