#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import re
import secrets
import socket
import subprocess
import time
from collections import defaultdict

import pytest

HOST = "127.0.0.1"
ORIGINAL_EXPECTED = [
    "2023-10-15 08:00 -> 125",
    "2023-10-15 09:00 -> 210",
]


def config_from_image():
    text = subprocess.check_output(
        ["tesseract", "/app/config_image.png", "stdout", "--psm", "6"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    port_match = re.search(r"PORT\s*=\s*(\d+)", text)
    mask_match = re.search(r"MASK_REGEX\s*=\s*(.+)", text)
    assert port_match, f"Could not extract PORT from configuration image; OCR output was {text!r}"
    assert mask_match, f"Could not extract MASK_REGEX from configuration image; OCR output was {text!r}"
    return int(port_match.group(1)), mask_match.group(1).strip()


def request(port, command):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(5.0)
            sock.connect((HOST, port))
            sock.sendall(command)
            sock.shutdown(socket.SHUT_WR)
            data = b""
            while True:
                try:
                    chunk = sock.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused on {HOST}:{port}. Ensure the server is listening.")
    except socket.timeout:
        pytest.fail(f"Connection timed out on {HOST}:{port}.")
    except Exception as exc:
        pytest.fail(f"Unexpected error connecting to {HOST}:{port}: {exc}")

    return [
        line.strip()
        for line in data.decode("utf-8", errors="replace").splitlines()
        if line.strip()
    ]


def derive_expected(log_text, mask_regex):
    try:
        masker = re.compile(mask_regex)
    except re.error as exc:
        pytest.fail(f"MASK_REGEX extracted from the image is invalid: {exc}")

    totals = defaultdict(lambda: [0, 0])
    line_pattern = re.compile(
        r"^\[([^]]+)\]\s+(\S+)\s+(\S+)\s+([0-9]+)\s*$"
    )
    for raw_line in log_text.splitlines():
        anonymized = masker.sub("[REDACTED]", raw_line)
        match = line_pattern.match(anonymized)
        assert match, f"Log line did not retain the required format after anonymization: {raw_line!r}"
        hour = match.group(1)[:13] + ":00"
        totals[hour][0] += int(match.group(4))
        totals[hour][1] += 1

    return [
        f"{hour} -> {total // count}"
        for hour, (total, count) in sorted(totals.items())
    ]


def test_01_original_tcp_server_response():
    port, _ = config_from_image()
    assert port == 9099
    response_lines = request(port, b"FETCH_STATS\n")
    assert response_lines == ORIGINAL_EXPECTED, (
        "Server response did not match expected output.\n"
        f"Expected: {ORIGINAL_EXPECTED}\nGot: {response_lines}"
    )


def test_02_only_exact_command_returns_statistics():
    port, _ = config_from_image()
    response_lines = request(port, b"FETCH_STATS_EXTRA\n")
    assert response_lines != ORIGINAL_EXPECTED, (
        "The server returned FETCH_STATS output for a different command"
    )


def test_03_statistics_are_derived_from_log_data():
    port, mask_regex = config_from_image()
    path = "/app/system_metrics.log"
    with open(path, "r", encoding="utf-8") as handle:
        original = handle.read()

    # Values are chosen only after the agent has finished, so a canned response
    # cannot know the required averages.
    a = 300 + secrets.randbelow(400)
    b = 300 + secrets.randbelow(400)
    c = 50 + secrets.randbelow(200)
    nonce = secrets.token_hex(6)
    additions = (
        f"[2023-10-15 10:01:02] verifier.{nonce}@example.com GET {a}\n"
        f"[2023-10-15 10:58:59] audit.{nonce}@corp.local POST {b}\n"
        f"[2023-10-15 08:59:58] check.{nonce}@test.org GET {c}\n"
    )
    changed = original.rstrip("\n") + "\n" + additions

    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(changed)
        expected = derive_expected(changed, mask_regex)
        time.sleep(0.25)
        response_lines = request(port, b"FETCH_STATS\n")
        assert response_lines == expected, (
            "Server did not calculate statistics from the current anonymized log data.\n"
            f"Expected: {expected}\nGot: {response_lines}"
        )
    finally:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
