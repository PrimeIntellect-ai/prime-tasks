#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import json
import math
import os
import random
import re
import subprocess

import pytest

PROJECT = "/home/user/traffic_etl"
GPS_PATH = "/home/user/data/bus_gps.csv"
TARGETS_PATH = "/home/user/data/targets.csv"
OUTPUT_PATH = "/home/user/etl_output.sql"

ORIGINAL_GPS = """timestamp,bus_id,x,y
2023-10-01T10:00:05Z,bus_1,100.0,200.0
2023-10-01T10:00:15Z,bus_1,120.0,200.0
2023-10-01T10:00:25Z,bus_1,140.0,210.0
2023-10-01T10:00:45Z,bus_1,180.0,210.0
"""

ORIGINAL_TARGETS = """point_id,x,y
point_A,110.0,240.0
point_B,130.0,205.0
point_C,500.0,500.0
"""


def write_inputs(gps_text, targets_text):
    os.makedirs("/home/user/data", exist_ok=True)
    with open(GPS_PATH, "w") as f:
        f.write(gps_text)
    with open(TARGETS_PATH, "w") as f:
        f.write(targets_text)


def run_etl():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        "The Rust ETL program failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "The executed Rust program did not generate /home/user/etl_output.sql."


def read_nonempty_lines():
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_for(gps_rows, target_rows):
    parsed = []
    for timestamp, bus_id, x, y in gps_rows:
        when = dt.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
        parsed.append((int(when.timestamp()), bus_id, float(x), float(y)))
    parsed.sort(key=lambda row: row[0])

    minimum = parsed[0][0]
    maximum = parsed[-1][0]
    first_aligned = ((minimum + 9) // 10) * 10
    expected = []

    for current in range(first_aligned, maximum + 1, 10):
        exact = next((row for row in parsed if row[0] == current), None)
        if exact is not None:
            bus_id, x, y = exact[1], exact[2], exact[3]
        else:
            previous = max(row for row in parsed if row[0] < current)
            following = min(row for row in parsed if row[0] > current)
            ratio = (current - previous[0]) / (following[0] - previous[0])
            bus_id = previous[1]
            x = previous[2] + (following[2] - previous[2]) * ratio
            y = previous[3] + (following[3] - previous[3]) * ratio

        timestamp = dt.datetime.fromtimestamp(current, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        for point_id, target_x, target_y in target_rows:
            distance = math.hypot(x - float(target_x), y - float(target_y))
            if distance <= 50.0:
                expected.append(
                    "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) "
                    f"VALUES ('{timestamp}', '{bus_id}', '{point_id}', {distance:.2f});"
                )
    return expected


def assert_sql_matches(expected):
    lines = read_nonempty_lines()
    assert len(lines) == len(expected), f"Expected {len(expected)} SQL statements, but found {len(lines)}."

    timestamps = []
    for line in lines:
        match = re.search(r"\('([^']+)'", line)
        assert match is not None, f"Could not parse timestamp from line: {line}"
        timestamps.append(match.group(1))
    assert timestamps == sorted(timestamps), "The SQL statements are not ordered chronologically."

    assert set(lines) == set(expected), (
        "SQL generated from verifier-supplied CSV data was incorrect.\n"
        f"Missing: {sorted(set(expected) - set(lines))}\n"
        f"Extra: {sorted(set(lines) - set(expected))}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_rust_project():
    assert os.path.isdir(PROJECT), "/home/user/traffic_etl does not exist."
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), "/home/user/traffic_etl is not a Cargo project."

    rust_sources = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [name for name in dirs if name != "target"]
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, "No Rust source files were found in /home/user/traffic_etl."
    assert any(re.search(r"\bfn\s+main\s*\(", open(path, errors="ignore").read()) for path in rust_sources), \
        "The Cargo project does not contain a Rust main function."

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    assert any("bin" in target.get("kind", []) and target.get("src_path", "").endswith(".rs")
               for package in metadata.get("packages", []) for target in package.get("targets", [])), \
        "The Cargo project has no Rust binary target."

    rng = random.SystemRandom()
    token = f"{rng.randrange(10**8, 10**9)}"
    bus_id = f"verify_bus_{token}"
    tx = rng.randint(-200, 200)
    ty = rng.randint(-200, 200)
    day = rng.randint(2, 25)
    hour = rng.randint(1, 20)
    minute = rng.randint(1, 50)
    base = dt.datetime(2024, 6, day, hour, minute, 0, tzinfo=dt.timezone.utc)

    coords = [
        (tx, ty),
        (tx + rng.randint(8, 15), ty + rng.randint(1, 7)),
        (tx + rng.randint(22, 30), ty + rng.randint(10, 18)),
        (tx + rng.randint(35, 43), ty + rng.randint(15, 24)),
    ]
    offsets = [0, 7, 23, 40]
    gps_rows = []
    for offset, (x, y) in zip(offsets, coords):
        timestamp = (base + dt.timedelta(seconds=offset)).strftime("%Y-%m-%dT%H:%M:%SZ")
        gps_rows.append((timestamp, bus_id, x, y))

    target_rows = [
        (f"start_{token}", tx, ty),
        (f"finish_{token}", coords[-1][0], coords[-1][1]),
        (f"boundary_{token}", tx + 50, ty),
        (f"far_{token}", tx + 300, ty + 300),
    ]

    gps_text = "timestamp,bus_id,x,y\n" + "".join(
        f"{timestamp},{bid},{x},{y}\n" for timestamp, bid, x, y in gps_rows
    )
    targets_text = "point_id,x,y\n" + "".join(
        f"{point_id},{x},{y}\n" for point_id, x, y in target_rows
    )

    try:
        write_inputs(gps_text, targets_text)
        run_etl()
        assert_sql_matches(expected_for(gps_rows, target_rows))
    finally:
        write_inputs(ORIGINAL_GPS, ORIGINAL_TARGETS)

    # Re-run on the task's original inputs so the original output assertions remain intact.
    run_etl()
    yield


def test_etl_output_exists():
    assert os.path.isfile("/home/user/etl_output.sql"), "/home/user/etl_output.sql was not generated."


def test_etl_output_content():
    expected_statements = {
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:10Z', 'bus_1', 'point_A', 40.00);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:10Z', 'bus_1', 'point_B', 20.62);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:20Z', 'bus_1', 'point_A', 40.31);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:20Z', 'bus_1', 'point_B', 0.00);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:30Z', 'bus_1', 'point_A', 50.00);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:30Z', 'bus_1', 'point_B', 20.62);",
        "INSERT INTO bus_proximity (timestamp, bus_id, point_id, distance) VALUES ('2023-10-01T10:00:40Z', 'bus_1', 'point_B', 40.31);"
    }

    with open("/home/user/etl_output.sql", "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_statements), f"Expected {len(expected_statements)} SQL statements, but found {len(lines)}."

    # Verify chronological ordering
    timestamps = []
    for line in lines:
        match = re.search(r"\('([^']+)'", line)
        assert match is not None, f"Could not parse timestamp from line: {line}"
        timestamps.append(match.group(1))

    assert timestamps == sorted(timestamps), "The SQL statements are not ordered chronologically."

    # Verify exact contents
    actual_statements = set(lines)
    missing = expected_statements - actual_statements
    extra = actual_statements - expected_statements

    error_msg = []
    if missing:
        error_msg.append(f"Missing expected statements:\n" + "\n".join(missing))
    if extra:
        error_msg.append(f"Unexpected statements found:\n" + "\n".join(extra))

    assert not missing and not extra, "\n".join(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
