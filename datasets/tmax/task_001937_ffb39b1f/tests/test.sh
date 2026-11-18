#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from datetime import datetime, timedelta

SOURCE = "/home/user/process.c"
EXECUTABLE = "/home/user/process"
INPUT = "/home/user/raw_events.csv"
OUTPUT = "/home/user/hourly_status.csv"
BASE = datetime(2023, 10, 1, 0, 0, 0)


def read_nonempty_lines(path):
    with open(path, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.split("\n") if line.strip()]


def expected_for(events):
    # Remove adjacent exact duplicates independently of the submitted program.
    deduplicated = []
    for event in events:
        if not deduplicated or event != deduplicated[-1]:
            deduplicated.append(event)

    result = []
    index = 0
    state = "OFFLINE"
    for hour in range(24):
        grid_time = BASE + timedelta(hours=hour)
        grid_offset = hour * 3600
        while index < len(deduplicated) and deduplicated[index][0] <= grid_offset:
            state = deduplicated[index][1]
            index += 1
        result.append(f"{grid_time:%Y-%m-%d %H:%M:%S},{state}")
    return result


def write_events(events):
    with open(INPUT, "w") as f:
        for offset, state in events:
            timestamp = BASE + timedelta(seconds=offset)
            f.write(f"{timestamp:%Y-%m-%d %H:%M:%S},{state}\n")


def run_case(executable, events):
    write_events(events)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    completed = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(OUTPUT), f"{executable} did not create {OUTPUT}."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a regular file."

    actual = read_nonempty_lines(OUTPUT)
    expected = expected_for(events)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines, but got {len(actual)} from {executable}."
    )
    for i, (actual_line, expected_line) in enumerate(zip(actual, expected)):
        assert actual_line == expected_line, (
            f"Mismatch from {executable} at line {i + 1}:\n"
            f"Expected: {expected_line}\nActual:   {actual_line}"
        )


def make_random_case(rng, case_number):
    states = ["BOOTING", "READY", "DEGRADED", "PAUSED", "RECOVERING", "ONLINE"]
    earliest = rng.randint(1 + case_number * 1800, 5 * 3600 + case_number * 900)
    offsets = {earliest, rng.randint(6 * 3600, 10 * 3600)}
    offsets.add(rng.randint(11 * 3600, 16 * 3600))
    offsets.add(rng.randint(17 * 3600, 22 * 3600))
    offsets.add(rng.choice(range(1, 23)) * 3600)  # Exercise an exact grid boundary.
    while len(offsets) < 14:
        offsets.add(rng.randint(1, 86399))

    events = []
    previous_state = None
    for offset in sorted(offsets):
        choices = [state for state in states if state != previous_state]
        state = rng.choice(choices)
        event = (offset, state)
        events.append(event)
        if rng.randrange(2) == 0:
            events.append(event)
            if rng.randrange(3) == 0:
                events.append(event)
        previous_state = state
    return events


def test_submission():
    # Preserve the original artifact assertions.
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a regular file."

    expected_lines = [
        "2023-10-01 00:00:00,OFFLINE",
        "2023-10-01 01:00:00,OFFLINE",
        "2023-10-01 02:00:00,OFFLINE",
        "2023-10-01 03:00:00,OFFLINE",
        "2023-10-01 04:00:00,MAINTENANCE",
        "2023-10-01 05:00:00,MAINTENANCE",
        "2023-10-01 06:00:00,MAINTENANCE",
        "2023-10-01 07:00:00,MAINTENANCE",
        "2023-10-01 08:00:00,ACTIVE",
        "2023-10-01 09:00:00,WARNING",
        "2023-10-01 10:00:00,WARNING",
        "2023-10-01 11:00:00,WARNING",
        "2023-10-01 12:00:00,ACTIVE",
        "2023-10-01 13:00:00,ACTIVE",
        "2023-10-01 14:00:00,ACTIVE",
        "2023-10-01 15:00:00,ACTIVE",
        "2023-10-01 16:00:00,ERROR",
        "2023-10-01 17:00:00,ERROR",
        "2023-10-01 18:00:00,ERROR",
        "2023-10-01 19:00:00,ERROR",
        "2023-10-01 20:00:00,MAINTENANCE",
        "2023-10-01 21:00:00,MAINTENANCE",
        "2023-10-01 22:00:00,MAINTENANCE",
        "2023-10-01 23:00:00,MAINTENANCE",
    ]
    actual_lines = read_nonempty_lines(OUTPUT)
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}:\nExpected: {expected}\nActual:   {actual}"
        )

    # Compile the submitted C source independently so its behavior is verified too.
    rebuilt = "/tmp/process_from_submitted_source"
    compilation = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compilation.returncode == 0, (
        f"Submitted C source did not compile.\nstdout:\n{compilation.stdout}\n"
        f"stderr:\n{compilation.stderr}"
    )

    rng = secrets.SystemRandom()
    cases = [
        [
            (37, "BOOTING"),
            (37, "BOOTING"),
            (3599, "READY"),
            (3600, "ONLINE"),
            (3600, "ONLINE"),
            (8 * 3600 + 1, "DEGRADED"),
            (15 * 3600, "RECOVERING"),
            (15 * 3600, "RECOVERING"),
            (23 * 3600, "PAUSED"),
        ],
        make_random_case(rng, 0),
        make_random_case(rng, 1),
        make_random_case(rng, 2),
    ]

    # Exercise both the delivered executable and an executable rebuilt from process.c.
    for executable in (EXECUTABLE, rebuilt):
        for events in cases:
            run_case(executable, events)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
