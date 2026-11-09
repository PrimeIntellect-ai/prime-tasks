#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest


def test_config_json():
    config_path = "/home/user/app/services/config.json"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Config file {config_path} is not valid JSON.")

    assert config.get("webhook_url") == "http://127.0.0.1:8080/provision", "webhook_url is not correctly configured."
    assert config.get("api_host") == "127.0.0.1", "api_host is not correctly configured."


def run_filter(filter_script, path):
    return subprocess.run(
        ["python3", filter_script, path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_filter_py_adversarial_corpus():
    filter_script = "/home/user/app/filter.py"
    assert os.path.isfile(filter_script), f"Filter script {filter_script} is missing."

    evil_dir = "/home/user/corpora/evil/"
    clean_dir = "/home/user/corpora/clean/"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)] if os.path.isdir(evil_dir) else []
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)] if os.path.isdir(clean_dir) else []

    evil_bypassed = []
    for f in evil_files:
        res = run_filter(filter_script, f)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        res = run_filter(filter_script, f)
        if res.returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    alphabet = string.ascii_lowercase + string.digits
    valid3 = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(3))
    valid8 = ''.join(secrets.choice(alphabet) for _ in range(8))
    valid12 = ''.join(secrets.choice(alphabet) for _ in range(12))
    upper_name = valid8[0].upper() + valid8[1:]

    cases = [
        (0, f"From: sender@example.test\nSubject: Request Account: {valid3}\n\nI accept the terms of service.\n"),
        (0, f"Subject: Request Account: {valid8}\nX-Request: account\n\nPlease provision me. i ACCEPT THE TERMS OF SERVICE. Thank you.\n"),
        (0, f"To: admin@example.test\nSubject: Request Account: {valid12}\n\nI accept the terms of service.\n"),
        (1, f"Subject: Request Account: ab\n\nI accept the terms of service.\n"),
        (1, f"Subject: Request Account: abcdefghijklm\n\nI accept the terms of service.\n"),
        (1, f"Subject: Request Account: {upper_name}\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: bad-name\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: bad name\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: ../root\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: foo/bar\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: abc;id\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: abc$HOME\n\nI accept the terms of service.\n"),
        (1, "Subject: Request Account: abc&whoami\n\nI accept the terms of service.\n"),
        (1, f"From: sender@example.test\n\nI accept the terms of service.\nUsername: {valid8}\n"),
        (1, f"Subject: Account Request: {valid8}\n\nI accept the terms of service.\n"),
        (1, f"Subject: Request Account: {valid8}\n\nI do not accept anything.\n"),
        (1, f"Subject: Request Account: {valid8}\nX-Notice: I accept the terms of service.\n\nNo acceptance phrase is present in this body.\n"),
        (1, f"Subject: Request Account: {valid8}!\n\nI accept the terms of service.\n"),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="mail-cases-") as case_dir:
        for expected, content in cases:
            path = os.path.join(case_dir, secrets.token_hex(10) + ".eml")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(content)
            res = run_filter(filter_script, path)
            if res.returncode != expected:
                failures.append(
                    f"generated case expected exit {expected}, got {res.returncode}; stderr={res.stderr!r}"
                )

    assert not failures, " | ".join(failures)


def assert_scaffolded(skel_script, username):
    res = subprocess.run([skel_script, username], capture_output=True, text=True, timeout=10)
    assert res.returncode == 0, f"Script failed with exit code {res.returncode}. stderr: {res.stderr}"

    storage_dir = f"/home/user/accounts/{username}/storage/"
    shared_link = f"/home/user/accounts/{username}/shared"
    user_conf = f"/home/user/accounts/{username}/user.conf"

    assert os.path.isdir(storage_dir), "Storage directory was not created."
    assert os.path.islink(shared_link), "Shared symlink was not created."
    assert os.readlink(shared_link) == "/home/user/shared_data/", "Shared symlink points to the wrong target."
    assert os.path.isfile(user_conf), "user.conf was not created."
    with open(user_conf, "r") as f:
        assert "status=active" in f.read(), "user.conf does not contain status=active."

    with open(user_conf, "w") as f:
        f.write("status=inactive")
    res = subprocess.run([skel_script, username], capture_output=True, text=True, timeout=10)
    assert res.returncode == 0, "Idempotency test failed: script returned non-zero exit code on second run."
    with open(user_conf, "r") as f:
        assert "status=inactive" in f.read(), "Idempotency test failed: user.conf was overwritten."


def test_create_skel_sh():
    skel_script = "/home/user/app/create_skel.sh"
    assert os.path.isfile(skel_script), f"Script {skel_script} is missing."
    assert os.access(skel_script, os.X_OK), f"Script {skel_script} is not executable."

    username = "testuser99"
    assert_scaffolded(skel_script, username)

    large_file = "/home/user/accounts/large_dummy"
    with open(large_file, "wb") as f:
        f.write(b"0" * 5000001)

    try:
        res = subprocess.run([skel_script, "testuser_quota"], capture_output=True, text=True, timeout=10)
        assert res.returncode == 2, f"Quota test failed: expected exit code 2, got {res.returncode}."
        assert res.stdout.strip() == "QUOTA_EXCEEDED", f"Quota test failed: expected stdout 'QUOTA_EXCEEDED', got '{res.stdout.strip()}'"
    finally:
        if os.path.exists(large_file):
            os.remove(large_file)


def test_create_skel_randomized_inputs():
    skel_script = "/home/user/app/create_skel.sh"
    alphabet = string.ascii_lowercase + string.digits
    usernames = [
        ''.join(secrets.choice(alphabet) for _ in range(7)),
        ''.join(secrets.choice(alphabet) for _ in range(12)),
    ]

    try:
        for username in usernames:
            shutil.rmtree(f"/home/user/accounts/{username}", ignore_errors=True)
            assert_scaffolded(skel_script, username)
    finally:
        for username in usernames:
            shutil.rmtree(f"/home/user/accounts/{username}", ignore_errors=True)

    quota_user = ''.join(secrets.choice(alphabet) for _ in range(10))
    quota_file = f"/home/user/accounts/{secrets.token_hex(10)}"
    quota_home = f"/home/user/accounts/{quota_user}"
    shutil.rmtree(quota_home, ignore_errors=True)
    with open(quota_file, "wb") as f:
        f.write(b"Q" * 5000001)
    try:
        res = subprocess.run([skel_script, quota_user], capture_output=True, text=True, timeout=10)
        assert res.returncode == 2, f"Randomized quota test expected exit code 2, got {res.returncode}."
        assert res.stdout.strip() == "QUOTA_EXCEEDED", "Randomized quota test emitted incorrect stdout."
        assert not os.path.exists(quota_home), "Account directory was created despite quota being exceeded."
    finally:
        if os.path.exists(quota_file):
            os.remove(quota_file)
        shutil.rmtree(quota_home, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
