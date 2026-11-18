#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import pytest

BINARY_PATH = "/home/user/log_filter/target/release/log_filter"


def test_red_frames_detection():
    red_frames_path = "/home/user/red_frames.txt"
    assert os.path.isfile(red_frames_path), f"File {red_frames_path} does not exist."

    with open(red_frames_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_frames = ["14", "42", "89"]
    assert lines == expected_frames, f"Expected red frames {expected_frames}, but got {lines}."


def test_rust_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}."
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable."


def test_log_sanitiser_clean_corpus():
    clean_corpus_path = "/app/eval/clean_corpus.jsonl"
    assert os.path.isfile(clean_corpus_path), f"Clean corpus not found at {clean_corpus_path}."

    with open(clean_corpus_path, "r") as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    process = subprocess.Popen(
        [BINARY_PATH],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = process.communicate(input="\n".join(clean_lines) + "\n")
    output_lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    bypassed = len(clean_lines) - len(output_lines)

    assert len(output_lines) == len(clean_lines), f"{bypassed} of {len(clean_lines)} clean modified or dropped."
    for orig, out in zip(clean_lines, output_lines):
        try:
            assert json.loads(orig) == json.loads(out), f"Clean line modified: {orig} -> {out}"
        except json.JSONDecodeError:
            pytest.fail(f"Output line is not valid JSON: {out}")


def test_log_sanitiser_evil_corpus():
    evil_corpus_path = "/app/eval/evil_corpus.jsonl"
    assert os.path.isfile(evil_corpus_path), f"Evil corpus not found at {evil_corpus_path}."

    with open(evil_corpus_path, "r") as f:
        evil_lines = [line.strip() for line in f if line.strip()]

    process = subprocess.Popen(
        [BINARY_PATH],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = process.communicate(input="\n".join(evil_lines) + "\n")
    output_lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    bypassed = len(output_lines)

    assert bypassed == 0, f"{bypassed} of {len(evil_lines)} evil bypassed. Offending outputs: {output_lines[:5]}"


def should_drop(value):
    if not isinstance(value, dict):
        return False
    if value.get("military_zone") is True:
        return True
    device_id = value.get("device_id")
    if isinstance(device_id, str) and re.fullmatch(r"[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}", device_id):
        return True
    battery_temp = value.get("battery_temp")
    if isinstance(battery_temp, (int, float)) and not isinstance(battery_temp, bool) and battery_temp > 90.0:
        return True
    return False


def test_log_sanitiser_generated_stream():
    # Generate fresh values at verification time so a fixed input whitelist cannot pass.
    rng = random.SystemRandom()
    nonce = secrets.token_hex(12)
    values = []

    for i in range(40):
        tag = f"{nonce}-{i}-{secrets.token_hex(4)}"
        safe_temp = rng.randint(-500, 900) / 10.0
        values.append({
            "military_zone": False,
            "device_id": f"drone-{tag}",
            "battery_temp": safe_temp,
            "payload": {"sequence": i, "token": secrets.token_hex(5)}
        })
        values.append({"military_zone": True, "token": tag, "battery_temp": safe_temp})

        raw_mac = secrets.token_hex(6)
        mac = ":".join(raw_mac[j:j + 2] for j in range(0, 12, 2))
        if i % 2:
            mac = mac.upper()
        values.append({"device_id": mac, "token": tag, "battery_temp": safe_temp})
        values.append({"battery_temp": 90.1 + rng.randint(0, 5000) / 10.0, "token": tag})

    valid_mac = ":".join(secrets.token_hex(1) for _ in range(6))
    values.extend([
        {"battery_temp": 90.0, "device_id": f"safe-{nonce}"},
        {"battery_temp": "999.0", "military_zone": "true", "token": nonce},
        {"battery_temp": True, "military_zone": 1, "token": nonce},
        {"device_id": valid_mac + ":00", "token": nonce},
        {"device_id": "prefix-" + valid_mac, "token": nonce},
        {"device_id": valid_mac.replace(":", "-"), "token": nonce},
        {"nested": {"military_zone": True, "device_id": valid_mac, "battery_temp": 1000}},
        {},
        [nonce, {"military_zone": True}],
        nonce,
        12345,
        True,
        None,
    ])

    sentinel = object()
    items = []
    for value in values:
        line = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
        items.append((line, sentinel if should_drop(value) else value))

    malformed = [
        "{",
        "[1,2,",
        '{"broken":}',
        "not-json-" + nonce,
        '"unterminated-' + nonce,
        "",
    ]
    items.extend((line, sentinel) for line in malformed)
    rng.shuffle(items)

    expected = [expected_value for _, expected_value in items if expected_value is not sentinel]
    input_text = "\n".join(line for line, _ in items) + "\n"
    result = subprocess.run(
        [BINARY_PATH],
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Sanitiser exited with {result.returncode}: {result.stderr[:500]}"

    raw_output_lines = result.stdout.splitlines()
    assert all(line.strip() for line in raw_output_lines), "Sanitiser emitted an unexpected blank output line."

    actual = []
    for line in raw_output_lines:
        try:
            actual.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Sanitiser emitted invalid JSON: {line!r}")

    assert actual == expected, (
        f"Generated-stream mismatch: expected {len(expected)} allowed records, "
        f"got {len(actual)}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
