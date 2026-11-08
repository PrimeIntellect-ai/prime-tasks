#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import sys
from datetime import datetime, timedelta

RAW_FILE = '/home/user/raw_chat.csv'
OUT_FILE = '/home/user/chat_summary.csv'
SCRIPT_FILE = '/home/user/process_chat.py'


def validate_summary(raw_file, out_file):
    assert os.path.exists(raw_file), f"Raw file {raw_file} is missing."
    assert os.path.exists(out_file), f"Output file {out_file} was not created."
    assert os.path.isfile(out_file), f"{out_file} is not a file."

    raw_data = []
    with open(raw_file, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = datetime.fromisoformat(row['timestamp'])
            msg_len = len(row['message'].strip())
            raw_data.append({
                'ts': ts,
                'room': row['chat_room'],
                'msg_len': msg_len,
            })

    assert raw_data, "Raw data is empty."

    min_ts = min(r['ts'] for r in raw_data)
    max_ts = max(r['ts'] for r in raw_data)
    start_hour = min_ts.replace(minute=0, second=0, microsecond=0)
    end_hour = max_ts.replace(minute=0, second=0, microsecond=0)
    rooms = sorted(set(r['room'] for r in raw_data))

    hourly_sums = {}
    curr = start_hour
    while curr <= end_hour:
        hourly_sums[curr] = {room: 0 for room in rooms}
        curr += timedelta(hours=1)

    for row in raw_data:
        hour = row['ts'].replace(minute=0, second=0, microsecond=0)
        hourly_sums[hour][row['room']] += row['msg_len']

    expected_output = {}
    curr = start_hour
    while curr <= end_hour:
        expected_output[curr] = {}
        for room in rooms:
            total = 0
            for i in range(3):
                hour = curr - timedelta(hours=i)
                if hour in hourly_sums:
                    total += hourly_sums[hour][room]
            expected_output[curr][room] = total
        curr += timedelta(hours=1)

    with open(out_file, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            assert False, f"Output file {out_file} is empty."

        expected_headers = ['timestamp'] + rooms
        assert headers == expected_headers, (
            f"Headers mismatch. Expected {expected_headers}, got {headers}"
        )
        out_rows = list(reader)

    assert len(out_rows) == len(expected_output), (
        f"Expected {len(expected_output)} rows, got {len(out_rows)}"
    )

    curr = start_hour
    for row in out_rows:
        ts_str = curr.strftime('%Y-%m-%d %H:%M:%S')
        assert row[0] == ts_str, f"Expected timestamp '{ts_str}', got '{row[0]}'"
        assert len(row) == len(rooms) + 1, (
            f"Expected {len(rooms) + 1} fields at {ts_str}, got {len(row)}"
        )
        for i, room in enumerate(rooms):
            expected_val = float(expected_output[curr][room])
            try:
                actual_val = float(row[i + 1])
            except ValueError:
                assert False, (
                    f"Non-numeric value '{row[i + 1]}' found for room "
                    f"'{room}' at timestamp '{ts_str}'"
                )
            assert actual_val == expected_val, (
                f"Value mismatch at {ts_str} for room '{room}'. "
                f"Expected {expected_val}, got {actual_val}."
            )
        curr += timedelta(hours=1)


def run_script():
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_chat.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUT_FILE), (
        "process_chat.py completed without creating /home/user/chat_summary.csv"
    )
    assert os.path.isfile(OUT_FILE), f"{OUT_FILE} is not a file."


def main():
    # Preserve the original verifier's checks against the submitted report.
    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} was not created."
    assert os.path.isfile(OUT_FILE), f"{OUT_FILE} is not a file."
    validate_summary(RAW_FILE, OUT_FILE)

    assert os.path.exists(SCRIPT_FILE), f"Required script {SCRIPT_FILE} is missing."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a regular file."

    with open(RAW_FILE, 'rb') as f:
        original_raw = f.read()
    with open(OUT_FILE, 'rb') as f:
        original_output = f.read()

    try:
        # The script must regenerate the report for the original input.
        run_script()
        validate_summary(RAW_FILE, OUT_FILE)

        # Exercise the ETL on an unpredictable valid CSV so a fixed report or
        # hard-coded implementation cannot pass.
        token = secrets.token_hex(4)
        room_a = f'alpha_{token}'
        room_b = f'zeta_{token}'
        day = 10 + secrets.randbelow(10)
        base = datetime(2024, 2, day, 3, 0, 0)
        rows = [
            {
                'timestamp': (base + timedelta(minutes=5)).isoformat(),
                'user_id': 'u1',
                'chat_room': room_b,
                'message': '  hello, world\n世界 🙂  ',
            },
            {
                'timestamp': (base + timedelta(minutes=47)).isoformat(),
                'user_id': 'u2',
                'chat_room': room_b,
                'message': 'quote: "yes"',
            },
            {
                'timestamp': (base + timedelta(hours=1, minutes=20)).isoformat(),
                'user_id': 'u3',
                'chat_room': room_a,
                'message': '\n  こんにちは  \n',
            },
            {
                'timestamp': (base + timedelta(hours=3, minutes=1)).isoformat(),
                'user_id': 'u4',
                'chat_room': room_b,
                'message': 'x',
            },
            {
                'timestamp': (base + timedelta(hours=5, minutes=55)).isoformat(),
                'user_id': 'u5',
                'chat_room': room_a,
                'message': ' final\nmessage 🚀 ',
            },
        ]
        with open(RAW_FILE, 'w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(
                f,
                fieldnames=['timestamp', 'user_id', 'chat_room', 'message'],
                quoting=csv.QUOTE_ALL,
            )
            writer.writeheader()
            writer.writerows(rows)

        run_script()
        validate_summary(RAW_FILE, OUT_FILE)
    finally:
        with open(RAW_FILE, 'wb') as f:
            f.write(original_raw)
        with open(OUT_FILE, 'wb') as f:
            f.write(original_output)


if __name__ == '__main__':
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
