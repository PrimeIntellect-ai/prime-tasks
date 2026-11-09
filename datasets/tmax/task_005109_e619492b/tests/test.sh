#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import urllib.request
import urllib.error
import subprocess
import glob
import re
import secrets
import pytest

SSN_RE = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')

def test_solution_status():
    status_file = "/home/user/solution_status.txt"
    assert os.path.isfile(status_file), f"Solution status file missing at {status_file}"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"Expected 'READY' in {status_file}, found '{content}'"

def redis_lrange(key):
    try:
        result = subprocess.run(["redis-cli", "LRANGE", key, "0", "-1"], capture_output=True, text=True, check=True)
        return result.stdout.strip().splitlines()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query Redis: {e.stderr}")

def clear_redis(key):
    subprocess.run(["redis-cli", "DEL", key], capture_output=True, check=True)

def post_to_service(payload):
    req = urllib.request.Request("http://127.0.0.1:8080/sanitize", data=payload, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.URLError as e:
        return getattr(e, 'code', str(e))

def contains_pii(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("ssn", "credit_card") and v != "[REDACTED]":
                return True
            if contains_pii(v):
                return True
    elif isinstance(obj, list):
        return any(contains_pii(item) for item in obj)
    elif isinstance(obj, str):
        return SSN_RE.search(obj) is not None
    return False

def assert_preserved_and_sanitized(original, actual, path="$."):
    if isinstance(original, dict):
        assert isinstance(actual, dict), f"Expected object at {path}, got {type(actual).__name__}"
        assert set(actual).issubset(set(original)), f"Unexpected fields were added at {path}"
        for key, value in original.items():
            child_path = f"{path}{key}."
            if key in ("ssn", "credit_card"):
                if key in actual:
                    assert actual[key] == "[REDACTED]", f"PII field {child_path} was not redacted"
            else:
                assert key in actual, f"Non-PII field {child_path} was removed"
                assert_preserved_and_sanitized(value, actual[key], child_path)
    elif isinstance(original, list):
        assert isinstance(actual, list), f"Expected list at {path}"
        assert len(actual) == len(original), f"List structure changed at {path}"
        for index, (before, after) in enumerate(zip(original, actual)):
            assert_preserved_and_sanitized(before, after, f"{path}[{index}].")
    elif isinstance(original, str):
        assert isinstance(actual, str), f"String type changed at {path}"
        if SSN_RE.search(original):
            substituted = SSN_RE.sub("[REDACTED]", original)
            assert actual in (substituted, "[REDACTED]"), f"PII string at {path} was not correctly redacted"
        else:
            assert actual == original, f"Non-PII string changed at {path}"
    else:
        assert type(actual) is type(original) and actual == original, f"Non-PII value changed at {path}"

def test_clean_corpus():
    clean_dir = "/home/user/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    clear_redis("processed_logs")

    failed_files = []
    for filepath in clean_files:
        with open(filepath, "rb") as f:
            payload = f.read()

        status = post_to_service(payload)
        if status not in (200, 201, 202, 204):
            failed_files.append(os.path.basename(filepath))

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(clean_files)} clean logs failed to POST: {failed_files}"

    logs = redis_lrange("processed_logs")
    assert len(logs) == len(clean_files), f"Expected {len(clean_files)} logs in Redis, found {len(logs)}"

    original_logs = []
    for filepath in clean_files:
        with open(filepath, "r") as f:
            original_logs.append(json.loads(f.read()))

    redis_logs = [json.loads(log) for log in logs]

    missing = []
    for orig in original_logs:
        if orig not in redis_logs:
            missing.append(orig)

    assert len(missing) == 0, f"{len(missing)} of {len(clean_files)} clean logs were modified or not found in Redis."

def test_evil_corpus():
    evil_dir = "/home/user/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clear_redis("processed_logs")

    failed_files = []
    for filepath in evil_files:
        with open(filepath, "rb") as f:
            payload = f.read()

        status = post_to_service(payload)
        if status not in (200, 201, 202, 204):
            failed_files.append(os.path.basename(filepath))

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(evil_files)} evil logs crashed or failed to POST: {failed_files}"

    logs = redis_lrange("processed_logs")
    assert len(logs) == len(evil_files), f"Expected {len(evil_files)} logs in Redis, found {len(logs)}"

    ssn_regex = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')

    bypassed = 0
    for log_str in logs:
        try:
            log_obj = json.loads(log_str)
        except json.JSONDecodeError:
            bypassed += 1
            continue

        def check_pii(obj):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k in ("ssn", "credit_card") and v != "[REDACTED]":
                        return True
                    if check_pii(v):
                        return True
            elif isinstance(obj, list):
                for item in obj:
                    if check_pii(item):
                        return True
            elif isinstance(obj, str):
                if ssn_regex.search(obj) and obj != "[REDACTED]":
                    return True
            return False

        if check_pii(log_obj):
            bypassed += 1

    assert bypassed == 0, f"{bypassed} of {len(evil_files)} evil logs bypassed sanitization and contained PII."

def test_generated_requests_preserve_structure_and_sanitize():
    nonce = secrets.token_hex(16)
    clean = {
        "message": "generated-" + nonce,
        "metadata": {"request_id": nonce, "ok": True, "count": 17},
        "items": [nonce, 3, None, {"kind": "clean-" + nonce}]
    }

    clear_redis("processed_logs")
    status = post_to_service(json.dumps(clean).encode("utf-8"))
    assert status in (200, 201, 202, 204), f"Generated clean log failed with status {status}"
    logs = redis_lrange("processed_logs")
    assert len(logs) == 1, f"Expected one generated clean log in Redis, found {len(logs)}"
    assert json.loads(logs[0]) == clean, "Generated clean log was not preserved unmodified"

    evil = {
        "message": "generated-evil-" + nonce,
        "request_id": nonce,
        "ssn": "123-45-6789",
        "nested": {
            "keep": "nested-" + nonce,
            "note": "contact 987-65-4321 for " + nonce,
            "credit_card": "4111111111111111"
        },
        "items": [
            {"name": "first-" + nonce, "ssn": "111-22-3333"},
            "embedded 222-33-4444 value",
            {"deep": [nonce, {"credit_card": "5555555555554444", "keep": 42}]}
        ]
    }

    clear_redis("processed_logs")
    status = post_to_service(json.dumps(evil).encode("utf-8"))
    assert status in (200, 201, 202, 204), f"Generated evil log failed with status {status}"
    logs = redis_lrange("processed_logs")
    assert len(logs) == 1, f"Expected one generated evil log in Redis, found {len(logs)}"
    try:
        actual = json.loads(logs[0])
    except json.JSONDecodeError as exc:
        pytest.fail(f"Generated evil output was not valid JSON: {exc}")
    assert_preserved_and_sanitized(evil, actual)
    assert not contains_pii(actual), "Generated evil output still contains PII"
TEST_EOF

if (
    set -e
    test -f /home/user/app/sanitizer/src/main.rs
    test -f /home/user/app/sanitizer/Cargo.toml
    cd /home/user/app/sanitizer
    "$HOME/.cargo/bin/cargo" build --release
    killall sanitizer >/dev/null 2>&1 || true
    killall redis-server >/dev/null 2>&1 || true
    redis-server --daemonize yes
    for i in $(seq 1 30); do
        redis-cli PING 2>/dev/null | grep -q PONG && break
        sleep 1
    done
    redis-cli PING | grep -q PONG
    REDIS_URL=redis://127.0.0.1:6379 BIND_ADDR=127.0.0.1:8080 /home/user/app/sanitizer/target/release/sanitizer >/tmp/sanitizer-verifier.log 2>&1 &
    ready=0
    for i in $(seq 1 60); do
        if curl -sS -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
            ready=1
            break
        fi
        sleep 1
    done
    test "$ready" = "1"
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
