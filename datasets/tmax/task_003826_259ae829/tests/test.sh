#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import random
import re
import signal
import socket
import subprocess
import threading
import time
import uuid

import pytest
import redis
import requests

AGGREGATOR = "/app/aggregator/server"
DASHBOARD_URL = "http://127.0.0.1:9000/api/stats"


def wait_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"Port {port} did not become available")


def wait_http(timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = requests.get(DASHBOARD_URL, timeout=1)
            if response.status_code < 500:
                return
            last = f"HTTP {response.status_code}: {response.text}"
        except Exception as exc:
            last = exc
        time.sleep(0.1)
    raise AssertionError(f"Dashboard did not become available: {last}")


def flattened_ini(path):
    parser = configparser.ConfigParser()
    assert parser.read(path), f"Could not read {path}"
    result = {}
    for section in parser.sections():
        for key, value in parser.items(section):
            result[f"{section}.{key}".lower()] = str(value).strip()
    return result


def flatten_json(value, prefix=""):
    result = {}
    if isinstance(value, dict):
        for key, child in value.items():
            name = f"{prefix}.{key}" if prefix else str(key)
            result.update(flatten_json(child, name.lower()))
    else:
        result[prefix.lower()] = str(value).strip()
    return result


def has_setting(values, words, expected):
    expected = str(expected)
    return any(all(word in key for word in words) and value == expected
               for key, value in values.items())


def redis_dump(client):
    parts = []
    for key in client.scan_iter(match="*"):
        key_text = key.decode("utf-8", "replace") if isinstance(key, bytes) else str(key)
        parts.append(key_text)
        kind = client.type(key)
        kind = kind.decode() if isinstance(kind, bytes) else kind
        if kind == "string":
            parts.append(str(client.get(key)))
        elif kind == "hash":
            for field, value in client.hgetall(key).items():
                parts.extend([str(field), str(value)])
        elif kind in ("set", "zset"):
            values = client.smembers(key) if kind == "set" else client.zrange(key, 0, -1, withscores=True)
            parts.extend(map(str, values))
        elif kind == "list":
            parts.extend(map(str, client.lrange(key, 0, -1)))
        elif kind == "stream":
            parts.extend(map(str, client.xrange(key)))
    return "\n".join(parts)


def query_stats():
    response = requests.get(DASHBOARD_URL, timeout=5)
    assert response.status_code == 200, f"Dashboard returned HTTP {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Dashboard did not return valid JSON: {response.text}")
    assert isinstance(data, dict), f"Dashboard JSON must be an object, got {data!r}"
    return data


def assert_expected(data, expected):
    for device_id, totals in expected.items():
        assert device_id in data, f"Device {device_id} not found in aggregated stats. Got: {data}"
        stats = data[device_id]
        assert stats.get("count") == totals["count"], \
            f"Expected count {totals['count']} for {device_id}, got {stats.get('count')}"
        assert stats.get("sum") == totals["sum"], \
            f"Expected sum {totals['sum']} for {device_id}, got {stats.get('sum')}"


def test_01_poison_pill_extracted_exactly():
    path = "/home/user/poison_pill.txt"
    assert os.path.isfile(path), f"File {path} does not exist"
    with open("/app/core/core.aggregator", "rb") as core:
        match = re.search(rb"POISON_PILL[^\s\x00]*", core.read())
    assert match, "No poison-pill string was found in the supplied core dump"
    expected = match.group(0).decode("utf-8")
    with open(path, encoding="utf-8") as submitted:
        actual = submitted.read().strip()
    assert actual == expected, f"Expected exact poison pill {expected!r}, found {actual!r}"


def test_02_configuration_and_compiled_artifact():
    agg = flattened_ini("/app/aggregator/config.ini")
    assert has_setting(agg, ("ingestion", "port"), 8080), agg
    assert has_setting(agg, ("query", "port"), 8081), agg
    assert any("host" in key and value == "127.0.0.1" for key, value in agg.items()), agg
    assert has_setting(agg, ("redis", "host"), "127.0.0.1"), agg
    assert has_setting(agg, ("redis", "port"), 6379), agg

    with open("/app/dashboard/config.json", encoding="utf-8") as handle:
        dashboard = flatten_json(json.load(handle))
    assert has_setting(dashboard, ("aggregator", "host"), "127.0.0.1"), dashboard
    assert has_setting(dashboard, ("aggregator", "port"), 8081), dashboard
    assert has_setting(dashboard, ("redis", "host"), "127.0.0.1"), dashboard
    assert has_setting(dashboard, ("redis", "port"), 6379), dashboard
    assert any(("dashboard" in key or "listen" in key or "http" in key) and "host" in key and value == "127.0.0.1"
               for key, value in dashboard.items()), dashboard
    assert any(("dashboard" in key or "listen" in key or "http" in key) and "port" in key and value == "9000"
               for key, value in dashboard.items()), dashboard

    assert os.path.isfile(AGGREGATOR), "Compiled aggregator binary is missing"
    assert os.access(AGGREGATOR, os.X_OK), "Compiled aggregator is not executable"
    with open(AGGREGATOR, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Aggregator artifact is not a compiled ELF executable"
    result = subprocess.run(["make", "-q", "server"], cwd="/app/aggregator")
    assert result.returncode == 0, "Aggregator binary is missing or older than its source; compile it with the provided Makefile"

    source = open("/app/aggregator/src/server.cpp", encoding="utf-8").read()
    assert "usleep(100000)" not in source.replace(" ", ""), "Original blocking delay remains in server.cpp"


def test_03_randomized_concurrent_pipeline_and_redis_persistence():
    subprocess.run(["pkill", "-9", "-x", "server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-9", "-f", "/app/dashboard/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-9", "-x", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    subprocess.run(["redis-server", "--bind", "127.0.0.1", "--port", "6379", "--daemonize", "yes"], check=True)
    redis_client = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            if redis_client.ping():
                break
        except Exception:
            time.sleep(0.1)
    else:
        pytest.fail("Redis did not start on 127.0.0.1:6379")
    redis_client.flushdb()

    agg_log = open("/tmp/aggregator-verifier.log", "w")
    dash_log = open("/tmp/dashboard-verifier.log", "w")
    aggregator = subprocess.Popen([AGGREGATOR], cwd="/app/aggregator", stdout=agg_log, stderr=subprocess.STDOUT)
    dashboard = subprocess.Popen(["python3", "/app/dashboard/app.py"], stdout=dash_log, stderr=subprocess.STDOUT)

    wait_port(8080)
    wait_port(8081)
    wait_port(9000)
    wait_http()
    assert aggregator.poll() is None, "Compiled aggregator exited during startup"
    assert dashboard.poll() is None, "Dashboard exited during startup"

    token = uuid.uuid4().hex[:10]
    devices = [f"DEV_VERIFY_{token}_{i}" for i in range(4)]
    rng = random.SystemRandom()
    jobs = []
    expected = {device: {"count": 0, "sum": 0} for device in devices}
    for thread_index in range(9):
        messages = []
        for item_index in range(rng.randint(53, 79)):
            device = devices[(thread_index + item_index) % len(devices)]
            value = rng.randint(2, 31)
            messages.append((device, value))
            expected[device]["count"] += 1
            expected[device]["sum"] += value
        jobs.append(messages)

    errors = []
    start = time.monotonic()

    def send_messages(messages):
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=3) as connection:
                connection.settimeout(3)
                for device, value in messages:
                    connection.sendall(f"SECRET_AUTH_99:{device}:{value}\n".encode())
        except Exception as exc:
            errors.append(exc)

    threads = [threading.Thread(target=send_messages, args=(job,)) for job in jobs]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=8)
    assert all(not thread.is_alive() for thread in threads), "Concurrent ingestion deadlocked"
    assert not errors, f"Errors occurred during concurrent ingestion: {errors}"
    assert time.monotonic() - start < 8, "Concurrent ingestion is still blocked by the original critical-section bottleneck"

    deadline = time.time() + 10
    last_data = None
    while time.time() < deadline:
        try:
            last_data = query_stats()
            assert_expected(last_data, expected)
            break
        except (AssertionError, requests.RequestException):
            time.sleep(0.2)
    else:
        assert_expected(last_data or {}, expected)

    dump = redis_dump(redis_client)
    for device in devices:
        assert device in dump, f"Redis contains no data for ingested device {device}; dump was {dump!r}"

    # The dashboard must actually depend on the aggregator's internal query service.
    aggregator.send_signal(signal.SIGKILL)
    aggregator.wait(timeout=3)
    time.sleep(0.3)
    served_same_data = False
    try:
        response = requests.get(DASHBOARD_URL, timeout=3)
        if response.status_code == 200:
            candidate = response.json()
            try:
                assert_expected(candidate, expected)
                served_same_data = True
            except AssertionError:
                pass
    except (requests.RequestException, ValueError):
        pass
    assert not served_same_data, "Dashboard still served the aggregation after port 8081 was stopped; it is not querying the C++ aggregator"

    # Restart only the compiled aggregator. The prior randomized aggregation must
    # survive via Redis and become queryable again.
    aggregator = subprocess.Popen([AGGREGATOR], cwd="/app/aggregator", stdout=agg_log, stderr=subprocess.STDOUT)
    wait_port(8080)
    wait_port(8081)
    deadline = time.time() + 10
    last_data = None
    while time.time() < deadline:
        try:
            last_data = query_stats()
            assert_expected(last_data, expected)
            break
        except (AssertionError, requests.RequestException):
            time.sleep(0.2)
    else:
        assert_expected(last_data or {}, expected)
    assert aggregator.poll() is None, "Restarted compiled aggregator exited unexpectedly"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
