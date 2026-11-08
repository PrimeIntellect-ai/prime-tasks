#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import subprocess
import tempfile
import pytest

WAF_SCRIPT = "/home/user/waf.py"
CLEAN_CORPUS_DIR = "/app/traffic/clean/"
EVIL_CORPUS_DIR = "/app/traffic/evil/"

def test_waf_script_exists():
    """Ensure the student created the WAF script at the correct location."""
    assert os.path.exists(WAF_SCRIPT), f"WAF script not found at {WAF_SCRIPT}"
    assert os.path.isfile(WAF_SCRIPT), f"{WAF_SCRIPT} is not a file"

def test_waf_against_clean_corpus():
    """
    Iterate over every file in the clean corpus path and assert the agent's
    solution leaves it unchanged / accepted (exit code 0, prints CLEAN).
    """
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus directory is empty."

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)

        result = subprocess.run(
            ["python3", WAF_SCRIPT, filepath],
            capture_output=True,
            text=True
        )

        if result.returncode != 0 or "CLEAN" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean requests modified/rejected. Offending files: {', '.join(failed_files)}")

def test_waf_against_evil_corpus():
    """
    Iterate over every file in the evil corpus path and assert the agent's
    solution rejects each one (exit code 1, prints EVIL).
    """
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus directory is empty."

    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)

        result = subprocess.run(
            ["python3", WAF_SCRIPT, filepath],
            capture_output=True,
            text=True
        )

        if result.returncode != 1 or "EVIL" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil requests bypassed. Offending files: {', '.join(failed_files)}")

def test_waf_against_generated_holdout():
    """Exercise the WAF on unseen, neutrally named request variants."""
    holdout_dir = tempfile.mkdtemp(prefix="http_holdout_")
    cases = []
    methods = ["GET", "POST", "HEAD"]
    normal_roles = ["user", "viewer", "auditor"]

    for i in range(40):
        user = f"acct_{secrets.token_hex(5)}"
        mac = secrets.token_hex(12)
        role = "admin" if i % 4 == 0 else normal_roles[i % len(normal_roles)]
        tokens = [f"user={user}", f"role={role}", f"mac={mac}"]
        if i % 3 == 0:
            tokens = [tokens[2], tokens[0], tokens[1]]
        elif i % 3 == 1:
            tokens = [tokens[1], tokens[0], tokens[2]]
        request = (
            f"{methods[i % len(methods)]} /resource/{secrets.token_hex(3)} HTTP/1.1\r\n"
            f"User-Agent: audit-{i}\r\n"
            f"Host: service.internal\r\n"
            f"X-Auth-Session: {';'.join(tokens)}\r\n"
            f"Accept: */*\r\n\r\n"
        )
        cases.append((request, 0, "CLEAN"))

    for i in range(40):
        user = f"acct_{secrets.token_hex(5)}"
        mac = secrets.token_hex(12)
        first_role = normal_roles[i % len(normal_roles)]
        if i % 3 == 0:
            tokens = [f"user={user}", f"role={first_role}", f"mac={mac}", "role=admin"]
        elif i % 3 == 1:
            tokens = [f"role={first_role}", f"user={user}", "role=admin", f"mac={mac}"]
        else:
            tokens = [f"mac={mac}", f"user={user}", f"role={first_role}", "role=admin"]
        request = (
            f"{methods[i % len(methods)]} /resource/{secrets.token_hex(3)} HTTP/1.1\r\n"
            f"Host: service.internal\r\n"
            f"X-Request-ID: {secrets.token_hex(8)}\r\n"
            f"X-Auth-Session: {';'.join(tokens)}\r\n"
            f"Connection: close\r\n\r\n"
        )
        cases.append((request, 1, "EVIL"))

    random.SystemRandom().shuffle(cases)
    failures = []
    for request, expected_code, expected_output in cases:
        filepath = os.path.join(holdout_dir, secrets.token_hex(16))
        with open(filepath, "wb") as f:
            f.write(request.encode("ascii"))
        result = subprocess.run(
            ["python3", WAF_SCRIPT, filepath],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != expected_code or result.stdout.strip() != expected_output:
            failures.append((filepath, expected_code, expected_output, result.returncode, result.stdout))

    if failures:
        pytest.fail(f"WAF failed {len(failures)} of {len(cases)} generated holdout requests; first failure: {failures[0]}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
