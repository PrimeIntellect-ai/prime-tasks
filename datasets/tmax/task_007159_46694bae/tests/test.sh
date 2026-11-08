#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest

def test_processed_data_exists():
    file_path = "/home/user/processed_data.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

def test_processed_data_utf8_encoding():
    file_path = "/home/user/processed_data.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            f.read()
    except UnicodeDecodeError:
        pytest.fail(f"The file {file_path} is not valid UTF-8.")

def test_processed_data_contents():
    file_path = "/home/user/processed_data.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

    expected_rows = [
        ['id', 'timestamp', 'log_message', 'temperature', 'rolling_avg'],
        ['1', '2023-10-01T10:00:00', 'User [REDACTED_EMAIL] connected', '20.00', '20.00'],
        ['2', '2023-10-01T10:01:00', 'Café machine active [REDACTED_EMAIL]', '20.00', '20.00'],
        ['3', '2023-10-01T10:02:00', 'Normal operation', '22.00', '20.67'],
        ['4', '2023-10-01T10:03:00', 'Alert sent to [REDACTED_EMAIL]', '22.00', '21.33'],
        ['5', '2023-10-01T10:04:00', 'Shutdown initiated by [REDACTED_EMAIL]', '25.00', '23.00']
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch. Expected: {expected}, but got: {actual}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_pipeline.py
import csv
import os
import re
import secrets
import subprocess

project = "/home/user/sensor_etl"
raw_path = "/home/user/raw_sensor_data.csv"
out_path = "/home/user/processed_data.csv"

base = 10 + secrets.randbelow(20)
id_base = 1000 + secrets.randbelow(8000)
token = secrets.token_hex(6)
email1 = f"alpha.{token}@example.net"
email2 = f"ops+{token}@sub.domain.org"
email3 = f"user_{token}@service.co.uk"

input_rows = [
    [str(id_base), "2024-02-01T08:00:00", f"Device café {email1} connected", str(base)],
    [str(id_base + 1), "2024-02-01T08:01:00", "Müller status nominal", ""],
    [str(id_base + 2), "2024-02-01T08:02:00", f"Notify {email2} now", str(base + 3)],
    [str(id_base + 3), "2024-02-01T08:03:00", "No address here", ""],
    [str(id_base + 4), "2024-02-01T08:04:00", f"Owner {email3}", str(base - 2)],
    [str(id_base + 5), "2024-02-01T08:05:00", "Routine operation", str(base + 5)],
    [str(id_base + 6), "2024-02-01T08:06:00", f"Final report to {email1}", ""],
]

with open(raw_path, "w", encoding="iso-8859-1", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["id", "timestamp", "log_message", "temperature"])
    writer.writerows(input_rows)

if os.path.exists(out_path):
    os.unlink(out_path)

subprocess.run(
    ["cargo", "run", "--quiet"],
    cwd=project,
    check=True,
    timeout=180,
)

assert os.path.isfile(out_path), "The Rust program did not regenerate processed_data.csv"
with open(out_path, "r", encoding="utf-8", newline="") as f:
    actual = list(csv.reader(f))

email_re = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
expected = [["id", "timestamp", "log_message", "temperature", "rolling_avg"]]
last = None
window = []
for row in input_rows:
    if row[3] != "":
        last = float(row[3])
    window.append(last)
    window = window[-3:]
    expected.append([
        row[0],
        row[1],
        email_re.sub("[REDACTED_EMAIL]", row[2]),
        f"{last:.2f}",
        f"{sum(window) / len(window):.2f}",
    ])

assert actual == expected, f"Dynamic pipeline output mismatch. Expected {expected!r}, got {actual!r}"
DYNAMIC_EOF

verify() {
    [ -d /home/user/sensor_etl ] || return 1
    [ -f /home/user/sensor_etl/Cargo.toml ] || return 1
    find /home/user/sensor_etl -type f -name '*.rs' -print -quit | grep -q . || return 1

    python3 - << 'PY_EOF' || return 1
data = """id,timestamp,log_message,temperature
1,2023-10-01T10:00:00,User constr@example.com connected,20.0
2,2023-10-01T10:01:00,Café machine active admin@test.org,,
3,2023-10-01T10:02:00,Normal operation,22.0
4,2023-10-01T10:03:00,Alert sent to bob123@domain.co.uk,,
5,2023-10-01T10:04:00,Shutdown initiated by z_user@sub.domain.com,25.0
"""
with open("/home/user/raw_sensor_data.csv", "wb") as f:
    f.write(data.encode("iso-8859-1"))
PY_EOF

    rm -f /home/user/processed_data.csv || return 1
    (cd /home/user/sensor_etl && timeout 180 cargo build --quiet) || return 1
    (cd /home/user/sensor_etl && timeout 180 cargo run --quiet) || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
    python3 /tmp/test_dynamic_pipeline.py || return 1
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
