#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import os
import random
import secrets
import shlex
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone

SANITIZER_PATH = "/home/user/sanitizer"
AGGREGATE_PATH = "/home/user/aggregate.sh"
CRON_PATH = "/home/user/pipeline.cron"


def run_filter(data):
    return subprocess.run(
        [SANITIZER_PATH], input=data, capture_output=True, timeout=10
    )


def csv_line(fields):
    stream = io.StringIO(newline="")
    csv.writer(stream, lineterminator="\n").writerow(fields)
    return stream.getvalue().encode("utf-8")


def test_sanitizer_executable():
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer script not found at {SANITIZER_PATH}"
    assert os.access(SANITIZER_PATH, os.X_OK), f"Sanitizer script at {SANITIZER_PATH} is not executable"


def test_sanitizer_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.csv")
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for fpath in clean_files:
        with open(fpath, "rb") as f:
            input_data = f.read()

        result = run_filter(input_data)
        if result.returncode != 0:
            failed_files.append(os.path.basename(fpath))
            continue

        input_lines = [line for line in input_data.decode("utf-8").splitlines() if line.strip()]
        output_lines = [line for line in result.stdout.decode("utf-8").splitlines() if line.strip()]
        if len(output_lines) != len(input_lines):
            failed_files.append(os.path.basename(fpath))

        # Clean input must be preserved, rather than replaced by fabricated rows.
        if result.stdout != input_data:
            failed_files.append(os.path.basename(fpath))

    assert not failed_files, f"Clean files modified or rejected: {', '.join(sorted(set(failed_files)))}"


def test_sanitizer_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.csv")
    assert evil_files, "No evil corpus files found."

    failed_files = []
    for fpath in evil_files:
        with open(fpath, "rb") as f:
            input_data = f.read()

        result = run_filter(input_data)
        if result.returncode != 0:
            failed_files.append(os.path.basename(fpath))
            continue

        output_lines = [line for line in result.stdout.decode("utf-8").splitlines() if line.strip()]
        # Preserve the original assertion: output is empty or just one header line.
        if len(output_lines) > 1:
            failed_files.append(os.path.basename(fpath))

        header = input_data.splitlines(keepends=True)[0]
        if result.stdout not in (b"", header):
            failed_files.append(os.path.basename(fpath))

    assert not failed_files, f"Evil files bypassed or fabricated output: {', '.join(sorted(set(failed_files)))}"


def test_sanitizer_generated_mixed_csv():
    token = secrets.token_hex(12)
    header = csv_line(["timestamp", "user_id", "payload"])
    valid_plain = csv_line(["2025-04-03T07:01:02Z", "user-a", f"plain payload {token}"])
    valid_escape = csv_line(["2025-04-03T07:02:03Z", "user-b", f"valid \\u004A value,{token}"])
    valid_other_column = csv_line(["2025-04-03T07:03:04Z", f"user-{token}\\u12G4", "payload is still valid"])
    bad_hex = csv_line(["2025-04-03T07:04:05Z", "user-c", f"bad \\u12G4 {token}"])
    bad_short = csv_line(["2025-04-03T07:05:06Z", "user-d", f"bad, quoted \\u99 {token}"])
    bad_end = csv_line(["2025-04-03T07:06:07Z", "user-e", f"{token} ends \\u"])

    input_data = header + valid_plain + bad_hex + valid_escape + bad_short + valid_other_column + bad_end
    expected = header + valid_plain + valid_escape + valid_other_column
    result = run_filter(input_data)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    assert result.stdout == expected, "Sanitizer did not preserve exactly the generated valid CSV records"


def test_sanitizer_generated_all_evil():
    token = secrets.token_hex(10)
    header = csv_line(["timestamp", "user_id", "payload"])
    rows = b"".join([
        csv_line(["2025-05-01T00:00:00Z", "u1", f"{token} \\u-abc"]),
        csv_line(["2025-05-01T00:01:00Z", "u2", f"{token} \\u0X00"]),
        csv_line(["2025-05-01T00:02:00Z", "u3", f"{token} \\u123"]),
    ])
    result = run_filter(header + rows)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    assert result.stdout in (b"", header), "Generated malformed payload rows passed the sanitizer"


def parse_bucket(value):
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def test_aggregate_script():
    assert os.path.isfile(AGGREGATE_PATH), f"Aggregate script not found at {AGGREGATE_PATH}"
    assert os.access(AGGREGATE_PATH, os.X_OK), f"Aggregate script at {AGGREGATE_PATH} is not executable"

    with open(AGGREGATE_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "30" in content, "Aggregate script does not seem to implement 30-minute time bucketing."


def test_aggregate_generated_data():
    rng = random.SystemRandom()
    base = datetime(2025, rng.randint(1, 10), rng.randint(1, 20), rng.randint(1, 18), 0, tzinfo=timezone.utc)
    rows = []
    expected = {}

    for bucket_index in range(4):
        bucket = base + timedelta(minutes=30 * bucket_index)
        unique_count = rng.randint(1, 5)
        expected[bucket] = unique_count
        for event_index in range(unique_count):
            token = secrets.token_hex(10)
            payload = f"Event-{token}-{event_index}-AbCd"
            minute = rng.randint(0, 29)
            second = rng.randint(0, 59)
            timestamp = bucket + timedelta(minutes=minute, seconds=second)
            rows.append([timestamp.isoformat().replace("+00:00", "Z"), secrets.token_hex(4), payload])
            # A case-only variant must hash identically after lowercasing.
            dup_time = bucket + timedelta(minutes=rng.randint(0, 29), seconds=rng.randint(0, 59))
            rows.append([dup_time.isoformat().replace("+00:00", "Z"), secrets.token_hex(4), payload.swapcase()])

    rng.shuffle(rows)
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(["timestamp", "user_id", "payload"])
    writer.writerows(rows)

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", suffix=".csv", delete=False) as f:
        f.write(stream.getvalue())
        input_path = f.name

    try:
        result = subprocess.run([AGGREGATE_PATH, input_path], capture_output=True, text=True, timeout=15)
    finally:
        os.unlink(input_path)

    assert result.returncode == 0, result.stderr
    output_rows = list(csv.reader(io.StringIO(result.stdout)))
    assert output_rows, "Aggregator produced no CSV output"
    assert output_rows[0] == ["time_bucket", "unique_event_count"], "Incorrect summary CSV header"

    actual = {}
    for row in output_rows[1:]:
        assert len(row) == 2, f"Incorrect summary row: {row!r}"
        bucket = parse_bucket(row[0])
        assert bucket.minute in (0, 30) and bucket.second == 0 and bucket.microsecond == 0, "Bucket is not aligned to 30 minutes"
        assert bucket not in actual, "Aggregator emitted a bucket more than once"
        try:
            count = int(row[1])
        except ValueError:
            raise AssertionError(f"Non-integer unique_event_count: {row[1]!r}")
        actual[bucket] = count

    assert actual == expected, f"Incorrect bucketing or payload-hash deduplication: expected {expected}, got {actual}"


def cron_minutes(field):
    values = set()
    for part in field.split(","):
        if "/" in part:
            base, step_text = part.split("/", 1)
            step = int(step_text)
        else:
            base, step = part, 1

        if base == "*":
            start, end = 0, 59
        elif "-" in base:
            start_text, end_text = base.split("-", 1)
            start, end = int(start_text), int(end_text)
        else:
            start = end = int(base)

        assert 0 <= start <= end <= 59 and step > 0
        values.update(range(start, end + 1, step))
    return values


def test_cron_file():
    assert os.path.isfile(CRON_PATH), f"Cron file not found at {CRON_PATH}"

    with open(CRON_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "15" in content, "Cron file does not seem to schedule every 15 minutes."
    assert "aggregate.sh" in content, "Cron file does not reference aggregate.sh"
    assert "/tmp/latest.csv" in content, "Cron file does not reference /tmp/latest.csv"

    valid_entries = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ("=" in line and len(line.split()) == 1):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, day, month, weekday, command = fields
        try:
            minutes = cron_minutes(minute)
        except (ValueError, AssertionError):
            continue
        if minutes != {0, 15, 30, 45} or [hour, day, month, weekday] != ["*", "*", "*", "*"]:
            continue
        try:
            command_words = shlex.split(command)
        except ValueError:
            continue
        if AGGREGATE_PATH in command_words:
            aggregate_index = command_words.index(AGGREGATE_PATH)
            if "/tmp/latest.csv" in command_words[aggregate_index + 1:]:
                valid_entries.append(line)

    assert valid_entries, "No valid every-15-minutes cron entry runs aggregate.sh on /tmp/latest.csv"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
