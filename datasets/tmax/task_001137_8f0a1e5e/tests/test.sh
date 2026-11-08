#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import socket
import subprocess

import pytest


def expected_stats():
    ocr = subprocess.run(
        ["tesseract", "/app/target_distribution.png", "stdout"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    match = re.search(
        r"Mean\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*,?\s*StdDev\s*=\s*([0-9]+(?:\.[0-9]+)?)",
        ocr,
        re.IGNORECASE,
    )
    assert match, f"Could not extract Mean and StdDev from image OCR: {ocr!r}"
    mean, stddev = map(float, match.groups())

    lengths = []
    current = None
    with open("/home/user/raw_sequences.fasta", encoding="utf-8") as fasta:
        for raw_line in fasta:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current is not None:
                    lengths.append(current)
                current = 0
            else:
                assert current is not None, "FASTA sequence data appeared before a header"
                current += len(re.sub(r"\s+", "", line))
    if current is not None:
        lengths.append(current)

    filtered = [n for n in lengths if mean - stddev <= n <= mean + stddev]
    assert filtered, "Reference filtering produced no sequences"
    return sum(filtered) / len(filtered), len(filtered)


def listener_processes():
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as table:
        next(table)
        for line in table:
            fields = line.split()
            # 0100007F is 127.0.0.1 and 1F90 is port 8080.
            if fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    assert inodes, "No process is listening specifically on 127.0.0.1:8080"

    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    exe = os.path.basename(os.readlink(f"/proc/{entry}/exe"))
                    found.append((int(entry), exe))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    assert found, "Could not identify the process owning the HTTP listener"
    return found


def raw_stats_request():
    request = (
        b"GET /stats HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        b"Connection: close\r\n\r\n"
    )
    chunks = []
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=5) as sock:
            sock.settimeout(5)
            sock.sendall(request)
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
    except OSError as exc:
        pytest.fail(f"Failed to communicate with the server: {exc}")

    response = b"".join(chunks)
    assert b"\r\n\r\n" in response, "HTTP response must use CRLF headers and include a header/body separator"
    head, body = response.split(b"\r\n\r\n", 1)
    lines = head.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 200 OK", f"Expected HTTP/1.1 200 OK, got {lines[0]!r}"

    headers = {}
    for line in lines[1:]:
        assert b":" in line, f"Malformed HTTP header: {line!r}"
        name, value = line.split(b":", 1)
        headers[name.decode("ascii").strip().lower()] = value.decode("ascii").strip()
    assert "content-type" in headers, "Response is missing the Content-Type header"
    assert headers["content-type"].split(";", 1)[0].strip().lower() == "application/json", \
        f"Expected JSON Content-Type, got {headers['content-type']!r}"
    if "content-length" in headers:
        assert int(headers["content-length"]) == len(body), "Content-Length does not match the response body"

    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Response body is not valid UTF-8 JSON: {body!r}: {exc}")


def assert_payload(data, expected_mean, expected_count):
    assert isinstance(data, dict), f"Expected a JSON object, got {data!r}"
    assert "empirical_mean" in data, f"Response JSON missing 'empirical_mean' key. Got: {data}"
    assert "sequence_count" in data, f"Response JSON missing 'sequence_count' key. Got: {data}"
    assert set(data) == {"empirical_mean", "sequence_count"}, f"Unexpected JSON fields: {data}"
    assert isinstance(data["empirical_mean"], (int, float)) and not isinstance(data["empirical_mean"], bool)
    assert isinstance(data["sequence_count"], int) and not isinstance(data["sequence_count"], bool)
    assert math.isclose(float(data["empirical_mean"]), expected_mean, rel_tol=0, abs_tol=1e-9), \
        f"Expected empirical_mean {expected_mean}, got {data['empirical_mean']}"
    assert data["sequence_count"] == expected_count, \
        f"Expected sequence_count {expected_count}, got {data['sequence_count']}"


def test_server_response_and_implementation():
    expected_mean, expected_count = expected_stats()

    owners = listener_processes()
    allowed = {"bash", "nc", "nc.openbsd", "netcat"}
    assert any(exe in allowed for _, exe in owners), \
        f"Listener must be implemented with Bash or nc; found {owners}"

    # Exercise the endpoint twice to ensure the background server remains available.
    assert_payload(raw_stats_request(), expected_mean, expected_count)
    assert_payload(raw_stats_request(), expected_mean, expected_count)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
