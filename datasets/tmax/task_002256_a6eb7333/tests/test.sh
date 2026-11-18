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
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import glob
import importlib
import inspect
import json
import math
import os
import secrets
import socket
import sys
import time

import pytest
import redis
import requests

HOST = "127.0.0.1"
TCP_PORT = 5000
STATS_URL = "http://127.0.0.1:8000/stats"


def entropy_bits(message):
    counts = collections.Counter(message)
    n = len(message)
    if not n:
        return 0.0
    return -sum((count / n) * math.log2(count / n) for count in counts.values())


def send_payload(payload):
    try:
        with socket.create_connection((HOST, TCP_PORT), timeout=2) as sock:
            sock.sendall(payload)
    except Exception as exc:
        pytest.fail(f"Failed to connect and send data to TCP Ingestor at {HOST}:{TCP_PORT}: {exc}")


def wait_for_lengths(client, logs, dead, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if client.llen("logs") == logs and client.llen("dead_letter") == dead:
            return
        time.sleep(0.05)
    assert client.llen("logs") == logs, "Ingestor did not place the expected valid logs in Redis"
    assert client.llen("dead_letter") == dead, "Ingestor did not place the expected corrupt payloads in Redis"


def get_stats():
    try:
        response = requests.get(STATS_URL, timeout=5)
        response.raise_for_status()
    except requests.RequestException as exc:
        pytest.fail(f"Failed to reach HTTP Processor at {STATS_URL}: {exc}")
    data = response.json()
    assert "valid_logs_processed" in data, "Response missing 'valid_logs_processed'"
    assert "dead_letters" in data, "Response missing 'dead_letters'"
    assert "latest_entropy" in data, "Response missing 'latest_entropy'"
    return data


def process_table():
    entries = []
    for path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            raw = open(path, "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
            cwd = os.readlink(os.path.join(os.path.dirname(path), "cwd"))
            entries.append((raw, cwd))
        except (OSError, PermissionError):
            pass
    return entries


def test_pipeline_integration_and_artifacts():
    # Confirm that the required long-running programs, rather than only unrelated
    # stand-in listeners, are present.
    processes = process_table()
    assert any("redis-server" in cmd for cmd, _ in processes), "redis-server is not running"
    assert any("/app/ingestor.py" in cmd for cmd, _ in processes), "/app/ingestor.py is not running"
    assert any(
        ("gunicorn" in cmd and "app:app" in cmd)
        or ("app.py" in cmd and cwd == "/app/processor")
        for cmd, cwd in processes
    ), "The Flask processor is not running from /app/processor"

    client = redis.Redis(host=HOST, port=6379, db=0)
    assert client.ping() is True
    info = client.info("server")
    assert "redis_version" in info
    assert int(client.config_get("port")["port"]) == 6379

    # The compiled artifact must exist, be a native extension, and independently
    # implement the corrected formula on verifier-generated nonzero-entropy data.
    extension_paths = glob.glob("/app/processor/ext/entropy_ext*.so")
    assert extension_paths, "entropy_ext was not built in place"
    assert any(open(path, "rb").read(4) == b"\x7fELF" for path in extension_paths), "entropy_ext is not an ELF extension"

    sys.path.insert(0, "/app/processor/ext")
    sys.modules.pop("entropy_ext", None)
    importlib.invalidate_caches()
    entropy_ext = importlib.import_module("entropy_ext")
    assert os.path.realpath(entropy_ext.__file__).startswith("/app/processor/ext/")
    assert entropy_ext.__file__.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES))
    assert inspect.isbuiltin(entropy_ext.calculate_entropy), "calculate_entropy is not provided by the C extension"

    token = secrets.token_hex(12)
    entropy_messages = [
        "AABB",
        "abcabcabc",
        "AAAAABBC",
        token,
        token + token[:5] + "XYZ",
        "0123456789abcdef",
        "",
    ]
    for message in entropy_messages:
        actual = entropy_ext.calculate_entropy(message)
        expected = entropy_bits(message)
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (
            f"C extension entropy mismatch for {message!r}: expected {expected}, got {actual}"
        )

    # Ensure the processor source is wired to the native extension rather than
    # merely shipping an unused .so alongside a separate implementation.
    processor_tree = ast.parse(open("/app/processor/app.py", encoding="utf-8").read())
    calls_extension = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "calculate_entropy"
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "entropy_ext"
        for node in ast.walk(processor_tree)
    )
    assert calls_extension, "Processor is not wired to entropy_ext.calculate_entropy"

    # Exercise the real TCP-to-Redis path with unpredictable content and verify
    # exact queue contents, including literal '?' replacement for invalid UTF-8.
    client.flushdb()
    first_message = "mix-" + token[:8] + "-AABBC"
    second_message = "latest-" + token[8:] + "-XYZXYZ"
    valid_objects = [
        {"message": first_message, "marker": token, "sequence": 1},
        {"message": second_message, "marker": token, "sequence": 2},
    ]
    malformed = ('{"message":"broken-' + token + '"\n').encode("utf-8")
    invalid = b"\xff" + token.encode("ascii") + b"\xfe\n"

    send_payload(json.dumps(valid_objects[0]).encode("utf-8") + b"\n")
    send_payload(malformed)
    send_payload(invalid)
    send_payload(json.dumps(valid_objects[1]).encode("utf-8") + b"\n")
    wait_for_lengths(client, 2, 2)

    stored_logs = [json.loads(item) for item in client.lrange("logs", 0, -1)]
    assert stored_logs == [valid_objects[1], valid_objects[0]], "Valid JSON was not serialized into the logs list correctly"
    dead_payloads = set(client.lrange("dead_letter", 0, -1))
    expected_dead = {
        malformed,
        ("?" + token + "?\n").encode("utf-8"),
    }
    assert dead_payloads == expected_dead, "Corrupt payloads were not preserved in dead_letter with invalid bytes replaced by '?'"

    data = get_stats()
    assert data["valid_logs_processed"] == 2
    assert data["dead_letters"] == 2
    expected = entropy_bits(second_message)
    assert math.isclose(data["latest_entropy"], expected, rel_tol=1e-9, abs_tol=1e-9), (
        f"Expected latest_entropy {expected}, got {data['latest_entropy']}"
    )

    # Probe the HTTP processor repeatedly using messages and answers selected by
    # the verifier. This detects fixed stats endpoints and the old natural-log formula.
    for message in ["AB", "AAAB", "abcde" + secrets.token_hex(5), token + "Q" * 7]:
        client.delete("logs")
        client.lpush("logs", json.dumps({"message": message, "probe": token}))
        probe = get_stats()
        assert probe["valid_logs_processed"] == 1
        assert probe["dead_letters"] == 2
        expected = entropy_bits(message)
        assert math.isclose(probe["latest_entropy"], expected, rel_tol=1e-9, abs_tol=1e-9), (
            f"Processor entropy mismatch: expected {expected}, got {probe['latest_entropy']}"
        )

    # Retain the original integration scenario and its assertions.
    client.flushdb()
    payloads = [
        b'{"message": "AABB"}\n',
        b'{"message": "corrupted...\n',
        b'\xff\xfe\x00\x00\n',
        b'{"message": "A"}\n'
    ]
    for payload in payloads:
        send_payload(payload)
        time.sleep(0.1)

    wait_for_lengths(client, 2, 2)
    time.sleep(1)
    data = get_stats()
    assert data["valid_logs_processed"] >= 2, f"Expected at least 2 valid logs processed, got {data['valid_logs_processed']}"
    assert data["dead_letters"] >= 2, f"Expected at least 2 dead letters, got {data['dead_letters']}"
    assert abs(data["latest_entropy"] - 0.0) < 0.001, f"Expected latest_entropy to be 0.0, got {data['latest_entropy']}"

    final_dead = set(client.lrange("dead_letter", 0, -1))
    assert b'{"message": "corrupted...\n' in final_dead
    assert b'??\x00\x00\n' in final_dead
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
