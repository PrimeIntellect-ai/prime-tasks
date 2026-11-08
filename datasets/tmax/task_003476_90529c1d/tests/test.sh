#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import subprocess
import sqlite3
import json
import urllib.request
import urllib.error
import time
import uuid
import random
import string
import re
import pytest

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
SANITIZER_SCRIPT = "/home/user/sanitizer.py"
DB_PATH = "/app/analytics.db"
STATUS_PATH = "/home/user/pipeline_status.log"

def run_sanitizer(payload):
    return subprocess.run(
        ["python3", SANITIZER_SCRIPT, json.dumps(payload)],
        capture_output=True,
        timeout=5
    ).returncode

def valid_payload(i=0):
    token = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(10))
    return {
        "user_id": str(uuid.uuid4()),
        "username": ("U" + token)[:20],
        "email": f"{token}.{i}@example.org",
        "age": random.SystemRandom().randint(18, 120),
        "bio": f"ordinary profile {token}"
    }

def post(payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request("http://localhost:8000/submit", data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code

def rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute("SELECT user_id, username, email, age, bio FROM users").fetchall()
    finally:
        conn.close()

def test_sanitizer_clean_corpus():
    assert os.path.isfile(SANITIZER_SCRIPT), f"Sanitizer script missing at {SANITIZER_SCRIPT}"
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.json"))
    assert clean_files, "No clean corpus files found."
    failed = []
    for filepath in clean_files:
        content = open(filepath).read()
        if subprocess.run(["python3", SANITIZER_SCRIPT, content], capture_output=True, timeout=5).returncode != 0:
            failed.append(os.path.basename(filepath))
    assert not failed, f"Clean files rejected: {failed[:10]}"

def test_sanitizer_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.json"))
    assert evil_files, "No evil corpus files found."
    bypassed = []
    for filepath in evil_files:
        content = open(filepath).read()
        if subprocess.run(["python3", SANITIZER_SCRIPT, content], capture_output=True, timeout=5).returncode == 0:
            bypassed.append(os.path.basename(filepath))
    assert not bypassed, f"Evil files accepted: {bypassed[:10]}"

def test_sanitizer_generated_cases():
    # Fresh randomized payloads prevent corpus filename/hash whitelisting.
    for i in range(12):
        p = valid_payload(i)
        assert run_sanitizer(p) == 0, f"Fresh valid payload rejected: {p}"

        mutations = []
        for bad_id in [str(uuid.uuid1()), str(uuid.uuid4()).upper(), "not-a-uuid"]:
            q = dict(p); q["user_id"] = bad_id; mutations.append(q)
        for bad_name in ["ab", "x" * 21, "bad-name", "a b", "_"]:
            q = dict(p); q["username"] = bad_name; mutations.append(q)
        for bad_email in ["plainaddress", "a@", "@example.com", "a b@example.com"]:
            q = dict(p); q["email"] = bad_email; mutations.append(q)
        for bad_age in [17, 121, 18.5, "25", True, None]:
            q = dict(p); q["age"] = bad_age; mutations.append(q)
        for bad_bio in ["hello <b>world</b>", "prefix <anything> suffix", "<>"]:
            q = dict(p); q["bio"] = bad_bio; mutations.append(q)
        for key in p:
            q = dict(p); del q[key]; mutations.append(q)
        q = dict(p); q["extra"] = "field"; mutations.append(q)
        for q in mutations:
            assert run_sanitizer(q) != 0, f"Fresh invalid payload accepted: {q}"

    malformed = ["", "not json", "[]", "null", "{", json.dumps([valid_payload()])]
    for text in malformed:
        rc = subprocess.run(["python3", SANITIZER_SCRIPT, text], capture_output=True, timeout=5).returncode
        assert rc != 0, f"Malformed/non-profile JSON accepted: {text!r}"

def test_nginx_config():
    assert os.path.isfile("/app/nginx.conf")
    config_content = open("/app/nginx.conf").read()
    assert "5000" in config_content, "Nginx config does not seem to forward to port 5000."

def test_database_initial_count_and_origin():
    assert os.path.isfile(DB_PATH)
    actual = rows()
    assert len(actual) == 100, f"Expected 100 rows in database, but found {len(actual)}."
    expected = []
    for path in glob.glob(os.path.join(CLEAN_DIR, "*.json")):
        with open(path) as f:
            p = json.load(f)
        expected.append((p["user_id"], p["username"], p["email"], p["age"], p["bio"]))
    assert sorted(actual) == sorted(expected), "Database rows are not exactly the clean corpus rows."

def test_pipeline_status_log():
    assert os.path.isfile(STATUS_PATH), f"Missing {STATUS_PATH}"
    assert open(STATUS_PATH).read().strip() == "100", "pipeline_status.log must contain the exact completed row count 100"

def test_e2e_pipeline_accepts_valid_and_rejects_invalid():
    before = rows()
    valid = [valid_payload(i + 1000) for i in range(8)]
    invalid = []
    for i in range(8):
        q = valid_payload(i + 2000)
        field = i % 5
        if field == 0: q["user_id"] = "invalid"
        elif field == 1: q["username"] = "bad-name"
        elif field == 2: q["email"] = "invalid"
        elif field == 3: q["age"] = 121
        else: q["bio"] = "random <tag> content"
        invalid.append(q)

    for p in valid:
        assert post(p) == 200, "Valid payload was not accepted through Nginx"
    for p in invalid:
        assert post(p) == 400, "Invalid payload was not rejected through Nginx"
    time.sleep(2)

    after = rows()
    added = after[len(before):]
    expected = [(p["user_id"], p["username"], p["email"], p["age"], p["bio"]) for p in valid]
    assert len(after) == len(before) + len(valid), "Only fresh valid payloads should be inserted"
    assert sorted(added) == sorted(expected), "Inserted rows do not match the fresh valid requests"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
