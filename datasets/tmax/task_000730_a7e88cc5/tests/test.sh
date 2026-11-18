#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

# Stop stale agent processes and remove any output fabricated before verification.
pkill -TERM -f '/home/user/extractor\.py' 2>/dev/null || true
pkill -TERM -x log_generator 2>/dev/null || true
sleep 1
pkill -KILL -f '/home/user/extractor\.py' 2>/dev/null || true
pkill -KILL -x log_generator 2>/dev/null || true

rm -f /home/user/parsed_logs.jsonl
rm -rf /home/user/raw_logs
mkdir -p /home/user/raw_logs
chown -R user:user /home/user/raw_logs

SEED=$(( $(od -An -N4 -tu4 /dev/urandom) % 2000000000 + 1 ))
printf '%s\n' "$SEED" > /tmp/generator_seed

# Exercise the submitted extractor concurrently with the real generator.
runuser -u user -- bash -c 'cd /home/user && exec python3 /home/user/extractor.py' \
    >/tmp/extractor.stdout 2>/tmp/extractor.stderr &
EXTRACTOR_PID=$!
sleep 1

timeout 65s runuser -u user -- /app/log_generator --duration 30 --seed "$SEED" \
    >/tmp/generator.stdout 2>/tmp/generator.stderr
GENERATOR_STATUS=$?
printf '%s\n' "$GENERATOR_STATUS" > /tmp/generator_status

# Allow the extractor to consume the final flushed records, then stop it.
sleep 5
kill -TERM "$EXTRACTOR_PID" 2>/dev/null || true
pkill -TERM -f '/home/user/extractor\.py' 2>/dev/null || true
sleep 1
pkill -KILL -f '/home/user/extractor\.py' 2>/dev/null || true
wait "$EXTRACTOR_PID" 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import os
import struct

import pytest

EXTRACTOR = "/home/user/extractor.py"
PARSED = "/home/user/parsed_logs.jsonl"
EXPECTED_TOTAL = 100000
HEADER = struct.Struct("<2sQBH")


def test_extractor_script_exists():
    assert os.path.isfile(EXTRACTOR), (
        f"Expected extractor script at {EXTRACTOR} but it was not found."
    )


def test_concurrent_generator_run_succeeded():
    with open("/tmp/generator_status", "r") as f:
        status = int(f.read().strip())
    assert status == 0, f"The concurrent log generator run failed with status {status}."


def _read_generated_records():
    records = []
    paths = glob.glob("/home/user/raw_logs/*.log")
    assert paths, "The generator produced no binary log files."

    for path in paths:
        with open(path, "rb") as f:
            data = f.read()
        offset = 0
        while offset < len(data):
            assert len(data) - offset >= HEADER.size, (
                f"Partial binary header in generated file {path} at offset {offset}."
            )
            magic, timestamp_us, severity, msg_len = HEADER.unpack_from(data, offset)
            assert magic == b"\xBE\xEF", (
                f"Invalid magic in generated file {path} at offset {offset}."
            )
            offset += HEADER.size
            assert offset + msg_len <= len(data), (
                f"Partial binary payload in generated file {path} at offset {offset}."
            )
            payload = data[offset:offset + msg_len]
            offset += msg_len
            try:
                message = payload.decode("ascii")
            except UnicodeDecodeError as exc:
                pytest.fail(f"Non-ASCII generated payload in {path}: {exc}")
            records.append((timestamp_us, severity, message))

    records.sort(key=lambda record: record[0])
    assert len(records) == EXPECTED_TOTAL, (
        f"Expected the real generator to produce {EXPECTED_TOTAL} records, "
        f"but decoded {len(records)}."
    )

    # Independently validate that the binary files are the output of this run,
    # rather than files substituted by the submitted process.
    with open("/tmp/generator_seed", "r") as f:
        seed = int(f.read().strip())
    libc = ctypes.CDLL(None)
    libc.srand(ctypes.c_uint(seed))
    base_timestamp = records[0][0]
    for i, (timestamp_us, severity, message) in enumerate(records):
        assert timestamp_us == base_timestamp + i * 1000, (
            f"Generated timestamp sequence is invalid at record {i}."
        )
        assert severity == libc.rand() % 6, (
            f"Generated severity sequence is invalid at record {i}."
        )
        assert message == f"Log message {i} with some extra padding to make it realistic.", (
            f"Generated message is invalid at record {i}."
        )
    return records


def _read_output_lines():
    assert os.path.isfile(PARSED), (
        f"Expected parsed logs file at {PARSED} but it was not found."
    )
    with open(PARSED, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_parsed_logs_accuracy():
    generated = _read_generated_records()
    expected = {
        timestamp: (severity, message)
        for timestamp, severity, message in generated
    }
    lines = _read_output_lines()

    # Preserve the original shape-based accuracy assertion.
    valid_records = 0
    decoded = []
    for line_number, line in enumerate(lines, 1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Invalid JSON on output line {line_number}: {exc}")
        if isinstance(record, dict) and all(
            key in record for key in ("timestamp_us", "severity", "message")
        ):
            valid_records += 1
        decoded.append(record)

    accuracy = valid_records / EXPECTED_TOTAL
    assert accuracy >= 0.98, (
        f"Extraction accuracy is too low. Expected >= 0.98, but got "
        f"{accuracy:.4f} ({valid_records} valid records out of {EXPECTED_TOTAL})."
    )

    # Validate schema, values, uniqueness, ordering, and correspondence to the
    # binary records produced during the concurrent run.
    previous_timestamp = None
    seen_timestamps = set()
    for line_number, record in enumerate(decoded, 1):
        assert isinstance(record, dict), f"Output line {line_number} is not a JSON object."
        assert set(record) == {"timestamp_us", "severity", "message"}, (
            f"Output line {line_number} does not exactly match the required schema."
        )
        timestamp = record["timestamp_us"]
        severity = record["severity"]
        message = record["message"]
        assert type(timestamp) is int, f"timestamp_us on line {line_number} is not an integer."
        assert type(severity) is int, f"severity on line {line_number} is not an integer."
        assert type(message) is str, f"message on line {line_number} is not a string."
        assert timestamp not in seen_timestamps, f"Duplicate timestamp on line {line_number}."
        if previous_timestamp is not None:
            assert timestamp > previous_timestamp, (
                f"Output is not in increasing timestamp order at line {line_number}."
            )
        assert timestamp in expected, (
            f"Output line {line_number} does not correspond to a generated record."
        )
        expected_severity, expected_message = expected[timestamp]
        assert severity == expected_severity, f"Wrong severity on output line {line_number}."
        assert message == expected_message, f"Wrong message on output line {line_number}."
        seen_timestamps.add(timestamp)
        previous_timestamp = timestamp

    matched_accuracy = len(seen_timestamps) / EXPECTED_TOTAL
    assert matched_accuracy >= 0.98, (
        f"Only {len(seen_timestamps)} unique generated records were captured "
        f"({matched_accuracy:.4f}); expected at least 0.98."
    )


def test_parsed_logs_no_extra_records():
    if not os.path.exists(PARSED):
        return

    valid_records = 0
    with open(PARSED, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                if isinstance(record, dict) and all(
                    key in record for key in ("timestamp_us", "severity", "message")
                ):
                    valid_records += 1
            except json.JSONDecodeError:
                pass

    assert valid_records <= EXPECTED_TOTAL, (
        f"Found {valid_records} valid records, which is more than the expected total "
        f"of {EXPECTED_TOTAL} records generated."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi
