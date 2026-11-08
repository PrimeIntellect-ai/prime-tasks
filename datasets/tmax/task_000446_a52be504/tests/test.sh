#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'ARTIFACT_EOF' > /tmp/check_process_logs.py
import json
import os
import re
import secrets
import stat
import subprocess

SCRIPT = "/home/user/process_logs.sh"
RAW = "/home/user/raw_logs.jsonl"
CLEAN = "/home/user/clean_logs.jsonl"

with open(RAW, "rb") as f:
    original_raw = f.read()

failure = None
try:
    st = os.stat(SCRIPT)
    assert stat.S_ISREG(st.st_mode), f"{SCRIPT} is not a regular file"
    assert st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"{SCRIPT} is not executable"

    nonce = secrets.token_hex(8)
    records = [
        {"timestamp": f"probe-{nonce}-1", "user_id": None, "email": f"alpha.{nonce}@example.test", "message": "ProbeTOKEN1"},
        {"timestamp": f"probe-{nonce}-2", "user_id": 700000 + secrets.randbelow(100000), "email": f"beta+{nonce}@work.test", "message": "ValueTOKEN2"},
        {"timestamp": f"probe-{nonce}-3", "user_id": None, "email": f"gamma_{nonce}@home.test", "message": "Code TOKEN3"},
    ]
    replacements = [("TOKEN1", r"\x21"), ("TOKEN2", r"\x3a"), ("TOKEN3", r"\x41")]
    probe_lines = []
    for record, (token, escape) in zip(records, replacements):
        line = json.dumps(record, separators=(",", ":"))
        probe_lines.append(line.replace(token, escape))

    with open(RAW, "w", encoding="utf-8") as f:
        f.write("\n".join(probe_lines) + "\n")
    if os.path.exists(CLEAN):
        os.unlink(CLEAN)

    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"process_logs.sh failed on test input: {result.stderr}"
    assert os.path.isfile(CLEAN), "process_logs.sh did not create clean_logs.jsonl"

    with open(CLEAN, "r", encoding="utf-8") as f:
        clean_lines = f.readlines()
    assert len(clean_lines) == len(probe_lines), "process_logs.sh did not preserve the input line count"

    for i, (raw_line, clean_line) in enumerate(zip(probe_lines, clean_lines), 1):
        raw_obj = json.loads(re.sub(r'\\x([0-9a-fA-F]{2})', r'\\u00\1', raw_line))
        expected = dict(raw_obj)
        if expected.get("user_id") is None:
            expected["user_id"] = "UNKNOWN"
        email = expected.get("email", "")
        if "@" in email:
            expected["email"] = "***@" + email.split("@", 1)[1]
        try:
            actual = json.loads(clean_line)
        except json.JSONDecodeError as e:
            raise AssertionError(f"Probe output line {i} is invalid JSON: {e}")
        assert actual == expected, f"Probe output line {i} was transformed incorrectly"
except Exception as e:
    failure = e
finally:
    with open(RAW, "wb") as f:
        f.write(original_raw)
    if os.path.isfile(SCRIPT) and os.stat(SCRIPT).st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
        try:
            if os.path.exists(CLEAN):
                os.unlink(CLEAN)
            result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=15)
            if result.returncode != 0:
                raise AssertionError(f"process_logs.sh failed on the required input: {result.stderr}")
            with open(RAW, "rb") as f:
                assert f.read() == original_raw, "process_logs.sh modified raw_logs.jsonl"
        except Exception as e:
            if failure is None:
                failure = e
            with open(RAW, "wb") as f:
                f.write(original_raw)

if failure is not None:
    raise failure
ARTIFACT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re

def test_clean_logs_exists():
    assert os.path.isfile("/home/user/clean_logs.jsonl"), "The file /home/user/clean_logs.jsonl does not exist. Did you run the script?"

def test_clean_logs_line_count():
    with open("/home/user/raw_logs.jsonl", "r") as f:
        raw_lines = f.readlines()
    with open("/home/user/clean_logs.jsonl", "r") as f:
        clean_lines = f.readlines()

    assert len(clean_lines) == len(raw_lines), f"Expected {len(raw_lines)} lines in clean_logs.jsonl, but found {len(clean_lines)}."

def test_clean_logs_valid_json_and_transformations():
    with open("/home/user/raw_logs.jsonl", "r") as f:
        raw_lines = f.readlines()
    with open("/home/user/clean_logs.jsonl", "r") as f:
        clean_lines = f.readlines()

    for i, (raw_line, clean_line) in enumerate(zip(raw_lines, clean_lines)):
        try:
            clean_obj = json.loads(clean_line)
        except json.JSONDecodeError as e:
            assert False, f"Line {i+1} in clean_logs.jsonl is not valid JSON: {e}\nLine content: {clean_line.strip()}"

        # Fix the raw line's invalid \x escape sequences so we can parse it as truth
        fixed_raw_line = re.sub(r'\\x([0-9a-fA-F]{2})', r'\\u00\1', raw_line)
        raw_obj = json.loads(fixed_raw_line)

        # 1. Check user_id imputation
        if raw_obj.get("user_id") is None:
            assert clean_obj.get("user_id") == "UNKNOWN", f"Line {i+1}: 'user_id' was null but not imputed to 'UNKNOWN'."
        else:
            assert clean_obj.get("user_id") == raw_obj.get("user_id"), f"Line {i+1}: 'user_id' was altered improperly."

        # 2. Check email masking
        raw_email = raw_obj.get("email", "")
        if "@" in raw_email:
            domain = raw_email.split("@")[1]
            expected_email = f"***@{domain}"
            assert clean_obj.get("email") == expected_email, f"Line {i+1}: 'email' was not masked correctly. Expected {expected_email}, got {clean_obj.get('email')}."

        # 3. Check message (verifies unicode escape processing)
        assert clean_obj.get("message") == raw_obj.get("message"), f"Line {i+1}: 'message' was not processed correctly. Check escape sequence conversion."

        # 4. Check timestamp remains intact
        assert clean_obj.get("timestamp") == raw_obj.get("timestamp"), f"Line {i+1}: 'timestamp' was altered."
TEST_EOF

if python3 /tmp/check_process_logs.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
