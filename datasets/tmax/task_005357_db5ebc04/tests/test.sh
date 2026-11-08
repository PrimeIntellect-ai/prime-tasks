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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import glob
import json
import os
import re
import socket
import subprocess
import time
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8080/metrics"
LIB = "/app/local/lib/libcJSON.so"
HEADER = "/app/local/include/cJSON.h"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return int(proc.rsplit("/", 1)[-1])
    return None


def raw_request(method, path="/metrics", body=b"", source_ip=None, content_type="application/json"):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    if source_ip:
        sock.bind((source_ip, 0))
    try:
        sock.connect(("127.0.0.1", 8080))
        headers = [
            f"{method} {path} HTTP/1.1",
            "Host: 127.0.0.1",
            "Connection: close",
        ]
        if method == "POST":
            headers.extend([
                f"Content-Type: {content_type}",
                f"Content-Length: {len(body)}",
            ])
        sock.sendall(("\r\n".join(headers) + "\r\n\r\n").encode("ascii") + body)
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    finally:
        sock.close()
    response = b"".join(chunks)
    head, _, response_body = response.partition(b"\r\n\r\n")
    first = head.split(b"\r\n", 1)[0]
    match = re.match(br"HTTP/\d(?:\.\d)?\s+(\d{3})", first)
    assert match, f"Invalid HTTP response: {response[:200]!r}"
    return int(match.group(1)), response_body


def wait_for_fresh_window():
    time.sleep(1.15)


def test_complete_task():
    # Preserve the original installation assertions.
    assert os.path.isfile(LIB), "libcJSON.so is missing from /app/local/lib"
    assert os.path.isfile(HEADER), "cJSON.h is missing from /app/local/include"

    # The installed artifact must actually be a loadable shared library exporting cJSON.
    elf = subprocess.run(["readelf", "-h", LIB], text=True, capture_output=True)
    assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout, elf.stderr
    loaded = ctypes.CDLL(LIB)
    assert getattr(loaded, "cJSON_Parse", None) is not None
    assert getattr(loaded, "cJSON_Delete", None) is not None

    # The server listening on the required port must have loaded this library.
    pid = listener_pid()
    assert pid is not None, "No process is listening on port 8080"
    maps = open(f"/proc/{pid}/maps", errors="replace").read()
    assert "libcJSON.so" in maps, "The running server has not loaded libcJSON.so"

    # Exercise the repaired Makefile rather than trusting a pre-existing file.
    build = subprocess.run(
        ["make", "-B", "install"], cwd="/app/vendored/cJSON",
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"cJSON Makefile build/install failed:\n{build.stdout}"
    rebuilt = subprocess.run(["readelf", "-h", LIB], text=True, capture_output=True)
    assert rebuilt.returncode == 0 and "DYN (Shared object file)" in rebuilt.stdout
    rebuilt_lib = ctypes.CDLL(LIB)
    assert getattr(rebuilt_lib, "cJSON_Parse", None) is not None

    # Preserve the original fixed POST/GET assertions.
    payload = [{"id": 3, "value": "apple"}, {"id": 1, "value": "banana"}]
    try:
        post_response = requests.post(URL, json=payload, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server for POST /metrics: {exc}")
    assert post_response.status_code == 200, (
        f"Expected POST /metrics to return 200, got {post_response.status_code}"
    )
    try:
        get_response = requests.get(URL, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server for GET /metrics: {exc}")
    assert get_response.status_code == 200, (
        f"Expected GET /metrics to return 200, got {get_response.status_code}"
    )
    expected_data = [{"id": 1, "value": "YmFuYW5h"}, {"id": 3, "value": "YXBwbGU="}]
    try:
        actual_data = get_response.json()
    except ValueError:
        pytest.fail("GET /metrics did not return valid JSON")
    assert actual_data == expected_data, (
        f"Expected GET /metrics to return {expected_data}, got {actual_data}"
    )

    # Use unpredictable data to verify parsing, sorting, base64 encoding, and storage.
    wait_for_fresh_window()
    token = uuid.uuid4().hex
    base_id = 100000000 + (int(token[:7], 16) % 500000000)
    values = [f"quote-\"-{token}", f"backslash-\\-{token}", f"spaces and + / {token}"]
    dynamic_payload = [
        {"id": base_id + 30, "value": values[0]},
        {"id": base_id + 10, "value": values[1]},
        {"id": base_id + 20, "value": values[2]},
    ]
    dynamic_post = requests.post(URL, json=dynamic_payload, timeout=2)
    assert dynamic_post.status_code == 200
    dynamic_get = requests.get(URL, timeout=2)
    assert dynamic_get.status_code == 200
    try:
        returned = dynamic_get.json()
    except ValueError:
        pytest.fail("GET /metrics did not return valid JSON for dynamic metrics")
    assert isinstance(returned, list)
    assert all(isinstance(item, dict) and set(item) == {"id", "value"} for item in returned)
    assert [item["id"] for item in returned] == sorted(item["id"] for item in returned), (
        "GET /metrics is not sorted by id"
    )
    expected_dynamic = {
        (item["id"], base64.b64encode(item["value"].encode("utf-8")).decode("ascii"))
        for item in dynamic_payload
    }
    returned_pairs = {(item["id"], item["value"]) for item in returned}
    assert expected_dynamic <= returned_pairs, (
        f"Dynamic metrics were not parsed, encoded, and stored correctly: {returned}"
    )

    # Malformed JSON and invalid metric shapes must be rejected by validation.
    wait_for_fresh_window()
    invalid_bodies = [
        b'[{"id":1,"value":"broken"}',
        b'{"id":1,"value":"not-an-array"}',
        b'[{"id":"one","value":"bad-id"}]',
        b'[{"id":1}]',
    ]
    for body in invalid_bodies:
        status, _ = raw_request("POST", body=body)
        assert status == 400, f"Invalid JSON/schema was not rejected with 400: {body!r} -> {status}"

    # Preserve and strengthen the original same-IP sixth-request assertion.
    wait_for_fresh_window()
    rate_payload = [{"id": 10, "value": "test"}]
    responses = [requests.post(URL, json=rate_payload, timeout=2).status_code for _ in range(6)]
    assert responses[:5] == [200] * 5, f"The first five requests were not accepted: {responses}"
    assert responses[5] == 429, (
        f"Expected 6th request to return 429 Too Many Requests, got {responses[5]}. "
        f"All responses: {responses}"
    )

    # Verify that counters are per source IP, not a single global POST counter.
    wait_for_fresh_window()
    body = json.dumps([{"id": base_id + 99, "value": token}]).encode("utf-8")
    ip_a = [raw_request("POST", body=body, source_ip="127.0.0.2")[0] for _ in range(5)]
    ip_b_first = raw_request("POST", body=body, source_ip="127.0.0.3")[0]
    ip_a_sixth = raw_request("POST", body=body, source_ip="127.0.0.2")[0]
    assert ip_a == [200] * 5, f"First five requests from one IP were not accepted: {ip_a}"
    assert ip_b_first == 200, "Rate limiting is global rather than per IP"
    assert ip_a_sixth == 429, "Sixth request from the same IP was not rate limited"

    # A C source implementing the API must contain its own linked-list node and operations.
    sources = []
    for root in ("/app", "/home/user", "/root", "/tmp"):
        for path in glob.glob(root + "/**/*.c", recursive=True):
            if os.path.realpath(path) == os.path.realpath("/app/vendored/cJSON/cJSON.c"):
                continue
            try:
                text = open(path, errors="ignore").read()
            except OSError:
                continue
            if "/metrics" in text and re.search(r'["\']id["\']', text) and re.search(r'["\']value["\']', text):
                sources.append((path, text))
    assert sources, "Could not find the C source implementing the metrics API"
    linked_source = False
    for _, text in sources:
        tags = re.findall(r"struct\s+([A-Za-z_]\w*)\s*\{", text)
        for tag in tags:
            self_pointer = re.search(
                r"struct\s+" + re.escape(tag) + r"\s*\{[^}]*struct\s+" +
                re.escape(tag) + r"\s*\*", text, re.S
            )
            if self_pointer and re.search(r"->\s*next\b", text):
                linked_source = True
                break
        if linked_source:
            break
    assert linked_source, "The metrics server source does not implement a custom linked list"

    # Preserve the original log assertions and require entries for exercised outcomes.
    time.sleep(0.25)
    log_path = "/home/user/api.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r", errors="replace") as handle:
        lines = handle.readlines()
    assert len(lines) > 0, "Log file is empty."
    pattern = re.compile(r"^\[.*?\]\s+(GET|POST)\s+/metrics\s+\d{3}\s*$")
    valid_lines = [line for line in lines if pattern.match(line)]
    assert valid_lines, (
        f"No lines in {log_path} matched '[TIMESTAMP] METHOD PATH STATUS'."
    )
    joined = "".join(valid_lines)
    assert re.search(r"\sPOST\s+/metrics\s+200\s*$", joined, re.M)
    assert re.search(r"\sGET\s+/metrics\s+200\s*$", joined, re.M)
    assert re.search(r"\sPOST\s+/metrics\s+400\s*$", joined, re.M)
    assert re.search(r"\sPOST\s+/metrics\s+429\s*$", joined, re.M)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
