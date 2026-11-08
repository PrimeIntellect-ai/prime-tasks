#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal


def run(cmd, timeout=15):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def test_detector_go_exists():
    path = "/home/user/detector.go"
    assert os.path.isfile(path), f"Missing required file: {path}"


def test_detector_classification():
    detector_path = "/home/user/detector.go"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isfile(detector_path), f"Missing detector program at {detector_path}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for f in clean_files:
        result = run(["go", "run", detector_path, f])
        if result.stdout.strip() != "CLEAN":
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = run(["go", "run", detector_path, f])
        if result.stdout.strip() != "EVIL":
            evil_failures.append(os.path.basename(f))

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/flagged. Offending files: {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(evil_failures)}")
    assert not clean_failures and not evil_failures, " | ".join(error_msg)


def test_detector_on_generated_unlabelled_inputs():
    detector = "/home/user/detector.go"
    build_dir = tempfile.mkdtemp(prefix="verify_" + secrets.token_hex(6) + "_")
    binary = os.path.join(build_dir, secrets.token_hex(8))
    built = run(["go", "build", "-o", binary, detector], timeout=30)
    assert built.returncode == 0, built.stderr

    seed = Decimal("1.045")
    cases = []

    # Randomized monotonic and clearly tampered logs prevent path/content lookup.
    for i in range(4):
        base = Decimal(1700000000 + secrets.randbelow(5000000)) + Decimal(secrets.randbelow(1000000)) / Decimal(1000000)
        cases.append((base, Decimal("-1.000000"), "CLEAN"))
        cases.append((base, Decimal("0.600000") + Decimal(secrets.randbelow(10000)) / Decimal(1000000), "EVIL"))

    # Exercise both sides of the seed-adjusted 500ms boundary. The expected
    # result is derived from the required rule rather than encoded in filenames.
    for _ in range(16):
        raw_us = 450000 + secrets.randbelow(60001)
        drift = Decimal(raw_us) / Decimal(1000000)
        if abs(drift * seed - Decimal("0.500")) < Decimal("0.002"):
            continue
        expected = "EVIL" if drift * seed > Decimal("0.500") else "CLEAN"
        base = Decimal(1700000000 + secrets.randbelow(5000000)) + Decimal(secrets.randbelow(1000000)) / Decimal(1000000)
        cases.append((base, drift, expected))

    for index, (base, backwards, expected) in enumerate(cases):
        first = base
        second = base + Decimal("1.000000")
        third = second + Decimal("1.000000") if backwards < 0 else second - backwards
        fourth = base + Decimal("3.000000")
        path = os.path.join(build_dir, secrets.token_hex(12) + ".dat")
        messages = [secrets.token_hex(7) for _ in range(4)]
        with open(path, "w", encoding="utf-8") as f:
            for timestamp, message in zip((first, second, third, fourth), messages):
                f.write(f"{timestamp:.6f} {message}\n")

        result = run([binary, path])
        assert result.returncode == 0, f"generated case {index} failed: {result.stderr}"
        assert result.stdout.strip() == expected, (
            f"generated case {index}: expected {expected}, got {result.stdout!r}; "
            f"raw backwards drift={backwards}"
        )


def test_timeline_is_fixed_and_sorts_precisely():
    timeline = "/home/user/timeline.go"
    assert os.path.isfile(timeline), f"Missing required file: {timeline}"

    # It must at least compile and terminate as a program.
    result = run(["go", "run", timeline], timeout=15)
    assert result.returncode == 0, result.stderr

    # Test the repaired sorting routine directly, including duplicate pivots
    # that caused the original recursion bug, and require a stable-width
    # timestamp representation rather than the original float32 field.
    work = tempfile.mkdtemp(prefix="timeline_test_")
    with open(timeline, "r", encoding="utf-8") as src, open(os.path.join(work, "timeline.go"), "w", encoding="utf-8") as dst:
        dst.write(src.read())
    with open(os.path.join(work, "timeline_test.go"), "w", encoding="utf-8") as f:
        f.write(r'''package main

import "testing"

var _ float64 = LogEntry{}.Timestamp

func TestSortLogsTerminatesAndOrders(t *testing.T) {
    logs := []LogEntry{
        {Timestamp: 1700000000.000009, Message: "late"},
        {Timestamp: 1700000000.000001, Message: "early"},
        {Timestamp: 1700000000.000005, Message: "middle"},
        {Timestamp: 1700000000.000005, Message: "duplicate"},
    }
    sortLogs(logs)
    for i := 1; i < len(logs); i++ {
        if logs[i-1].Timestamp > logs[i].Timestamp {
            t.Fatalf("timestamps not sorted at %d: %.9f > %.9f", i, logs[i-1].Timestamp, logs[i].Timestamp)
        }
    }
    if logs[0].Message != "early" || logs[len(logs)-1].Message != "late" {
        t.Fatalf("precision was lost or entries were not sorted: %#v", logs)
    }
}
''')
    result = run(["go", "test", "-timeout=5s", work], timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
