#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import time

RAW_PATH = "/home/user/raw_edits.jsonl"
SCRIPT_PATH = "/home/user/process_loc.sh"
CSV_PATH = "/home/user/hourly_loc_stats.csv"
LOG_PATH = "/home/user/process.log"
HOURS = ["08", "09", "10", "11", "12"]
LOCALES = ["de-DE", "es-ES", "fr-FR"]


def expected_csv(events):
    stats = {
        (f"2023-10-01T{hour}:00:00Z", locale): 0
        for hour in HOURS
        for locale in LOCALES
    }
    for event in events:
        bucket = event["timestamp"][:13] + ":00:00Z"
        key = (bucket, event["locale"])
        if key in stats:
            stats[key] += int(event["words"] * (event["tm_match"] / 100))

    lines = ["timestamp,locale,effective_words"]
    for hour in HOURS:
        for locale in LOCALES:
            timestamp = f"2023-10-01T{hour}:00:00Z"
            lines.append(f"{timestamp},{locale},{stats[(timestamp, locale)]}")
    return lines


def write_events(events):
    with open(RAW_PATH, "w") as handle:
        for event in events:
            handle.write(json.dumps(event, separators=(",", ":")) + "\n")


def random_events(count):
    events = []
    # Ensure every required locale is represented while leaving gaps in hours.
    for locale in LOCALES:
        hour = HOURS[secrets.randbelow(len(HOURS))]
        tm_match = [0, 25, 50, 75, 100][secrets.randbelow(5)]
        events.append({
            "timestamp": f"2023-10-01T{hour}:{secrets.randbelow(60):02d}:{secrets.randbelow(60):02d}Z",
            "locale": locale,
            "words": 4 * (1 + secrets.randbelow(100)),
            "tm_match": tm_match,
        })
    while len(events) < count:
        locale = LOCALES[secrets.randbelow(len(LOCALES))]
        hour = HOURS[secrets.randbelow(len(HOURS))]
        tm_match = [0, 25, 50, 75, 100][secrets.randbelow(5)]
        events.append({
            "timestamp": f"2023-10-01T{hour}:{secrets.randbelow(60):02d}:{secrets.randbelow(60):02d}Z",
            "locale": locale,
            "words": 4 * (1 + secrets.randbelow(100)),
            "tm_match": tm_match,
        })
    return events


def run_pipeline():
    before = time.time()
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    after = time.time()
    assert result.returncode == 0, (
        f"process_loc.sh failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return before, after


def assert_csv(events):
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} is missing."
    with open(CSV_PATH) as handle:
        actual = [line.strip() for line in handle if line.strip()]
    expected = expected_csv(events)
    assert actual == expected, f"CSV content mismatch.\nExpected:\n{expected}\nGot:\n{actual}"


def parse_datetime(value):
    result = subprocess.run(
        ["date", "-d", value, "+%s"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Log datetime is not valid: {value!r}"
    return int(result.stdout.strip())


def assert_log(run_windows, event_counts):
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH) as handle:
        lines = [line.rstrip("\n") for line in handle]

    starts = []
    ends = []
    for index, line in enumerate(lines):
        if line.endswith(" PIPELINE_START") and line.startswith("["):
            assert "] PIPELINE_START" in line, "Malformed PIPELINE_START entry."
            dt = line[1:-len("] PIPELINE_START")]
            assert dt and "]" not in dt, "Malformed PIPELINE_START datetime."
            starts.append((index, parse_datetime(dt)))
        if " PIPELINE_END - Processed " in line and line.startswith("["):
            marker = "] PIPELINE_END - Processed "
            assert marker in line and line.endswith(" events"), "Malformed PIPELINE_END entry."
            dt, count_text = line[1:].split(marker, 1)
            count_text = count_text[:-len(" events")]
            assert count_text.isdigit(), "PIPELINE_END event count is not an integer."
            ends.append((index, parse_datetime(dt), int(count_text)))

    assert len(starts) == len(event_counts), "Log must contain one PIPELINE_START entry per run."
    assert len(ends) == len(event_counts), "Log must contain one PIPELINE_END entry per run."

    for i, ((start_index, start_time), (end_index, end_time, count)) in enumerate(zip(starts, ends)):
        before, after = run_windows[i]
        assert start_index < end_index, "PIPELINE_START must precede PIPELINE_END."
        assert count == event_counts[i], f"Incorrect processed event count: expected {event_counts[i]}, got {count}."
        assert before - 120 <= start_time <= after + 120, "PIPELINE_START datetime is not current."
        assert before - 120 <= end_time <= after + 120, "PIPELINE_END datetime is not current."
        assert start_time <= end_time + 1, "PIPELINE_END datetime precedes PIPELINE_START."


def test_bash_pipeline_and_outputs():
    assert os.path.exists(RAW_PATH), f"File {RAW_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Bash script {SCRIPT_PATH} is missing or is not a regular file."
    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, f"process_loc.sh is not valid Bash syntax:\n{syntax.stderr}"

    with open(RAW_PATH, "rb") as handle:
        original_raw = handle.read()
    original_events = [json.loads(line) for line in original_raw.decode().splitlines() if line.strip()]

    try:
        for path in (CSV_PATH, LOG_PATH):
            if os.path.lexists(path):
                os.remove(path)

        first_events = random_events(7)
        write_events(first_events)
        first_window = run_pipeline()
        assert_csv(first_events)
        assert_log([first_window], [len(first_events)])
        with open(LOG_PATH, "rb") as handle:
            first_log = handle.read()

        second_events = random_events(10)
        write_events(second_events)
        second_window = run_pipeline()
        assert_csv(second_events)
        with open(LOG_PATH, "rb") as handle:
            second_log = handle.read()
        assert second_log.startswith(first_log), "process.log was overwritten instead of appended."
        assert_log([first_window, second_window], [len(first_events), len(second_events)])

        with open(RAW_PATH, "wb") as handle:
            handle.write(original_raw)
        third_window = run_pipeline()
        assert_csv(original_events)
        with open(LOG_PATH, "rb") as handle:
            third_log = handle.read()
        assert third_log.startswith(second_log), "process.log was overwritten instead of appended."
        assert_log(
            [first_window, second_window, third_window],
            [len(first_events), len(second_events), len(original_events)],
        )
    finally:
        with open(RAW_PATH, "wb") as handle:
            handle.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
