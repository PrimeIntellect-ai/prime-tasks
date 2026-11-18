#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/anomaly_detector")
SOURCE = PROJECT / "src/main.rs"
DATA = Path("/home/user/data.csv")


def test_slopes_file_exists():
    assert os.path.exists("/home/user/slopes.txt"), "The file /home/user/slopes.txt does not exist."


def test_slopes_content():
    with open("/home/user/slopes.txt", "r") as f:
        content = f.read()

    # Parse slope for ID 0
    m0 = re.search(r"^0:\s*([0-9\.]+)", content, re.MULTILINE)
    assert m0 is not None, "Could not find slope for ID 0 in slopes.txt. Ensure the format is '0: <slope>'"
    val0 = float(m0.group(1))
    assert abs(val0 - 2.0) < 1e-5, f"Expected slope for ID 0 to be 2.0, but got {val0}. The NaN records might not be properly skipped."

    # Parse slope for ID 1
    m1 = re.search(r"^1:\s*([0-9\.]+)", content, re.MULTILINE)
    assert m1 is not None, "Could not find slope for ID 1 in slopes.txt. Ensure the format is '1: <slope>'"
    val1 = float(m1.group(1))
    assert abs(val1 - 3.5) < 1e-5, f"Expected slope for ID 1 to be 3.5, but got {val1}."


def rust_binary_name():
    assert SOURCE.is_file(), "/home/user/anomaly_detector/src/main.rs is missing or is not a file"
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"

    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(PROJECT / "Cargo.toml")],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Invalid Rust project:\n{result.stdout}\n{result.stderr}"
    metadata = json.loads(result.stdout)
    source_path = SOURCE.resolve()
    targets = [
        target for package in metadata["packages"] for target in package["targets"]
        if "bin" in target.get("kind", []) and Path(target["src_path"]).resolve() == source_path
    ]
    assert targets, "The Cargo project does not build src/main.rs as a binary"
    return targets[0]["name"]


def test_rust_project_compiles():
    binary = rust_binary_name()
    result = subprocess.run(
        ["cargo", "build", "--manifest-path", str(PROJECT / "Cargo.toml"), "--bin", binary],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stdout}\n{result.stderr}"


def regression_slope(points):
    n = float(len(points))
    sum_x = sum(x for x, _ in points)
    sum_y = sum(y for _, y in points)
    sum_xy = sum(x * y for x, y in points)
    sum_xx = sum(x * x for x, _ in points)
    return (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)


def parse_program_output(output):
    number = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
    parsed = {}
    for line in output.splitlines():
        match = re.fullmatch(rf"\s*(-?\d+)\s*:\s*({number})\s*", line)
        assert match is not None, f"Unexpected program output line: {line!r}"
        sensor_id = int(match.group(1))
        assert sensor_id not in parsed, f"Duplicate output for sensor ID {sensor_id}"
        parsed[sensor_id] = float(match.group(2))
    return parsed


def test_program_skips_nan_rows_on_derived_inputs():
    binary = rust_binary_name()
    original_data = DATA.read_bytes()
    rng = secrets.SystemRandom()

    try:
        for _ in range(2):
            third_id = rng.randrange(2, 100)
            ids = [0, 1, third_id]
            rows = []
            points = {}

            for sensor_id in ids:
                slope = rng.choice([x / 10.0 for x in range(-90, 91) if x not in (0, 20, 35)])
                intercept = rng.randrange(-30, 31)
                timestamps = rng.sample(range(-20, 31), rng.randrange(4, 8))
                points[sensor_id] = []
                for timestamp in timestamps:
                    value = slope * timestamp + intercept
                    rows.append(f"{sensor_id},{timestamp},{repr(value)}")
                    points[sensor_id].append((float(timestamp), float(value)))

            # These rows would substantially corrupt ID 0 if NaN were cast to i32.
            for i in range(6):
                timestamp = rng.randrange(-25, 26)
                value = rng.choice([-1, 1]) * rng.randrange(10000, 50000)
                rows.append(f"NaN,{timestamp},{value}")

            rng.shuffle(rows)
            DATA.write_text("id,timestamp,value\n" + "\n".join(rows) + "\n")
            expected = {sensor_id: regression_slope(sensor_points) for sensor_id, sensor_points in points.items()}

            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml"), "--bin", binary],
                cwd=PROJECT,
                text=True,
                capture_output=True,
                timeout=120,
            )
            assert result.returncode == 0, f"Program failed on test data:\n{result.stdout}\n{result.stderr}"
            actual = parse_program_output(result.stdout)
            assert set(actual) == set(expected), f"Expected IDs {sorted(expected)}, got {sorted(actual)}"
            for sensor_id, expected_slope in expected.items():
                tolerance = 1e-7 * max(1.0, abs(expected_slope))
                assert abs(actual[sensor_id] - expected_slope) <= tolerance, (
                    f"Wrong slope for ID {sensor_id}: expected {expected_slope}, got {actual[sensor_id]}. "
                    "Rows whose ID is NaN must be skipped."
                )
    finally:
        DATA.write_bytes(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
