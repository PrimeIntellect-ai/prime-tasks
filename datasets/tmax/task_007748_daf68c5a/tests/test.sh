#!/bin/bash
mkdir -p /logs/verifier
status=0
workdir=$(mktemp -d)

cp -a /home/user/input_data "$workdir/input_data"
if [ -d /home/user/output_data ]; then
    cp -a /home/user/output_data "$workdir/output_data"
    had_output=1
else
    had_output=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
from datetime import datetime, timezone

def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/pipeline.py"), "/home/user/pipeline.py does not exist."

def test_output_file_exists():
    assert os.path.isfile("/home/user/output_data/clean_data.csv"), "/home/user/output_data/clean_data.csv does not exist."

def test_output_csv_content():
    output_file = "/home/user/output_data/clean_data.csv"

    with open(output_file, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)

    assert header == ["record_hash", "timestamp", "sensor_id", "temperature", "humidity"], "Header is incorrect."

    expected_rows = [
        ["9f4007b8862f90117a228399f57eb318", "2021-10-01T00:00:00Z", "A", "20.0", "40.0"],
        ["eab4463ce8cba2f30af0a2b535d47065", "2021-10-01T00:01:00Z", "A", "21.0", "41.0"],
        ["ceab44f1c9fc601f0165c7865dc601d3", "2021-10-01T00:02:00Z", "A", "22.0", "42.0"],
        ["ff0af19cd91d4e787bb7b60ffbe52bb8", "2021-10-01T00:03:00Z", "A", "23.0", "43.0"],
        ["106bc666a70d8a4f0bbd4a27572624d5", "2021-10-01T00:00:00Z", "B", "15.0", "50.0"],
        ["601ed85deab587e915002ba50bb5a2e9", "2021-10-01T00:01:00Z", "B", "16.0", "51.0"],
        ["795a98297b5e40632bca60d4b9668d2b", "2021-10-01T00:02:00Z", "B", "17.0", "52.0"]
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row == expected, f"Row {i+1} mismatch. Expected {expected}, got {row}."

def test_output_csv_formatting_and_logic():
    output_file = "/home/user/output_data/clean_data.csv"
    if not os.path.isfile(output_file):
        return

    with open(output_file, "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    for row in rows:
        assert "." in row["temperature"] and len(row["temperature"].split(".")[1]) == 1, f"Temperature {row['temperature']} not formatted to 1 decimal place."
        assert "." in row["humidity"] and len(row["humidity"].split(".")[1]) == 1, f"Humidity {row['humidity']} not formatted to 1 decimal place."

        try:
            datetime.strptime(row["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            assert False, f"Timestamp {row['timestamp']} does not match ISO8601 UTC format YYYY-MM-DDTHH:MM:SSZ."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

rm -rf /home/user/input_data /home/user/output_data
mkdir -p /home/user/input_data

cat << 'EOF' > /home/user/input_data/part_one.csv
timestamp,sensor_id,temperature,humidity
1633046700,Z,10.0,60.0
2021-10-01T00:04:00Z,A,30.0,44.0
1633046760,Z,,61.0
1633046700,Z,10.0,60.0
EOF

cat << 'EOF' > /home/user/input_data/part_two.csv
timestamp,sensor_id,temperature,humidity
2021-10-01T00:06:00Z,A,34.0,46.0
2021-10-01T00:05:00Z,A,,45.0
1633046820,Z,14.0,62.0
EOF

python3 /home/user/pipeline.py || status=1

cat << 'TEST_EOF' > /tmp/test_altered_input.py
import csv
import glob
import hashlib
import os
from datetime import datetime, timezone

INPUT_DIR = "/home/user/input_data"
OUTPUT_FILE = "/home/user/output_data/clean_data.csv"
HEADER = ["record_hash", "timestamp", "sensor_id", "temperature", "humidity"]

def normalize_timestamp(value):
    if value.isdigit():
        dt = datetime.fromtimestamp(int(value), tz=timezone.utc)
    else:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def derive_expected():
    combined = []
    for path in sorted(glob.glob(os.path.join(INPUT_DIR, "*.csv"))):
        with open(path, newline="") as f:
            combined.extend(csv.DictReader(f))

    deduplicated = []
    seen = set()
    for row in combined:
        digest = hashlib.md5((row["timestamp"] + row["sensor_id"]).encode()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        deduplicated.append({
            "record_hash": digest,
            "timestamp": normalize_timestamp(row["timestamp"]),
            "sensor_id": row["sensor_id"],
            "temperature": None if row["temperature"] == "" else float(row["temperature"]),
            "humidity": float(row["humidity"]),
        })

    deduplicated.sort(key=lambda row: (row["sensor_id"], row["timestamp"]))

    for sensor_id in sorted({row["sensor_id"] for row in deduplicated}):
        group = [row for row in deduplicated if row["sensor_id"] == sensor_id]
        for index, row in enumerate(group):
            if row["temperature"] is not None:
                continue
            before = next(i for i in range(index - 1, -1, -1) if group[i]["temperature"] is not None)
            after = next(i for i in range(index + 1, len(group)) if group[i]["temperature"] is not None)
            left = group[before]["temperature"]
            right = group[after]["temperature"]
            row["temperature"] = left + (right - left) * (index - before) / (after - before)

    return [[
        row["record_hash"], row["timestamp"], row["sensor_id"],
        f'{row["temperature"]:.1f}', f'{row["humidity"]:.1f}'
    ] for row in deduplicated]

def test_pipeline_on_altered_inputs():
    assert os.path.isfile("/home/user/pipeline.py")
    assert os.path.isfile(OUTPUT_FILE), "Running pipeline.py did not create clean_data.csv"

    with open(OUTPUT_FILE, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual = list(reader)

    expected = derive_expected()
    assert header == HEADER
    assert len(expected) == 6
    assert actual == expected
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_altered_input.py -x --tb=short 2>&1 || status=1

rm -rf /home/user/input_data /home/user/output_data
cp -a "$workdir/input_data" /home/user/input_data
if [ "$had_output" -eq 1 ]; then
    cp -a "$workdir/output_data" /home/user/output_data
fi
rm -rf "$workdir"

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
