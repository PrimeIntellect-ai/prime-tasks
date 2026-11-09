#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import socket
import subprocess
import urllib.request
import urllib.error
import importlib.util
import configparser
import uuid
import pytest

APP = "/home/user/app"
GATEWAY = f"{APP}/gateway"


def post(url, obj):
    data = json.dumps(obj).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def load_validator():
    path = f"{GATEWAY}/validator.py"
    assert os.path.isfile(path), f"Validator module {path} is missing."
    spec = importlib.util.spec_from_file_location("submitted_validator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "validate_build_request"), "Validator module missing 'validate_build_request' function."
    return module.validate_build_request


def test_setup_complete_log():
    path = f"{APP}/setup_complete.log"
    assert os.path.isfile(path), f"Log file {path} is missing."
    assert "SYSTEM_READY" in open(path).read(), "setup_complete.log does not contain SYSTEM_READY."


def test_validator_logic_and_unseen_inputs():
    validate = load_validator()

    clean_dir = f"{APP}/corpora/clean"
    evil_dir = f"{APP}/corpora/evil"
    clean_failed, evil_failed = [], []
    for name in os.listdir(clean_dir):
        path = os.path.join(clean_dir, name)
        if os.path.isfile(path):
            try:
                if validate(open(path).read()) is not True:
                    clean_failed.append(name)
            except Exception:
                clean_failed.append(name)
    for name in os.listdir(evil_dir):
        path = os.path.join(evil_dir, name)
        if os.path.isfile(path):
            try:
                if validate(open(path).read()) is not False:
                    evil_failed.append(name)
            except Exception:
                pass
    assert not clean_failed and not evil_failed, f"Corpus failures: clean={clean_failed}, evil={evil_failed}"

    token = uuid.uuid4().hex
    unseen_clean = [
        json.dumps({"repository": "repo-" + token, "commit_hash": "deadbeef" + token[:8], "build_target": "services/api"}),
        json.dumps({"build_target": "dist/release", "commit_hash": "0123456789abcdef", "repository": "org/project", "extra": {"language": "rust"}}),
    ]
    unseen_bad = [
        "not json " + token,
        json.dumps([{"repository": "r", "commit_hash": "c", "build_target": "src"}]),
        json.dumps({"repository": "r", "commit_hash": "c"}),
        json.dumps({"repository": "r", "commit_hash": "c", "build_target": "safe/../../secret"}),
        json.dumps({"repository": "r", "commit_hash": "c", "build_target": "..\\..\\secret"}),
        json.dumps({"repository": "", "commit_hash": "c", "build_target": "src"}),
        json.dumps({"repository": "r", "commit_hash": 123, "build_target": "src"}),
        "[" * 2000 + "]" * 2000,
    ]
    for payload in unseen_clean:
        try:
            assert validate(payload) is True, f"Rejected unseen valid payload: {payload}"
        except Exception as e:
            pytest.fail(f"Validator raised on unseen valid payload: {e}")
    for payload in unseen_bad:
        try:
            assert validate(payload) is False, f"Accepted unseen invalid payload: {payload[:100]}"
        except Exception:
            pass


def test_config():
    path = f"{GATEWAY}/config.ini"
    assert os.path.isfile(path), "config.ini is missing"
    cfg = configparser.ConfigParser()
    cfg.read(path)
    assert cfg.get("DEFAULT", "REDIS_HOST") in ("localhost", "127.0.0.1")
    assert cfg.getint("DEFAULT", "REDIS_PORT") == 6379
    assert cfg.get("DEFAULT", "DISPATCHER_URL").rstrip("/") == "http://localhost:5001"
    assert cfg.getboolean("DEFAULT", "RATE_LIMIT_ENABLED") is True


def test_real_services_and_gateway_behavior():
    # Redis must speak Redis, not merely accept TCP connections.
    pong = subprocess.run(["redis-cli", "-h", "localhost", "-p", "6379", "PING"], capture_output=True, text=True, timeout=5)
    assert pong.returncode == 0 and pong.stdout.strip() == "PONG", "Redis is not running on port 6379"
    subprocess.run(["redis-cli", "-h", "localhost", "-p", "6379", "FLUSHDB"], check=True, capture_output=True, timeout=5)

    # The supplied dispatcher must exhibit its documented catch-all behavior.
    marker = uuid.uuid4().hex
    status, body = post(f"http://localhost:5001/audit/{marker}", {"probe": marker})
    assert status == 200, "Dispatcher did not return 200"
    assert json.loads(body.decode()).get("status") == "dispatched", "Wrong dispatcher response"

    url = "http://localhost:5000/webhook"
    valid = {"repository": "live-" + marker, "commit_hash": marker, "build_target": "pkg/component"}
    invalid = {"repository": "live-" + marker, "commit_hash": marker, "build_target": "../../etc/passwd"}

    # Invalid requests demonstrate that the live gateway invokes validation.
    status, _ = post(url, invalid)
    assert status == 400, f"Live gateway accepted path traversal (status {status})"

    # Reset because this gateway counts all requests before validation.
    subprocess.run(["redis-cli", "-h", "localhost", "-p", "6379", "FLUSHDB"], check=True, capture_output=True, timeout=5)
    for i in range(5):
        status, body = post(url, valid)
        assert status == 200, f"Valid request {i+1} returned {status}"
        assert json.loads(body.decode()).get("status") == "ok", "Gateway response is not the supplied app's response"
    status, _ = post(url, valid)
    assert status == 429, f"Expected 429 on sixth request, got {status}"

    # Confirm rate-limit state is actually held in Redis under the supplied gateway's key.
    value = subprocess.run(["redis-cli", "-h", "localhost", "-p", "6379", "GET", "rate_limit:127.0.0.1"], capture_output=True, text=True, timeout=5)
    assert value.returncode == 0 and value.stdout.strip() == "5", "Gateway is not using Redis for rate limiting"

    # Dispatcher remains independently reachable after routed requests.
    status, body = post(f"http://localhost:5001/after/{marker}", {"probe": "after"})
    assert status == 200 and json.loads(body.decode()).get("status") == "dispatched"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
