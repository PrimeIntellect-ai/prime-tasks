#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import pytest

WORKSPACE_DIR = "/home/user/traffic_inspector"
AUTH_LOGS_PATH = os.path.join(WORKSPACE_DIR, "auth_logs.txt")
FLAGGED_IPS_PATH = os.path.join(WORKSPACE_DIR, "flagged_ips.log")
MAKEFILE_PATH = os.path.join(WORKSPACE_DIR, "Makefile")
EXECUTABLE_PATH = os.path.join(WORKSPACE_DIR, "inspector")


def get_expected_flagged_ips():
    expected_ips = []
    if not os.path.exists(AUTH_LOGS_PATH):
        return expected_ips

    with open(AUTH_LOGS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 4:
                continue

            ip, username, token, provided_hash = parts
            computed_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()

            if computed_hash == provided_hash and "EXPLOIT_PATTERN_X99" in token:
                expected_ips.append(ip)

    return expected_ips


def test_makefile_links_openssl():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile is missing at {MAKEFILE_PATH}"
    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()

    assert "-lssl" in content and "-lcrypto" in content, "Makefile does not link OpenSSL libraries (-lssl -lcrypto)."


def test_makefile_builds_inspector():
    if os.path.lexists(EXECUTABLE_PATH):
        os.remove(EXECUTABLE_PATH)

    result = subprocess.run(
        ["make"],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Running make failed:\n{result.stdout}"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}. Did you run 'make'?"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "inspector is not a compiled executable."


def test_flagged_ips_log_correctness():
    assert os.path.isfile(FLAGGED_IPS_PATH), f"Output file not found at {FLAGGED_IPS_PATH}. Did you run the compiled program?"

    expected_ips = get_expected_flagged_ips()

    with open(FLAGGED_IPS_PATH, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, (
        f"Contents of {FLAGGED_IPS_PATH} do not match expected logic.\n"
        f"Expected: {expected_ips}\n"
        f"Actual: {actual_ips}\n"
        "Ensure you are verifying the SHA-256 hash and checking for 'EXPLOIT_PATTERN_X99' before logging the IP."
    )


def test_executable_on_fresh_randomized_logs():
    nonce = secrets.token_hex(20)

    valid_attack_1 = f"AUTH_EXPLOIT_PATTERN_X99_{nonce}"
    valid_attack_2 = f"{nonce}_EXPLOIT_PATTERN_X99_TRAILING"
    tampered_attack = f"EXPLOIT_PATTERN_X99_TAMPERED_{nonce}"
    safe_token = f"REGULAR_AUTH_{nonce}"
    near_match = f"EXPLOIT_PATTERN_X9_{nonce}"
    lowercase_match = f"exploit_pattern_x99_{nonce}"

    def digest(token):
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    correct_tampered_digest = digest(tampered_attack)
    wrong_tampered_digest = ("0" if correct_tampered_digest[0] != "0" else "1") + correct_tampered_digest[1:]

    records = [
        ("198.51.100.11", "alpha", valid_attack_1, digest(valid_attack_1)),
        ("203.0.113.27", "root", tampered_attack, wrong_tampered_digest),
        ("192.0.2.44", "EXPLOIT_PATTERN_X99", safe_token, digest(safe_token)),
        ("198.51.100.78", "beta", near_match, digest(near_match)),
        ("203.0.113.91", "gamma", valid_attack_2, digest(valid_attack_2)),
        ("192.0.2.123", "delta", lowercase_match, digest(lowercase_match)),
    ]

    # Randomize ordering so a fixed output cannot satisfy this test.
    for i in range(len(records) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        records[i], records[j] = records[j], records[i]

    input_text = "\n".join(
        f"{ip} | {username} | {token} | {provided_hash}"
        for ip, username, token, provided_hash in records
    ) + "\nmalformed | EXPLOIT_PATTERN_X99 | line\n\n"

    expected_ips = [
        ip
        for ip, username, token, provided_hash in records
        if hashlib.sha256(token.encode("utf-8")).hexdigest() == provided_hash
        and "EXPLOIT_PATTERN_X99" in token
    ]

    with open(AUTH_LOGS_PATH, "rb") as f:
        original_auth_logs = f.read()
    output_existed = os.path.exists(FLAGGED_IPS_PATH)
    original_output = None
    if output_existed:
        with open(FLAGGED_IPS_PATH, "rb") as f:
            original_output = f.read()

    try:
        with open(AUTH_LOGS_PATH, "w", encoding="utf-8") as f:
            f.write(input_text)
        if os.path.lexists(FLAGGED_IPS_PATH):
            os.remove(FLAGGED_IPS_PATH)

        result = subprocess.run(
            [EXECUTABLE_PATH],
            cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"inspector exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(FLAGGED_IPS_PATH), "inspector did not create flagged_ips.log"

        with open(FLAGGED_IPS_PATH, "r", encoding="utf-8") as f:
            actual_ips = [line.strip() for line in f if line.strip()]

        assert actual_ips == expected_ips, (
            "inspector failed on freshly generated authentication records.\n"
            f"Expected: {expected_ips}\nActual: {actual_ips}"
        )
    finally:
        with open(AUTH_LOGS_PATH, "wb") as f:
            f.write(original_auth_logs)
        if output_existed:
            with open(FLAGGED_IPS_PATH, "wb") as f:
                f.write(original_output)
        elif os.path.lexists(FLAGGED_IPS_PATH):
            os.remove(FLAGGED_IPS_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
