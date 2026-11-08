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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import secrets
import string
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/ingest"
ETL_PATH = Path("/home/user/etl.py")
PARSER_PATH = Path("/app/text-pipeline-server-1.0/text_pipeline/parser.py")


def post(payload, batch_id):
    headers = {"X-Batch-ID": batch_id, "Content-Type": "text/plain"}
    for attempt in range(5):
        try:
            return requests.post(URL, headers=headers, data=payload, timeout=5)
        except requests.exceptions.ConnectionError:
            if attempt == 4:
                pytest.fail("Could not connect to the server at 127.0.0.1:8080. Is it running?")
            time.sleep(1)


def reference_process(raw_text):
    parsed = []
    pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] \[([^\]\r\n]+)\] (.*)$")
    for line in raw_text.splitlines():
        match = pattern.fullmatch(line)
        if not match:
            continue
        timestamp, level, message = match.groups()
        cleaned = "".join(ch.lower() for ch in message if ch.isalnum() or ch == " ")
        parsed.append({
            "timestamp": timestamp,
            "level": level,
            "cleaned_message": cleaned,
        })

    # Duplicate groups are connected components of the >= 0.75 similarity graph.
    parent = list(range(len(parsed)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[b] = a

    for i in range(len(parsed)):
        left = set(parsed[i]["cleaned_message"].split(" "))
        left.discard("")
        for j in range(i + 1, len(parsed)):
            right = set(parsed[j]["cleaned_message"].split(" "))
            right.discard("")
            union_words = left | right
            similarity = (len(left & right) / len(union_words)) if union_words else 1.0
            if similarity >= 0.75:
                union(i, j)

    groups = {}
    for i, item in enumerate(parsed):
        root = find(i)
        if root not in groups or item["timestamp"] < parsed[groups[root]]["timestamp"]:
            groups[root] = i
    return sorted((parsed[i] for i in groups.values()), key=lambda item: item["timestamp"])


def load_etl():
    assert ETL_PATH.is_file(), "/home/user/etl.py was not created as a Python file"
    spec = importlib.util.spec_from_file_location("submitted_etl", ETL_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "process_logs") and callable(module.process_logs)
    return module.process_logs


def random_word():
    return "w" + secrets.token_hex(6)


def generated_payloads():
    words = [random_word() for _ in range(20)]
    a, b, c, d = words[0:4]
    u1, u2, u3, u4 = words[4:8]
    q = words[8:16]

    payload1 = "\n".join([
        f"[2025-06-03T12:00:20] [INFO] {a.upper()}, {b}! {c}? {d}.",
        "not a valid log line",
        f"[2025-06-03T12:00:10] [WARN] {u1}; {u2}: {u3} / {u4}",
        f"[2025-06-03T12:00:05] [DEBUG] {a} {b} {c} {d}",
        f"[2025-06-03T12:00:30] [ERROR] {' '.join(q[:6])}",
        f"[2025-06-03T12:00:25] [NOTICE] {' '.join(q)}",
        f"prefix [2025-06-03T12:00:01] [INFO] {words[16]}",
        f"[2025-06-03T12:00:40] [INFO]{words[17]}",
    ])

    x, y, z, extra = words[16:20]
    payload2 = "\n".join([
        f"[2024-01-02T03:04:09] [ERROR] {x}--{y}!!{z}",
        f"[2024-01-02T03:04:06] [INFO] {x}{y}{z}",
        f"[2024-01-02T03:04:07] [WARN] {extra} unique payload",
        "[2024-01-02T03:04:08] INFO missing-level-brackets",
    ])
    return [payload1, payload2]


def test_framework_source_and_editable_install():
    assert PARSER_PATH.is_file(), "Vendored parser.py is missing"

    spec = importlib.util.spec_from_file_location("vendored_parser_check", PARSER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    suffix = "env" + secrets.token_hex(3)
    assert module.validate_batch_id(f"batch-{random.randint(1, 999999)}-{suffix}")
    assert module.validate_batch_id("batch-0-prod")
    for invalid in ["batch-prod-123", "batch-x-prod", "batch-123-", "batch-123-prod-extra", "not-a-batch"]:
        assert not module.validate_batch_id(invalid), f"Invalid batch ID was accepted: {invalid}"

    import text_pipeline.parser as installed_parser
    assert Path(installed_parser.__file__).resolve() == PARSER_PATH.resolve(), (
        "text-pipeline-server is not installed from the editable vendored source"
    )
    distribution = importlib.metadata.distribution("text-pipeline-server")
    assert distribution.version == "1.0"
    assert any(
        os.access(Path(directory) / "text-pipeline-server", os.X_OK)
        for directory in os.environ.get("PATH", "").split(os.pathsep)
    ), "text-pipeline-server CLI is not installed"


def test_required_server_command_is_running():
    found = False
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            args = (proc / "cmdline").read_bytes().split(b"\0")
            text_args = [arg.decode("utf-8", "replace") for arg in args if arg]
        except (OSError, PermissionError):
            continue
        if not any(Path(arg).name == "text-pipeline-server" for arg in text_args):
            continue
        joined = " ".join(text_args)
        if ("--host 127.0.0.1" in joined and "--port 8080" in joined and
                "--handler /home/user/etl.py:process_logs" in joined):
            found = True
            break
    assert found, "The required text-pipeline-server CLI command is not running"


def test_etl_artifact_and_dynamic_server_behavior():
    process_logs = load_etl()
    payloads = generated_payloads()
    for index, payload in enumerate(payloads):
        expected = reference_process(payload)
        assert process_logs(payload) == expected

        batch_id = f"batch-{secrets.randbelow(900000) + 100000}-run{secrets.token_hex(3)}"
        response = post(payload, batch_id)
        assert response.status_code == 200, response.text
        try:
            actual = response.json()
        except ValueError:
            pytest.fail(f"Server did not return valid JSON. Response body: {response.text}")
        assert actual == expected, f"Dynamic request {index} returned {actual}, expected {expected}"


def test_server_rejects_invalid_batch_ids():
    payload = f"[2025-01-01T00:00:00] [INFO] {random_word()}"
    for batch_id in ["batch-prod-123", "batch-abc-prod", "batch-123-"]:
        response = post(payload, batch_id)
        assert response.status_code == 400, f"Invalid batch ID {batch_id!r} returned {response.status_code}"


def test_original_etl_server_response():
    payload = """[2023-10-12T10:00:00] [INFO] Database connection established successfully!
[2023-10-12T10:00:05] [ERROR] User login failed for username: admin.
[2023-10-12T10:00:08] [INFO] database connection established successfully
Invalid log line without timestamp
[2023-10-12T10:00:15] [ERROR] User login failed for username: root.
[2023-10-12T10:01:00] [WARN] Disk space running low"""

    expected_response = [
        {"timestamp": "2023-10-12T10:00:00", "level": "INFO", "cleaned_message": "database connection established successfully"},
        {"timestamp": "2023-10-12T10:00:05", "level": "ERROR", "cleaned_message": "user login failed for username admin"},
        {"timestamp": "2023-10-12T10:01:00", "level": "WARN", "cleaned_message": "disk space running low"},
    ]

    response = post(payload, "batch-9982-prod")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response body: {response.text}"
    try:
        actual_response = response.json()
    except ValueError:
        pytest.fail(f"Server did not return valid JSON. Response body: {response.text}")
    assert actual_response == expected_response, f"Expected JSON response {expected_response}, but got {actual_response}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
