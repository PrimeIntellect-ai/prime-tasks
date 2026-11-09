#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

SOURCE = "/home/user/process.c"
LOG = "/home/user/data/etl_job.log"
REPORT = "/home/user/report.csv"
BINARY = "/tmp/process_submission"

CANONICAL_LOG = (
    b"1000,1,0,10.0,Started\n"
    b"1001,1,1,15.0,Retry 1\n"
    b"1002,1,2,20.0,Retry 2\n"
    b"1003,1,3,25.0,Retry 3\n"
    b"1004,2,0,5.0,OK\n"
    b"1005,3,0,100.0,Fail\xff\n"
    b"1006,3,1,110.0,Retry 1\n"
    b"1007,4,0,10.0,OK\n"
    b"1008,4,1,10.0,Retry 1\n"
    b"1009,4,2,10.0,Retry 2\n"
    b"1010,4,3,10.0,Retry 3\n"
    b"1011,4,4,10.0,Retry 4\n"
)


def write_log(data):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "wb") as f:
        f.write(data)


def run_submission(data):
    write_log(data)
    try:
        os.remove(REPORT)
    except FileNotFoundError:
        pass
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=15)
    assert os.path.isfile(REPORT), "The program did not create /home/user/report.csv."
    with open(REPORT, "r", encoding="ascii") as f:
        return [line.strip() for line in f if line.strip()]


# Compile the submitted artifact and regenerate the canonical report before
# retaining the original report assertions below.
assert os.path.isfile(SOURCE), "The C source file /home/user/process.c does not exist."
subprocess.run(
    ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
run_submission(CANONICAL_LOG)


def test_process_c_exists():
    assert os.path.isfile("/home/user/process.c"), "The C source file /home/user/process.c does not exist."


def test_report_csv_exists():
    assert os.path.isfile("/home/user/report.csv"), "The output file /home/user/report.csv does not exist."


def test_report_csv_content():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"The output file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1,3,20.00",
        "2,0,5.00",
        "3,1,110.00",
        "4,4,10.00"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report.csv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def make_random_case():
    rng = random.Random(secrets.randbits(128))
    base = 10000 + secrets.randbelow(500000)
    session_ids = [base + offset for offset in (17, 2, 81, 9, 44, 103, 25, 68, 5, 130, 36)]
    invalid_only_sid = base + 999

    events = []
    # Guarantee at least one valid event for every expected session.
    for index, sid in enumerate(session_ids):
        events.append((sid, index % 3, 20 + index, True, index))

    # A sizeable, unpredictably generated stream exercises retry counting and
    # the last-three-event window in file order.
    for index in range(4000):
        sid = rng.choice(session_ids)
        retry = rng.randrange(0, 5)
        latency = rng.randrange(1, 1500)
        events.append((sid, retry, latency, True, 100 + index))

        # These records would change both counts and rolling averages if their
        # non-ASCII messages were not filtered.
        if index % 67 == 0:
            events.append((sid, 9, 9000 + index, False, 50000 + index))

    for index in range(8):
        events.append((invalid_only_sid, 7, 7000 + index, False, 90000 + index))

    rng.shuffle(events)
    state = {}
    records = []
    timestamp = 2000000

    for sid, retry, latency, valid, marker in events:
        if valid:
            message = f"event {marker}, additional message text".encode("ascii")
            entry = state.setdefault(sid, {"retries": 0, "last": []})
            if retry > 0:
                entry["retries"] += 1
            entry["last"].append(float(latency))
            entry["last"] = entry["last"][-3:]
        else:
            message = b"invalid message \xff ignored"

        records.append(
            f"{timestamp},{sid},{retry},{latency}.0,".encode("ascii")
            + message
            + b"\n"
        )
        timestamp += 1

    expected = []
    for sid in sorted(state):
        entry = state[sid]
        average = sum(entry["last"]) / len(entry["last"])
        expected.append(f"{sid},{entry['retries']},{average:.2f}")

    return b"".join(records), expected


def test_compiled_program_on_unpredictable_streams():
    try:
        for _ in range(2):
            data, expected = make_random_case()
            actual = run_submission(data)
            assert actual == expected, (
                "Program output was incorrect for a generated log stream.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
    finally:
        # Leave the task's original input and expected report in place.
        run_submission(CANONICAL_LOG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
