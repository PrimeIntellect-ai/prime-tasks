#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    test -f /home/user/clean_data.go || return 1
    go build -o /tmp/clean_data_bin /home/user/clean_data.go || return 1

    cat > /home/user/data/events.csv <<'EOF' || return 1
event_id,user_id,value
evt_001,1001,45.5
evt_002,,50.0
evt_003,NaN,12.3
evt_004,1002,11.1
evt_005,1.2e4,99.9
evt_006,1003.0,44.4
evt_007,-99,0.0
evt_008,0,1.1
evt_009,null,5.5
evt_010,1004,8.8
EOF

    rm -f /home/user/data/cleaned.csv /home/user/anomalies.txt
    runuser -u user -- timeout 10s /tmp/clean_data_bin || return 1

    cat > /tmp/test_final_state.py <<'TEST_EOF' || return 1
import os

def test_go_file_exists():
    file_path = "/home/user/clean_data.go"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

def test_cleaned_csv_content():
    file_path = "/home/user/data/cleaned.csv"
    assert os.path.isfile(file_path), f"File {file_path} was not created."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "event_id,user_id,value",
        "evt_001,1001,45.5",
        "evt_004,1002,11.1",
        "evt_007,-99,0.0",
        "evt_008,0,1.1",
        "evt_010,1004,8.8"
    ]

    assert lines == expected_lines, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )

def test_anomalies_txt_content():
    file_path = "/home/user/anomalies.txt"
    assert os.path.isfile(file_path), f"File {file_path} was not created."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "evt_003",
        "evt_005",
        "evt_006",
        "evt_009"
    ]

    assert lines == expected_lines, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    python3 - <<'PY' || return 1
import csv
import os
import random
import secrets
import subprocess

source = "/home/user/data/events.csv"
cleaned = "/home/user/data/cleaned.csv"
anomalies = "/home/user/anomalies.txt"
binary = "/tmp/clean_data_bin"

for trial in range(2):
    token = secrets.token_hex(6)
    positive = random.SystemRandom().randint(20000, 900000000)
    negative = -random.SystemRandom().randint(1, 900000000)

    classified_rows = [
        ([f"valid_a_{token}", str(positive), "17.25"], "valid"),
        ([f"missing_{token}", "", "18.50"], "missing"),
        ([f"nan_{token}", "NaN", "19.75"], "anomaly"),
        ([f"valid_b_{token}", str(negative), "20.00"], "valid"),
        ([f"decimal_{token}", f"{positive}.0", "21.25"], "anomaly"),
        ([f"scientific_{token}", f"{positive}e2", "22.50"], "anomaly"),
        ([f"zero_{token}", "0", "23.75"], "valid"),
        ([f"null_{token}", "null", "24.00"], "anomaly"),
        ([f"space_{token}", " 42", "25.25"], "anomaly"),
    ]
    random.SystemRandom().shuffle(classified_rows)

    with open(source, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["event_id", "user_id", "value"])
        writer.writerows(row for row, _ in classified_rows)

    for path in (cleaned, anomalies):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        ["runuser", "-u", "user", "--", "timeout", "10s", binary],
        check=True,
        timeout=12,
    )

    assert os.path.isfile(cleaned), "cleaned.csv was not created on generated input"
    assert os.path.isfile(anomalies), "anomalies.txt was not created on generated input"

    expected_cleaned = [["event_id", "user_id", "value"]] + [
        row for row, kind in classified_rows if kind == "valid"
    ]
    expected_anomalies = [
        row[0] for row, kind in classified_rows if kind == "anomaly"
    ]

    with open(cleaned, newline="") as f:
        actual_cleaned = list(csv.reader(f))
    with open(anomalies) as f:
        actual_anomalies = f.read().splitlines()

    assert actual_cleaned == expected_cleaned, (
        f"generated-input cleaned.csv mismatch: expected {expected_cleaned!r}, "
        f"got {actual_cleaned!r}"
    )
    assert actual_anomalies == expected_anomalies, (
        f"generated-input anomalies mismatch: expected {expected_anomalies!r}, "
        f"got {actual_anomalies!r}"
    )
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
