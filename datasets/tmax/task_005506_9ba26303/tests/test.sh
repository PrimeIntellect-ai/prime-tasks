#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import resource
import secrets
import subprocess

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "config_events.csv")
LOG_PATH = os.path.join(HOME, "snapshots.log")
SOURCE_PATH = os.path.join(HOME, "resampler.rs")
MAKEFILE_PATH = os.path.join(HOME, "Makefile")
BINARY_PATH = os.path.join(HOME, "resampler")


def get_expected_snapshots(csv_path):
    events = []
    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 3:
                ts, key, val = parts
                events.append((int(ts), key, val))

    if not events:
        return []

    first_ts = events[0][0]
    last_ts = events[-1][0]
    t0 = (first_ts // 1000 + 1) * 1000
    t_end = (last_ts // 1000 + 1) * 1000

    snapshots = []
    state = {}
    event_idx = 0
    for t in range(t0, t_end + 1000, 1000):
        while event_idx < len(events) and events[event_idx][0] < t:
            _, key, val = events[event_idx]
            state[key] = val
            event_idx += 1
        if state:
            state_str = ",".join(f"{key}:{state[key]}" for key in sorted(state))
            snapshots.append(f"{t}|{state_str}")
    return snapshots


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_output(path, expected):
    actual = read_nonempty_lines(path)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} snapshots, but got {len(actual)}"
    )
    for i, (actual_line, expected_line) in enumerate(zip(actual, expected)):
        assert actual_line == expected_line, (
            f"Mismatch at line {i + 1}. Expected '{expected_line}', "
            f"got '{actual_line}'"
        )


def run_make(args):
    result = subprocess.run(
        args,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"{' '.join(args)} failed:\n{result.stdout}"


def test_complete_pipeline():
    # Preserve the original existence and submitted-log assertions.
    assert os.path.exists(SOURCE_PATH), "/home/user/resampler.rs is missing"
    assert os.path.exists(MAKEFILE_PATH), "/home/user/Makefile is missing"
    assert os.path.exists(LOG_PATH), "/home/user/snapshots.log is missing"
    assert os.path.exists(CSV_PATH), "/home/user/config_events.csv is missing"
    assert_output(LOG_PATH, get_expected_snapshots(CSV_PATH))

    assert os.path.isfile(SOURCE_PATH), "resampler.rs must be a regular file"
    assert os.path.isfile(MAKEFILE_PATH), "Makefile must be a regular file"

    # Require an actual buffered, line-oriented implementation.
    with open(SOURCE_PATH, "r") as f:
        source = f.read()
    assert re.search(r"\bBufReader\b", source), "resampler.rs must use BufReader"
    assert re.search(r"\.\s*(?:lines|read_line)\s*\(", source), (
        "resampler.rs must process input line-by-line"
    )

    expected_original = get_expected_snapshots(CSV_PATH)

    # The default Make target must build and execute the pipeline.
    for path in (BINARY_PATH, LOG_PATH):
        if os.path.lexists(path):
            os.remove(path)
    run_make(["make"])
    assert os.path.isfile(BINARY_PATH), "default make target did not build resampler"
    assert os.access(BINARY_PATH, os.X_OK), "resampler is not executable"
    assert os.path.isfile(LOG_PATH), "default make target did not create snapshots.log"
    assert_output(LOG_PATH, expected_original)

    # Explicitly exercise the required `make run` target from a clean artifact state.
    os.remove(BINARY_PATH)
    os.remove(LOG_PATH)
    run_make(["make", "run"])
    assert os.path.isfile(BINARY_PATH), "make run did not build resampler"
    assert os.access(BINARY_PATH, os.X_OK), "resampler is not executable"
    assert os.path.isfile(LOG_PATH), "make run did not create snapshots.log"
    assert_output(LOG_PATH, expected_original)

    # Exercise the compiled program on a fresh input whose expected answer is derived here.
    rng = random.Random(secrets.randbits(64))
    base = rng.randint(2000, 9000) * 1000
    suffix = secrets.token_hex(4)
    keys = [f"alpha_{suffix}", f"zeta_{suffix}", f"middle_{suffix}"]
    events = [
        (base + rng.randint(1, 300), keys[0], secrets.token_hex(3)),
        (base + 1000, keys[1], secrets.token_hex(3)),
        (base + 1001, keys[0], secrets.token_hex(3)),
        (base + 2500, keys[2], secrets.token_hex(3)),
        (base + 4000, keys[1], secrets.token_hex(3)),
    ]
    alternate_path = "/tmp/config_events_alternate.csv"
    with open(alternate_path, "w") as f:
        for ts, key, value in events:
            f.write(f"{ts},{key},{value}\n")

    result = subprocess.run(
        [BINARY_PATH, alternate_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"resampler failed on alternate input: {result.stderr}"
    actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    expected = get_expected_snapshots(alternate_path)
    assert actual == expected, f"Alternate-input mismatch:\nexpected={expected}\nactual={actual}"

    # A large input with tiny state must work under a memory cap, preventing whole-file loading.
    large_path = "/tmp/config_events_large.csv"
    value = "x" * 40
    line = f"1,k,{value}\n"
    with open(large_path, "w") as f:
        chunk = line * 10000
        for _ in range(160):
            f.write(chunk)

    def memory_limit():
        limit = 64 * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

    result = subprocess.run(
        [BINARY_PATH, large_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
        preexec_fn=memory_limit,
    )
    assert result.returncode == 0, (
        "resampler failed large streaming input under a 64 MiB memory limit: "
        + result.stderr
    )
    assert result.stdout.strip() == f"1000|k:{value}", (
        "Incorrect output for large streaming input"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
