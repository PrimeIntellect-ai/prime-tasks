#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import subprocess

SOURCE = "/home/user/analyze_logs.cpp"
BINARY = "/home/user/analyze_logs"
OUTPUT = "/home/user/anomalies.csv"
LOG_A = "/home/user/sensor_a.log"
LOG_B = "/home/user/sensor_b.log"
HEADER = ["timestamp_a", "X_a", "Y_a", "timestamp_b", "X_b", "Y_b", "distance"]

ORIGINAL_A = """[2023-10-25 14:22:01.150] INFO: Position detected at X=12.50 Y=4.20
[2023-10-25 14:22:02.500] INFO: Position detected at X=15.00 Y=5.00
[2023-10-25 14:22:03.100] INFO: Position detected at X=10.00 Y=10.00
[2023-10-25 14:22:04.900] INFO: Position detected at X=0.00 Y=0.00
"""
ORIGINAL_B = """[2023-10-25 14:22:01.180] TRACE: Object tracking - coord: (12.40, 4.30)
[2023-10-25 14:22:02.550] TRACE: Object tracking - coord: (12.00, 2.00)
[2023-10-25 14:22:03.250] TRACE: Object tracking - coord: (10.10, 10.10)
[2023-10-25 14:22:04.990] TRACE: Object tracking - coord: (3.00, 4.00)
"""


def write_logs(text_a, text_b):
    with open(LOG_A, "w") as f:
        f.write(text_a)
    with open(LOG_B, "w") as f:
        f.write(text_b)


def execute_and_read(executable):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([executable], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Missing output file after executing {executable}: {OUTPUT}"
    with open(OUTPUT, "r", newline="") as f:
        return list(csv.reader(f))


def timestamp(ms):
    hours, rem = divmod(ms, 3600000)
    minutes, rem = divmod(rem, 60000)
    seconds, millis = divmod(rem, 1000)
    return f"2023-10-25 {hours:02d}:{minutes:02d}:{seconds:02d}.{millis:03d}"


def make_log_text(entries_a, entries_b):
    a_text = "".join(
        f"[{timestamp(t)}] INFO: Position detected at X={x:.2f} Y={y:.2f}\n"
        for t, x, y in entries_a
    )
    b_text = "".join(
        f"[{timestamp(t)}] TRACE: Object tracking - coord: ({x:.2f}, {y:.2f})\n"
        for t, x, y in entries_b
    )
    return a_text, b_text


def independently_expected(entries_a, entries_b):
    rows = [HEADER]
    for ta, xa, ya in entries_a:
        best = None
        best_difference = None
        for tb, xb, yb in entries_b:
            difference = abs(ta - tb)
            if best_difference is None or difference < best_difference:
                best_difference = difference
                best = (tb, xb, yb)
        if best is None or best_difference > 100:
            continue
        tb, xb, yb = best
        distance = math.hypot(xa - xb, ya - yb)
        if distance > 2.0:
            rows.append([
                timestamp(ta), f"{xa:.2f}", f"{ya:.2f}",
                timestamp(tb), f"{xb:.2f}", f"{yb:.2f}", f"{distance:.2f}"
            ])
    return rows


def test_complete_submission():
    # Preserve the original source-file assertion.
    assert os.path.isfile(SOURCE), f"Missing C++ source file: {SOURCE}"

    # The requested compiled artifact must exist, be executable, and be a native binary.
    assert os.path.isfile(BINARY), f"Missing compiled program: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled program is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled program is not an ELF binary: {BINARY}"

    # Also ensure the submitted source really builds as C++.
    rebuilt = "/tmp/analyze_logs_rebuilt"
    compilation = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compilation.returncode == 0, f"C++ source does not compile: {compilation.stderr}"

    # Execute the submitted artifact on the original fixture and retain the original checks.
    write_logs(ORIGINAL_A, ORIGINAL_B)
    rows = execute_and_read(BINARY)
    assert len(rows) > 0, "The anomalies.csv file is empty."
    assert rows[0] == HEADER, f"Header mismatch. Expected {HEADER}, got {rows[0]}"
    expected_rows = [
        ["2023-10-25 14:22:02.500", "15.00", "5.00", "2023-10-25 14:22:02.550", "12.00", "2.00", "4.24"],
        ["2023-10-25 14:22:04.900", "0.00", "0.00", "2023-10-25 14:22:04.990", "3.00", "4.00", "5.00"]
    ]
    data_rows = rows[1:]
    assert len(data_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} anomaly rows, found {len(data_rows)}"
    )
    for i, (actual, expected) in enumerate(zip(data_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"

    # Generate an unpredictable second fixture and derive its answer independently.
    rng = random.SystemRandom()
    entries_a = [
        (12 * 3600000 + 1000, 10.00, 10.00),  # equal-time tie; first B must win
        (12 * 3600000 + 3000, 30.00, 30.00),  # nearest B is 101ms away: ignored
        (12 * 3600000 + 5000, 20.00, 20.00),  # distance exactly 2: not anomalous
    ]
    entries_b = [
        (12 * 3600000 + 900, 13.00, 10.00),
        (12 * 3600000 + 1100, 10.00, 10.00),
        (12 * 3600000 + 3101, 36.00, 30.00),
        (12 * 3600000 + 5050, 22.00, 20.00),
    ]

    for i in range(12):
        ta = 12 * 3600000 + 7000 + i * 1000
        xa = rng.randint(-5000, 5000) / 100.0
        ya = rng.randint(-5000, 5000) / 100.0
        entries_a.append((ta, xa, ya))

        near_offset = rng.randint(-40, 40)
        if i % 2 == 0:
            xb = xa + rng.randint(250, 500) / 100.0
            yb = ya + rng.randint(25, 175) / 100.0
        else:
            xb = xa + rng.randint(-75, 75) / 100.0
            yb = ya + rng.randint(-75, 75) / 100.0
        entries_b.append((ta + near_offset, xb, yb))

        far_offset = rng.choice([-1, 1]) * rng.randint(70, 100)
        entries_b.append((ta + far_offset, xa + 8.00, ya + 8.00))

    entries_b.sort(key=lambda entry: entry[0])
    hidden_a, hidden_b = make_log_text(entries_a, entries_b)
    expected_hidden = independently_expected(entries_a, entries_b)

    # Both the delivered executable and a fresh build of the submitted source must work.
    for executable in (BINARY, rebuilt):
        write_logs(hidden_a, hidden_b)
        actual = execute_and_read(executable)
        assert actual == expected_hidden, (
            f"{executable} produced incorrect output on generated logs. "
            f"Expected {expected_hidden}, got {actual}"
        )

    # Leave the requested output populated for the original supplied logs.
    write_logs(ORIGINAL_A, ORIGINAL_B)
    final_rows = execute_and_read(BINARY)
    assert final_rows == [HEADER] + expected_rows
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
