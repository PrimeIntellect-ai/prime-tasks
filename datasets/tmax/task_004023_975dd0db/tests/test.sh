#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shutil
import subprocess

EXECUTABLE = "/home/user/aggregator"
INPUT = "/home/user/translation_events.jsonl"
OUTPUT = "/home/user/throughput_stats.csv"
HEADER = ["bucket_ts", "lang", "hourly_words", "rolling_3h_avg"]


def expected_rows(input_path):
    totals = {}
    with open(input_path, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            event = json.loads(line)
            ts = int(event["ts"])
            lang = str(event["lang"])
            words = int(event["words"])
            bucket = ts - (ts % 3600)
            key = (bucket, lang)
            totals[key] = totals.get(key, 0) + words

    rows = []
    for bucket, lang in sorted(totals, key=lambda key: (key[0], key[1])):
        hourly = totals[(bucket, lang)]
        rolling_sum = (
            hourly
            + totals.get((bucket - 3600, lang), 0)
            + totals.get((bucket - 7200, lang), 0)
        )
        rows.append([
            str(bucket),
            lang,
            str(hourly),
            f"{rolling_sum / 3.0:.2f}",
        ])
    return rows


def validate_output(input_path):
    assert os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}"

    with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
        first_line = f.readline().rstrip("\r\n")
        assert first_line == ",".join(HEADER), (
            f"CSV header must be exactly {','.join(HEADER)!r}, got {first_line!r}"
        )
        f.seek(0)
        reader = csv.reader(f)
        header = next(reader)
        assert header == HEADER
        actual = list(reader)

    expected = expected_rows(input_path)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} data rows, got {len(actual)}"
    )

    for index, (got, want) in enumerate(zip(actual, expected), 2):
        assert len(got) == 4, f"CSV row {index} has {len(got)} columns instead of 4"
        assert got == want, f"Incorrect or unsorted CSV row {index}: expected {want}, got {got}"


def run_aggregator(timeout):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Aggregator exited with status {result.returncode}. "
        f"stdout={result.stdout[-2000:]!r}, stderr={result.stderr[-2000:]!r}"
    )


def main():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "aggregator must be a compiled executable"

    # Re-run the submitted executable on the supplied data rather than trusting a
    # pre-created CSV, then validate every field and the required ordering.
    run_aggregator(180)
    validate_output(INPUT)

    input_backup = INPUT + ".verifier_backup"
    output_backup = OUTPUT + ".verifier_backup"
    for path in (input_backup, output_backup):
        if os.path.exists(path):
            os.remove(path)

    os.replace(INPUT, input_backup)
    os.replace(OUTPUT, output_backup)
    try:
        # Hidden-data behavioral check. It includes absent preceding hours,
        # multiple events in a bucket, interleaved languages, and unsorted input.
        events = [
            {"ts": 18005, "lang": "z-ZZ", "words": 90},
            {"ts": 7210, "lang": "z-ZZ", "words": 10},
            {"ts": 7250, "lang": "z-ZZ", "words": 20},
            {"ts": 10801, "lang": "z-ZZ", "words": 60},
            {"ts": 3601, "lang": "a-AA", "words": 9},
            {"ts": 10803, "lang": "a-AA", "words": 15},
            {"ts": 7202, "lang": "a-AA", "words": 5},
            {"ts": 7300, "lang": "a-AA", "words": 7},
            {"ts": 14410, "lang": "m-MM", "words": 6},
        ]
        with open(INPUT, "w", encoding="utf-8") as f:
            for event in events:
                f.write(json.dumps(event, separators=(",", ":")) + "\n")

        run_aggregator(30)
        validate_output(INPUT)
    finally:
        if os.path.exists(INPUT):
            os.remove(INPUT)
        os.replace(input_backup, INPUT)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(output_backup):
            os.replace(output_backup, OUTPUT)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
