#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import shutil
import subprocess
from datetime import datetime, timedelta, timezone

CPP = "/home/user/etl_pipeline.cpp"
BIN = "/home/user/etl_pipeline"
OUTPUT = "/home/user/output/aligned_5min.csv"
TEMP = "/home/user/data/temp.csv"
HUMIDITY = "/home/user/data/humidity.csv"


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([BIN], cwd="/home/user", check=True, timeout=20)
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did the program run and generate it?"


def read_output():
    with open(OUTPUT, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError("Output file is empty.")
        rows = list(reader)
    return header, rows


def check_original_output():
    assert os.path.isfile(OUTPUT), "Output file missing."
    header, rows = read_output()
    assert header == ["bucket", "temp_avg", "humidity_avg"], f"Header is incorrect. Got: {header}"
    assert len(rows) == 2, f"Expected exactly 2 data rows, but got {len(rows)}."

    data_dict = {row[0]: (row[1], row[2]) for row in rows}
    expected_data = {
        "2023-10-01T10:00:00Z": ("21.00", "55.00"),
        "2023-10-01T10:05:00Z": ("20.00", "60.00"),
    }
    for bucket, expected_vals in expected_data.items():
        assert bucket in data_dict, f"Missing bucket {bucket} in the output."
        actual_vals = data_dict[bucket]
        assert actual_vals[0] == expected_vals[0], f"Incorrect temp_avg for bucket {bucket}. Expected {expected_vals[0]}, got {actual_vals[0]}."
        assert actual_vals[1] == expected_vals[1], f"Incorrect humidity_avg for bucket {bucket}. Expected {expected_vals[1]}, got {actual_vals[1]}."
    for bucket in data_dict:
        assert bucket in expected_data, f"Unexpected bucket {bucket} found in the output."


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def write_feed(path, value_header, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\r\n")
        writer.writerow(["timestamp", value_header, "notes"])
        writer.writerows(rows)


def check_generated_case():
    rng = random.SystemRandom()
    base = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(days=rng.randrange(500))
    bucket_numbers = rng.sample(range(288), 6)
    common = bucket_numbers[:4]
    temp_only = bucket_numbers[4]
    humidity_only = bucket_numbers[5]

    temp_rows = []
    humidity_rows = []
    expected = {}
    multiline_notes = [
        'first line\nsecond line, with comma\nand a "quoted" word',
        'sensor report\ncontinued on another line',
        'embedded "quotes", commas,\nand multiple\nnewlines',
    ]

    for i, bucket_number in enumerate(common):
        bucket = base + timedelta(minutes=5 * bucket_number)
        temp_mean_cents = rng.randrange(-1500, 4501)
        hum_mean_cents = rng.randrange(500, 9501)
        temp_delta = rng.randrange(1, 300)
        hum_delta = rng.randrange(1, 500)

        temp_rows.extend([
            [iso(bucket + timedelta(seconds=rng.randrange(0, 150))), f"{(temp_mean_cents-temp_delta)/100:.2f}", multiline_notes[i % len(multiline_notes)]],
            [iso(bucket + timedelta(seconds=rng.randrange(150, 300))), f"{(temp_mean_cents+temp_delta)/100:.2f}", "ordinary note"],
        ])
        humidity_rows.extend([
            [iso(bucket + timedelta(seconds=rng.randrange(0, 150))), f"{(hum_mean_cents-hum_delta)/100:.2f}", multiline_notes[(i+1) % len(multiline_notes)]],
            [iso(bucket + timedelta(seconds=rng.randrange(150, 300))), f"{(hum_mean_cents+hum_delta)/100:.2f}", "ordinary note"],
        ])
        expected[iso(bucket)] = (f"{temp_mean_cents/100:.2f}", f"{hum_mean_cents/100:.2f}")

    bucket = base + timedelta(minutes=5 * temp_only)
    temp_rows.append([iso(bucket + timedelta(seconds=rng.randrange(300))), "99.25", multiline_notes[0]])
    bucket = base + timedelta(minutes=5 * humidity_only)
    humidity_rows.append([iso(bucket + timedelta(seconds=rng.randrange(300))), "12.75", multiline_notes[1]])

    rng.shuffle(temp_rows)
    rng.shuffle(humidity_rows)
    write_feed(TEMP, "temperature", temp_rows)
    write_feed(HUMIDITY, "humidity", humidity_rows)

    run_pipeline()
    header, rows = read_output()
    assert header == ["bucket", "temp_avg", "humidity_avg"], f"Header is incorrect on generated inputs: {header}"
    assert all(len(row) == 3 for row in rows), f"Malformed output rows: {rows}"
    assert len(rows) == len(expected), f"Expected {len(expected)} joined buckets, got {len(rows)}: {rows}"
    actual = {row[0]: (row[1], row[2]) for row in rows}
    assert len(actual) == len(rows), "Output contains duplicate bucket rows."
    assert actual == expected, f"Incorrect aggregation/join for generated RFC 4180 inputs. Expected {expected}, got {actual}"


def main():
    assert os.path.isfile(CPP), f"C++ source file {CPP} is missing."
    temp_backup = open(TEMP, "rb").read()
    humidity_backup = open(HUMIDITY, "rb").read()
    try:
        subprocess.run(
            ["g++", "-O2", "-std=c++17", CPP, "-o", BIN],
            check=True,
            timeout=60,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert os.path.isfile(BIN) and os.access(BIN, os.X_OK), "Compilation did not produce an executable pipeline."

        run_pipeline()
        check_original_output()
        check_generated_case()
    finally:
        with open(TEMP, "wb") as f:
            f.write(temp_backup)
        with open(HUMIDITY, "wb") as f:
            f.write(humidity_backup)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
