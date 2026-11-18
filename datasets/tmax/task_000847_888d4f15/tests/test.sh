#!/bin/bash
set -e
mkdir -p /logs/verifier
export TZ=UTC

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest
import glob
import re
import random
import secrets
import time
from datetime import datetime, timedelta, timezone

SCRIPT_PATH = "/home/user/filter_stream.sh"
INGEST_PATH = "/app/bin/log_ingest"

os.environ["TZ"] = "UTC"
if hasattr(time, "tzset"):
    time.tzset()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def parse_timestamp(ts_str):
    try:
        dt = datetime.strptime(ts_str, "%Y/%m/%d %H:%M:%S")
    except ValueError:
        try:
            dt = datetime.strptime(ts_str, "%d-%m-%Y %H:%M:%S")
        except ValueError:
            return None
    return int(dt.timestamp())


def test_adversarial_corpus():
    evil_dir = "/app/tests/corpus/evil"
    clean_dir = "/app/tests/corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.log"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.log"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []

    for e_file in evil_files:
        with open(e_file, 'rb') as f:
            input_data = f.read()

        result = subprocess.run([SCRIPT_PATH], input=input_data, capture_output=True)
        if result.stdout.strip():
            evil_bypassed.append(os.path.basename(e_file))

    for c_file in clean_files:
        with open(c_file, 'rb') as f:
            lines = f.read().splitlines()

        expected_lines = []
        for line in lines:
            if not line:
                continue
            line_str = line.decode('utf-8', errors='replace')
            m = re.match(r'^\[(.*?)\]\s*(.*)$', line_str)
            if m:
                ts, payload = m.groups()
                epoch = parse_timestamp(ts)
                if epoch is not None:
                    expected_lines.append(f"[{epoch}] {payload}".encode('utf-8'))
                else:
                    expected_lines.append(line)
            else:
                expected_lines.append(line)

        with open(c_file, 'rb') as f:
            input_data = f.read()

        result = subprocess.run([SCRIPT_PATH], input=input_data, capture_output=True)
        out_lines = result.stdout.splitlines()

        if out_lines != expected_lines:
            clean_modified.append(os.path.basename(c_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def timestamp_for(rng, index):
    base = datetime(2018, 1, 1, tzinfo=timezone.utc)
    dt = base + timedelta(seconds=rng.randrange(0, 12 * 365 * 24 * 60 * 60) + index)
    if rng.randrange(2):
        rendered = dt.strftime("%Y/%m/%d %H:%M:%S")
    else:
        rendered = dt.strftime("%d-%m-%Y %H:%M:%S")
    return rendered.encode("ascii"), int(dt.timestamp())


def framed_line(ts, payload):
    return b"[" + ts + b"] " + payload + b"\n"


def test_generated_stream_filtering_and_normalization():
    # A fresh seed makes the exact records and timestamps unavailable to scripts
    # that merely special-case the image's fixed corpus.
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = []
    slash_u = bytes((0x5C, 0x75))
    hex_digits = b"0123456789abcdefABCDEF"
    invalid_digits = b"GgZz!@_-/?:;,. "

    # Thousands of clean records exercise both timestamp formats, preservation
    # of arbitrary payload text, and valid Unicode escapes.
    for i in range(2200):
        ts, epoch = timestamp_for(rng, i)
        token = secrets.token_hex(10).encode("ascii")
        codepoint = bytes(rng.choice(hex_digits) for _ in range(4))
        payload = (b'{"id":"' + token + b'","seq":' + str(i).encode("ascii")
                   + b',"msg":"clean escaped-tab \\t unicode ' + slash_u
                   + codepoint + b' tail"}')
        source = framed_line(ts, payload)
        expected = framed_line(str(epoch).encode("ascii"), payload)
        cases.append((source, expected))

    # Exercise every position in the four-digit escape with many independently
    # selected non-hexadecimal bytes.
    for i in range(160):
        ts, _ = timestamp_for(rng, 3000 + i)
        token = secrets.token_hex(8).encode("ascii")
        digits = bytearray(rng.choice(hex_digits) for _ in range(4))
        digits[i % 4] = rng.choice(invalid_digits)
        payload = (b'{"id":"' + token + b'","msg":"before ' + slash_u
                   + bytes(digits) + b' after"}')
        cases.append((framed_line(ts, payload), b""))

    # Cut-off escapes of each possible short length. The following quote or
    # payload delimiter is intentionally encountered before four hex digits.
    for i in range(80):
        ts, _ = timestamp_for(rng, 4000 + i)
        token = secrets.token_hex(8).encode("ascii")
        prefix_len = i % 4
        short_hex = bytes(rng.choice(hex_digits) for _ in range(prefix_len))
        payload = (b'{"id":"' + token + b'","msg":"cutoff ' + slash_u
                   + short_hex + b'"}')
        cases.append((framed_line(ts, payload), b""))

    # The binary crashes on literal non-NUL controls while it is inside a JSON
    # string. Cover every such byte except LF, which is the physical line
    # delimiter rather than a byte within one input line.
    controls = [c for c in range(1, 32) if c != 10]
    for i in range(120):
        ts, _ = timestamp_for(rng, 5000 + i)
        token = secrets.token_hex(8).encode("ascii")
        control = controls[i % len(controls)]
        payload = (b'{"id":"' + token + b'","msg":"left'
                   + bytes((control,)) + b'right"}')
        cases.append((framed_line(ts, payload), b""))

    rng.shuffle(cases)
    input_data = b"".join(source for source, _ in cases)
    expected = b"".join(output for _, output in cases)

    result = subprocess.run(
        [SCRIPT_PATH], input=input_data, capture_output=True, timeout=120,
        env={**os.environ, "TZ": "UTC"}
    )
    assert result.returncode == 0, (
        f"filter exited with status {result.returncode}: "
        f"{result.stderr[-1000:]!r}"
    )
    assert result.stdout == expected, (
        "generated mixed stream was not filtered and normalized exactly; "
        f"expected {len(expected)} output bytes, got {len(result.stdout)}"
    )

    ingested = subprocess.run(
        [INGEST_PATH], input=result.stdout, capture_output=True, timeout=30
    )
    assert ingested.returncode == 0, (
        f"filtered output crashed log_ingest with status {ingested.returncode}"
    )
    assert ingested.stdout == expected, "log_ingest did not receive the expected safe stream"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
