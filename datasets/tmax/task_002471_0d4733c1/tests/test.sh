#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import importlib.util
import json
import os
import re
import secrets
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

import pytest

BASE_URL = "https://127.0.0.1:8443"
SSL_CONTEXT = ssl.create_default_context()
SSL_CONTEXT.check_hostname = False
SSL_CONTEXT.verify_mode = ssl.CERT_NONE


def load_validator():
    validator_path = "/home/user/validator.py"
    assert os.path.exists(validator_path), f"Missing {validator_path}"
    assert os.path.isfile(validator_path), f"Not a regular file: {validator_path}"

    module_name = "submitted_validator_" + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(module_name, validator_path)
    assert spec is not None and spec.loader is not None, "Could not load validator.py"
    validator = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = validator
    try:
        spec.loader.exec_module(validator)
    except Exception as exc:
        pytest.fail(f"Failed to load validator.py: {exc}")

    assert hasattr(validator, "validate_payload"), "Missing validate_payload function in validator.py"
    assert callable(validator.validate_payload), "validate_payload is not callable"
    return validator


def request(path, payload=None):
    req = urllib.request.Request(
        BASE_URL + path,
        data=payload,
        headers={"Content-Type": "application/json"} if payload is not None else {},
    )
    try:
        with urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to {path}: {exc}")


def expected_safe(raw):
    try:
        value = json.loads(raw.decode("utf-8"))
    except Exception:
        return False

    def has_traversal(item):
        if isinstance(item, dict):
            return any(
                "../" in str(key)
                or "..\\" in str(key)
                or has_traversal(val)
                for key, val in item.items()
            )
        if isinstance(item, list):
            return any(has_traversal(val) for val in item)
        if isinstance(item, str):
            return "../" in item or "..\\" in item
        return False

    if has_traversal(value):
        return False
    if isinstance(value, dict) and isinstance(value.get("log_data"), str):
        if len(value["log_data"]) > 1024:
            return False
    return True


def test_adversarial_corpus():
    validator = load_validator()
    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"

    assert os.path.exists(clean_dir), f"Missing {clean_dir}"
    assert os.path.exists(evil_dir), f"Missing {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert clean_files, "No clean corpus files found"
    assert evil_files, "No evil corpus files found"

    clean_modified = []
    evil_bypassed = []
    for path in clean_files:
        try:
            result = validator.validate_payload(path)
        except Exception as exc:
            clean_modified.append(f"{os.path.basename(path)} (raised {exc!r})")
        else:
            if result is not True:
                clean_modified.append(os.path.basename(path))

    for path in evil_files:
        try:
            result = validator.validate_payload(path)
        except Exception as exc:
            evil_bypassed.append(f"{os.path.basename(path)} (raised {exc!r})")
        else:
            if result is not False:
                evil_bypassed.append(os.path.basename(path))

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean rejected: {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil accepted or errored: {', '.join(evil_bypassed)}")
    assert not errors, " | ".join(errors)


def test_validator_generated_payloads():
    validator = load_validator()
    token = secrets.token_hex(24)
    cases = [
        (json.dumps({"log_data": "safe-" + token, "nested": [1, {"message": token}]}).encode(), True),
        (json.dumps({"log_data": "x" * 1024, "tag": token}).encode(), True),
        (json.dumps({"log_data": "x" * 1025, "tag": token}).encode(), False),
        (json.dumps({"log_data": token, "nested": {"../secret": "value"}}).encode(), False),
        (json.dumps({"log_data": token, "nested": ["prefix/../target"]}).encode(), False),
        (json.dumps({"log_data": token, "nested": {"value": "..\\private"}}).encode(), False),
        (b'{"log_data": "unterminated",', False),
    ]

    for raw, expected in cases:
        fd, path = tempfile.mkstemp(prefix="payload_" + secrets.token_hex(6) + "_", suffix=".json")
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(raw)
            try:
                actual = validator.validate_payload(path)
            except Exception as exc:
                pytest.fail(f"validate_payload raised instead of returning False/True: {exc!r}")
            assert actual is expected, f"Wrong result for generated payload; expected {expected}, got {actual!r}"
        finally:
            if os.path.exists(path):
                os.unlink(path)


def test_certs_exist():
    crt_path = "/home/user/app/certs/server.crt"
    key_path = "/home/user/app/certs/server.key"
    assert os.path.exists(crt_path), f"Missing certificate: {crt_path}"
    assert os.path.exists(key_path), f"Missing key: {key_path}"
    assert os.path.getsize(crt_path) > 0, f"Empty certificate: {crt_path}"
    assert os.path.getsize(key_path) > 0, f"Empty key: {key_path}"


def test_health_endpoint():
    status, body = request("/health")
    assert status == 200, f"Expected 200 OK, got {status}"
    data = json.loads(body.decode("utf-8"))
    assert data.get("status") == "ok", "Expected status: ok"
    assert data.get("redis") == "connected", "Expected redis: connected"


def redis_ping():
    result = subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.returncode == 0 and result.stdout.strip() == "PONG"


def test_health_depends_on_redis_6379():
    assert redis_ping(), "Redis is not reachable on port 6379"
    stopped = False
    try:
        subprocess.run(
            ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "shutdown", "nosave"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        stopped = True
        deadline = time.time() + 5
        while redis_ping() and time.time() < deadline:
            time.sleep(0.1)
        assert not redis_ping(), "Redis did not stop for the health dependency test"

        status, _ = request("/health")
        assert status != 200, "/health returned HTTP 200 while Redis on port 6379 was unavailable"
    finally:
        if stopped and not redis_ping():
            subprocess.run(
                ["redis-server", "--port", "6379", "--daemonize", "yes"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            deadline = time.time() + 8
            while not redis_ping() and time.time() < deadline:
                time.sleep(0.1)
            assert redis_ping(), "Failed to restore Redis after health dependency test"

    status, body = request("/health")
    assert status == 200, f"Health did not recover after Redis restart; got {status}"
    data = json.loads(body.decode("utf-8"))
    assert data.get("status") == "ok" and data.get("redis") == "connected"


def test_ingest_endpoint_clean():
    clean_file = "/home/user/corpus/clean/test1.json"
    if not os.path.exists(clean_file):
        clean_files = [f for f in os.listdir("/home/user/corpus/clean") if f.endswith(".json")]
        assert clean_files, "No clean files available to test ingest endpoint"
        clean_file = os.path.join("/home/user/corpus/clean", clean_files[0])

    with open(clean_file, "rb") as handle:
        payload = handle.read()
    status, _ = request("/ingest", payload)
    assert status == 200, f"Expected 200 OK for clean payload, got {status}"


def test_ingest_endpoint_generated_payloads():
    token = secrets.token_hex(20)
    payloads = [
        (json.dumps({"log_data": "generated-safe-" + token, "metadata": {"id": token}}).encode(), 200),
        (json.dumps({"log_data": "z" * 1025, "id": token}).encode(), 400),
        (json.dumps({"log_data": token, "nested": {"key": "../../etc/passwd"}}).encode(), 400),
        (json.dumps({"log_data": token, "..\\hidden": "value"}).encode(), 400),
        (b'{"log_data": "broken",', 400),
    ]
    for payload, expected_status in payloads:
        status, _ = request("/ingest", payload)
        assert status == expected_status, f"Expected {expected_status} for generated ingest payload, got {status}"


def test_test_stack_script_artifacts():
    script_path = "/home/user/test_stack.sh"
    assert os.path.exists(script_path), f"Missing {script_path}"
    assert os.path.isfile(script_path), f"Not a regular file: {script_path}"

    health_res = "/home/user/health_result.json"
    ingest_res = "/home/user/ingest_results.txt"
    for artifact in (health_res, ingest_res):
        if os.path.exists(artifact):
            os.unlink(artifact)

    token = secrets.token_hex(10)
    probe_safe = os.path.join("/home/user/corpus/evil", f"generated_safe_{token}.json")
    probe_evil = os.path.join("/home/user/corpus/clean", f"generated_evil_{token}.json")
    with open(probe_safe, "wb") as handle:
        handle.write(json.dumps({"log_data": "safe-probe-" + token}).encode())
    with open(probe_evil, "wb") as handle:
        handle.write(json.dumps({"log_data": "probe/../escape", "id": token}).encode())

    try:
        expected = []
        for directory in ("/home/user/corpus/clean", "/home/user/corpus/evil"):
            for filename in os.listdir(directory):
                path = os.path.join(directory, filename)
                if not os.path.isfile(path):
                    continue
                with open(path, "rb") as handle:
                    raw = handle.read()
                expected.append((filename, "200" if expected_safe(raw) else "400"))

        result = subprocess.run(
            ["bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert result.returncode == 0, (
            f"test_stack.sh failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.exists(health_res), f"Missing {health_res} generated by script"
        assert os.path.exists(ingest_res), f"Missing {ingest_res} generated by script"
        assert os.path.getsize(health_res) > 0, f"Empty artifact: {health_res}"
        assert os.path.getsize(ingest_res) > 0, f"Empty artifact: {ingest_res}"

        with open(health_res, "r", encoding="utf-8") as handle:
            health_data = json.load(handle)
        assert health_data.get("status") == "ok", "health_result.json does not contain status ok"
        assert health_data.get("redis") == "connected", "health_result.json does not report Redis connected"

        actual = []
        line_pattern = re.compile(r"^(.+): ([0-9]{3})$")
        with open(ingest_res, "r", encoding="utf-8") as handle:
            lines = [line.rstrip("\n") for line in handle]
        assert lines, "ingest_results.txt is empty"
        for line in lines:
            match = line_pattern.fullmatch(line)
            assert match, f"Invalid ingest result line: {line!r}"
            actual.append((match.group(1), match.group(2)))

        assert collections.Counter(actual) == collections.Counter(expected), (
            f"ingest_results.txt did not contain exactly one correct result for every corpus file; "
            f"expected {collections.Counter(expected)}, got {collections.Counter(actual)}"
        )
    finally:
        for path in (probe_safe, probe_evil):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
