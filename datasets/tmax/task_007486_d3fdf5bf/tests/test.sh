#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

HOME = "/home/user"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run(command):
    return subprocess.run(
        command,
        cwd=HOME,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_source_files_exist():
    """Verify that the required source files and Makefile exist."""
    required_files = [
        "/home/user/extractor.c",
        "/home/user/detector.c",
        "/home/user/Makefile"
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file is missing: {file_path}"


def test_parsed_csv_content():
    """Verify that parsed.csv exists and contains the correct extracted records."""
    file_path = "/home/user/parsed.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

    expected_lines = [
        "timestamp,sensor_id,value",
        "2023-10-01T12:00:02Z,S1,10.5",
        "2023-10-01T12:00:03Z,S2,100.0",
        "2023-10-01T12:00:04Z,S1,11.0",
        "2023-10-01T12:00:05Z,S1,45.0",
        "2023-10-01T12:00:06Z,S1,46.0",
        "2023-10-01T12:00:07Z,S2,101.0",
        "2023-10-01T12:00:08Z,S1,20.0"
    ]

    actual_lines = read_nonempty_lines(file_path)
    assert actual_lines == expected_lines, f"The content of {file_path} does not match the expected extracted data."


def test_anomalies_csv_content():
    """Verify that anomalies.csv exists and contains the correct anomaly records."""
    file_path = "/home/user/anomalies.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

    expected_lines = [
        "timestamp,sensor_id,value,diff",
        "2023-10-01T12:00:05Z,S1,45.0,34.0",
        "2023-10-01T12:00:08Z,S1,20.0,26.0"
    ]

    actual_lines = read_nonempty_lines(file_path)
    assert actual_lines == expected_lines, f"The content of {file_path} does not match the expected anomaly data."


def test_compiled_pipeline_on_unseen_inputs():
    with open(os.path.join(HOME, "extractor.c"), "r", errors="replace") as f:
        extractor_source = f.read()
    assert re.search(r"#\s*include\s*[<\"]regex\.h[>\"]", extractor_source), "extractor.c must include regex.h"
    assert "regcomp" in extractor_source and "regexec" in extractor_source, "extractor.c must use POSIX regular expressions"

    for name in ("extractor", "detector", "parsed.csv", "anomalies.csv"):
        path = os.path.join(HOME, name)
        if os.path.exists(path):
            os.remove(path)

    run(["make", "all"])
    for name in ("extractor", "detector"):
        path = os.path.join(HOME, name)
        assert os.path.isfile(path), f"make all did not build {name}"
        assert os.access(path, os.X_OK), f"{name} is not executable"
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{name} is not a compiled executable"

    rng = random.SystemRandom()
    base = rng.randint(10, 40)
    fixture = [
        "unrelated startup message",
        f"[2026-02-03T04:05:01Z] INFO - sensor_id: S1, val: {base}.0",
        f"[2026-02-03T04:05:02Z] INFO - sensor_id: S2, val: {base + 80}.0",
        f"[2026-02-03T04:05:03Z] WARN - sensor_id: S1, val: {base + 20}.0",
        f"[2026-02-03T04:05:04Z] ERROR - sensor_id: S1, val: {base + 99}.0 trailing-text",
        f"[2026-02-03T04:05:05Z] ERROR - sensor_id: S1, val: {base + 41}.0",
        "[2026-02-03T04:05:06Z] WARN - malformed sensor record",
        f"[2026-02-03T04:05:07Z] DEBUG - sensor_id: S2, val: {base + 81}.0",
        f"[2026-02-03T04:05:08Z] INFO - sensor_id: S1, val: {base + 10}.0",
    ]
    with open(os.path.join(HOME, "sensor_logs.txt"), "w") as f:
        f.write("\n".join(fixture) + "\n")

    run(["./extractor"])
    expected_parsed = [
        "timestamp,sensor_id,value",
        f"2026-02-03T04:05:01Z,S1,{base}.0",
        f"2026-02-03T04:05:02Z,S2,{base + 80}.0",
        f"2026-02-03T04:05:03Z,S1,{base + 20}.0",
        f"2026-02-03T04:05:05Z,S1,{base + 41}.0",
        f"2026-02-03T04:05:07Z,S2,{base + 81}.0",
        f"2026-02-03T04:05:08Z,S1,{base + 10}.0",
    ]
    assert read_nonempty_lines(os.path.join(HOME, "parsed.csv")) == expected_parsed

    run(["./detector"])
    expected_anomalies = [
        "timestamp,sensor_id,value,diff",
        f"2026-02-03T04:05:05Z,S1,{base + 41}.0,21.0",
        f"2026-02-03T04:05:08Z,S1,{base + 10}.0,31.0",
    ]
    assert read_nonempty_lines(os.path.join(HOME, "anomalies.csv")) == expected_anomalies

    second = rng.randint(60, 90)
    fixture2 = [
        f"[2026-07-08T09:10:01Z] INFO - sensor_id: S1, val: {second}.0",
        f"[2026-07-08T09:10:02Z] INFO - sensor_id: S1, val: {second - 21}.0",
        f"[2026-07-08T09:10:03Z] INFO - sensor_id: S2, val: {second + 50}.0",
        "not a valid log line",
        f"[2026-07-08T09:10:04Z] WARN - sensor_id: S1, val: {second - 41}.0",
        f"[2026-07-08T09:10:05Z] ERROR - sensor_id: S1, val: {second - 15}.0",
    ]
    with open(os.path.join(HOME, "sensor_logs.txt"), "w") as f:
        f.write("\n".join(fixture2) + "\n")

    for name in ("extractor", "detector", "parsed.csv", "anomalies.csv"):
        path = os.path.join(HOME, name)
        if os.path.exists(path):
            os.remove(path)

    run(["make", "run"])
    assert read_nonempty_lines(os.path.join(HOME, "parsed.csv")) == [
        "timestamp,sensor_id,value",
        f"2026-07-08T09:10:01Z,S1,{second}.0",
        f"2026-07-08T09:10:02Z,S1,{second - 21}.0",
        f"2026-07-08T09:10:03Z,S2,{second + 50}.0",
        f"2026-07-08T09:10:04Z,S1,{second - 41}.0",
        f"2026-07-08T09:10:05Z,S1,{second - 15}.0",
    ]
    assert read_nonempty_lines(os.path.join(HOME, "anomalies.csv")) == [
        "timestamp,sensor_id,value,diff",
        f"2026-07-08T09:10:02Z,S1,{second - 21}.0,21.0",
        f"2026-07-08T09:10:05Z,S1,{second - 15}.0,26.0",
    ]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
