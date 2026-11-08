#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
from collections import defaultdict

import pytest

BASE = "/home/user/data_pipeline"
RAW = os.path.join(BASE, "raw_sensors.csv")
AGG = os.path.join(BASE, "aggregated.csv")
REPORT = os.path.join(BASE, "reproducibility_report.txt")


def run(cmd, cwd=BASE):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=True,
    )


def expected_from_raw(path):
    stats = defaultdict(lambda: {"count": 0, "min": float("inf"), "max": float("-inf"), "sum": 0.0})
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) != 3:
                continue
            sid = int(parts[1])
            value = float(parts[2])
            stats[sid]["count"] += 1
            stats[sid]["min"] = min(stats[sid]["min"], value)
            stats[sid]["max"] = max(stats[sid]["max"], value)
            stats[sid]["sum"] += value
    return stats


def assert_aggregate_matches(raw_path, agg_path):
    stats = expected_from_raw(raw_path)
    with open(agg_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert lines and lines[0] == "sensor_id,count,min,max,avg"
    assert len(lines) - 1 == len(stats)

    seen_ids = []
    decimal_pattern = re.compile(r"^-?\d+\.\d{2}$")
    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) == 5, f"Row does not have 5 columns: {line}"
        sid = int(parts[0])
        seen_ids.append(sid)
        assert sid in stats, f"Unexpected sensor_id: {sid}"
        assert re.fullmatch(r"\d+", parts[1]), f"Invalid count formatting: {parts[1]}"
        for value in parts[2:]:
            assert decimal_pattern.fullmatch(value), f"Double is not formatted to exactly two decimals: {value}"

        expected = stats[sid]
        assert int(parts[1]) == expected["count"]
        assert abs(float(parts[2]) - round(expected["min"], 2)) < 0.015
        assert abs(float(parts[3]) - round(expected["max"], 2)) < 0.015
        assert abs(float(parts[4]) - round(expected["sum"] / expected["count"], 2)) < 0.015

    assert seen_ids == sorted(stats), "Rows are not sorted by sensor_id or contain duplicate/missing IDs"


def assert_report():
    with open(AGG, "rb") as f:
        true_md5 = hashlib.md5(f.read()).hexdigest()
    with open(REPORT, "r") as f:
        lines = f.read().strip().split('\n')
    assert lines == [
        f"Run 1: {true_md5}",
        f"Run 2: {true_md5}",
        f"Run 3: {true_md5}",
        "Reproducible: YES",
    ]


@pytest.fixture(scope="session", autouse=True)
def exercise_c_program_and_makefile():
    for name in ["aggregate.c", "Makefile", "aggregated.csv", "reproducibility_report.txt"]:
        assert os.path.exists(os.path.join(BASE, name)), f"File {name} is missing"

    # Ensure every required Makefile target is defined and can be resolved.
    for target in ["build", "run", "test", "clean", "all"]:
        run(["make", "-n", target])

    dry_build = run(["make", "-n", "-B", "build"]).stdout
    assert re.search(r"(^|[/\s])gcc(?:\s|$)", dry_build), "build target must use gcc"
    assert re.search(r"(^|\s)-O3(?:\s|$)", dry_build), "build target must use -O3"
    assert "aggregate.c" in dry_build and "aggregate" in dry_build

    # Independently compile aggregate.c, so placeholder/non-C source cannot pass.
    verifier_binary = "/tmp/verifier_aggregate"
    subprocess.run(
        ["gcc", "-O3", os.path.join(BASE, "aggregate.c"), "-o", verifier_binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=True,
    )

    original_raw = open(RAW, "rb").read()
    hidden_raw = (
        b"1700000000,5,99.75\n"
        b"1700000010,1,10.25\n"
        b"1700000020,3,42.50\n"
        b"1700000030,1,20.75\n"
        b"1700000040,5,10.25\n"
        b"1700000050,3,57.50\n"
        b"1700000060,1,14.50\n"
    )

    try:
        with open(RAW, "wb") as f:
            f.write(hidden_raw)
        if os.path.exists(AGG):
            os.remove(AGG)
        run([verifier_binary])
        assert os.path.exists(AGG), "Compiled aggregate.c did not create aggregated.csv"
        assert_aggregate_matches(RAW, AGG)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)

    # Exercise clean and build, and ensure build produces a real executable.
    run(["make", "clean"])
    for name in ["aggregate", "aggregated.csv", "reproducibility_report.txt"]:
        assert not os.path.exists(os.path.join(BASE, name)), f"clean did not remove {name}"

    run(["make", "build"])
    built_binary = os.path.join(BASE, "aggregate")
    assert os.path.isfile(built_binary) and os.access(built_binary, os.X_OK)
    with open(built_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "build did not produce a compiled executable"

    # Exercise the Makefile-built binary on verifier-controlled input.
    try:
        with open(RAW, "wb") as f:
            f.write(hidden_raw)
        if os.path.exists(AGG):
            os.remove(AGG)
        run([built_binary])
        assert_aggregate_matches(RAW, AGG)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)

    if os.path.exists(AGG):
        os.remove(AGG)
    run(["make", "run"])
    assert os.path.exists(AGG), "run target did not produce aggregated.csv"
    assert_aggregate_matches(RAW, AGG)

    if os.path.exists(REPORT):
        os.remove(REPORT)
    run(["make", "test"])
    assert os.path.exists(REPORT), "test target did not produce the report"
    assert_report()

    # Finally require all to recreate the complete pipeline from a clean state.
    run(["make", "clean"])
    run(["make", "all"])
    yield


def test_files_exist():
    expected_files = ["aggregate.c", "Makefile", "aggregated.csv", "reproducibility_report.txt"]
    for filename in expected_files:
        path = os.path.join(BASE, filename)
        assert os.path.exists(path), f"File {path} is missing."


def test_aggregated_csv_content():
    assert os.path.exists(RAW), "raw_sensors.csv is missing."
    assert os.path.exists(AGG), "aggregated.csv is missing."
    assert_aggregate_matches(RAW, AGG)


def test_reproducibility_report():
    assert os.path.exists(AGG), "aggregated.csv is missing."
    assert os.path.exists(REPORT), "reproducibility_report.txt is missing."
    assert_report()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
