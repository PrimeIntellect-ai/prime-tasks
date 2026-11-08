#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import secrets
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest
import redis

SERVICE_PROCESS = None


def send_json(url, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return None


def send_payload(url, filepath):
    with open(filepath, "rb") as f:
        data = f.read()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return None


def services_ready():
    try:
        redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=1).ping()
        req = urllib.request.Request("http://127.0.0.1:8080/intake", method="GET")
        try:
            urllib.request.urlopen(req, timeout=1)
        except urllib.error.HTTPError:
            pass
        return True
    except Exception:
        return False


@pytest.fixture(scope="module", autouse=True)
def setup_services():
    global SERVICE_PROCESS
    script_path = "/app/start_all.sh"
    assert os.path.isfile(script_path), f"Missing startup script: {script_path}"

    subprocess.run(["pkill", "-f", "gunicorn"], check=False)
    subprocess.run(["pkill", "-f", "nginx"], check=False)
    subprocess.run(["pkill", "-f", "redis-server"], check=False)
    time.sleep(1)

    SERVICE_PROCESS = subprocess.Popen(
        ["bash", script_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 15
    while time.time() < deadline and not services_ready():
        time.sleep(0.25)
    assert services_ready(), "Services did not become ready when started via /app/start_all.sh"

    yield

    subprocess.run(["pkill", "-f", "nginx"], check=False)
    subprocess.run(["pkill", "-f", "gunicorn"], check=False)
    subprocess.run(["pkill", "-f", "redis-server"], check=False)


def test_nginx_config_updated():
    path = "/app/nginx/nginx.conf"
    assert os.path.isfile(path), f"Missing Nginx config: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "127.0.0.1:5000" in content, "Nginx config does not proxy to 127.0.0.1:5000"
    assert "/intake" in content, "Nginx config missing /intake location"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"\blocation\s+(?:=\s*)?/intake(?:\s|\{)", uncommented), \
        "Nginx config has no active /intake location"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000(?:/intake)?/?\s*;", uncommented), \
        "Nginx config has no active proxy_pass to Flask"

    result = subprocess.run(
        ["nginx", "-t", "-c", path, "-g", "pid /tmp/verifier-nginx.pid;"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert result.returncode == 0, f"Nginx configuration is invalid: {result.stdout}"


def test_flask_env_updated():
    path = "/app/flask/.env"
    assert os.path.isfile(path), f"Missing Flask env file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "REDIS_HOST=127.0.0.1" in content, "Flask .env missing REDIS_HOST=127.0.0.1"
    assert "REDIS_PORT=6379" in content, "Flask .env missing REDIS_PORT=6379"

    values = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("'\"")
    assert values.get("REDIS_HOST") == "127.0.0.1", "Active REDIS_HOST is not 127.0.0.1"
    assert values.get("REDIS_PORT") == "6379", "Active REDIS_PORT is not 6379"


def test_clean_corpus_accepted():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filename in clean_files:
        status = send_payload("http://127.0.0.1:8080/intake", os.path.join(clean_dir, filename))
        if status != 200:
            failed_files.append((filename, status))
    if failed_files:
        failures = ", ".join(f"{f} (status {s})" for f, s in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {failures}")


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filename in evil_files:
        status = send_payload("http://127.0.0.1:8080/intake", os.path.join(evil_dir, filename))
        if status != 400:
            failed_files.append((filename, status))
    if failed_files:
        failures = ", ".join(f"{f} (status {s})" for f, s in failed_files)
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {failures}")


def build_dynamic_cases():
    token = secrets.token_hex(12)
    valid = []
    invalid = []

    for i in range(8):
        start = (10 ** 30) + secrets.randbits(100) + i
        duration = secrets.randbelow(10 ** 9) + 1
        names = [f"{token}_{i}_{j}" for j in range(5)]
        graph = {
            names[0]: [names[1], names[2]],
            names[1]: [names[3]],
            names[2]: [names[3], names[4]],
            names[3]: [],
        }
        payload = {
            "start_ns": str(start),
            "end_ns": str(start + duration),
            "duration_ns": str(duration),
            "component_tree": graph,
            "verification_nonce": f"valid-{token}-{i}",
        }
        valid.append(payload)

        precision_bad = dict(payload)
        precision_bad["end_ns"] = str(start + duration + (1 if i % 2 == 0 else -1))
        precision_bad["verification_nonce"] = f"precision-{token}-{i}"
        invalid.append(precision_bad)

        cycle_names = [f"cycle_{token}_{i}_{j}" for j in range(2 + secrets.randbelow(5))]
        cycle_graph = {cycle_names[j]: [cycle_names[(j + 1) % len(cycle_names)]] for j in range(len(cycle_names))}
        cycle_bad = {
            "start_ns": str(start),
            "end_ns": str(start + duration),
            "duration_ns": str(duration),
            "component_tree": cycle_graph,
            "verification_nonce": f"cycle-{token}-{i}",
        }
        invalid.append(cycle_bad)

    malformed = dict(valid[0])
    malformed["duration_ns"] = "5000000.0"
    malformed["verification_nonce"] = f"malformed-{token}"
    invalid.append(malformed)
    return valid, invalid


def test_sanitizer_and_live_pipeline_on_dynamic_inputs_with_redis_persistence():
    sanitizer_path = "/app/flask/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer: {sanitizer_path}"
    spec = importlib.util.spec_from_file_location("submitted_sanitizer", sanitizer_path)
    sanitizer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sanitizer)
    assert callable(getattr(sanitizer, "validate", None)), "sanitizer.py has no callable validate function"
    assert callable(getattr(sanitizer, "check_cycles", None)), "sanitizer.py has no callable check_cycles function"

    valid_cases, invalid_cases = build_dynamic_cases()
    for payload in valid_cases:
        assert sanitizer.validate(payload) is True, "Sanitizer rejected a generated valid metric"
    for payload in invalid_cases:
        try:
            result = sanitizer.validate(payload)
        except RecursionError:
            pytest.fail("Sanitizer raised RecursionError on a generated cycle")
        assert result is False, "Sanitizer accepted a generated invalid metric"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    client.flushdb()

    for payload in valid_cases:
        assert send_json("http://127.0.0.1:8080/intake", payload) == 200, \
            "Pipeline rejected a generated valid metric"
    for payload in invalid_cases:
        assert send_json("http://127.0.0.1:8080/intake", payload) == 400, \
            "Pipeline failed to reject a generated invalid metric"

    saved_raw = client.lrange("uptime_metrics", 0, -1)
    assert len(saved_raw) == len(valid_cases), \
        "Redis must contain exactly the accepted generated metrics and no rejected metrics"
    saved = [json.loads(item.decode("utf-8")) for item in saved_raw]
    expected_nonces = {p["verification_nonce"] for p in valid_cases}
    saved_nonces = {p.get("verification_nonce") for p in saved}
    assert saved_nonces == expected_nonces, "Accepted generated metrics were not saved to Redis intact"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
