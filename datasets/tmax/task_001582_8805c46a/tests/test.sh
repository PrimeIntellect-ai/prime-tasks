#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
from datetime import datetime, timezone

SCRIPT_PATH = "/home/user/clean_data.sh"
OUTPUT_PATH = "/home/user/aligned_data.tsv"
SENSOR_A_PATH = "/home/user/sensor_A.log"
SENSOR_B_PATH = "/home/user/sensor_B.csv"


def compute_expected(sensor_a_path=SENSOR_A_PATH, sensor_b_path=SENSOR_B_PATH):
    sensor_b_data = []
    with open(sensor_b_path, "r") as f:
        lines = f.read().strip().split("\n")
        for line in lines[1:]:
            if not line.strip():
                continue
            epoch_str, temp_str = line.split(",")
            sensor_b_data.append((int(epoch_str), temp_str.strip()))

    expected_lines = []
    log_pattern = re.compile(r"\[(.*?) UTC\] POS: lat=(.*?), lon=(.*)")
    with open(sensor_a_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = log_pattern.match(line)
            assert match, f"Failed to parse sensor_A.log line: {line}"

            dt_str, lat_str, lon_str = match.groups()
            dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            log_epoch = int(dt.timestamp())
            lat = float(lat_str)
            lon = float(lon_str)
            distance = round(math.sqrt(lat**2 + lon**2), 2)

            closest_b = None
            min_diff = float("inf")
            for b_epoch, b_temp in sensor_b_data:
                diff = abs(b_epoch - log_epoch)
                if diff < min_diff:
                    min_diff = diff
                    closest_b = (b_epoch, b_temp)

            expected_lines.append(
                f"{log_epoch}\t{closest_b[0]}\t{distance:.2f}\t{closest_b[1]}"
            )

    return "\n".join(expected_lines)


def run_script():
    env = os.environ.copy()
    env["TZ"] = "UTC"
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_aligned_data_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    assert os.path.isfile(SENSOR_A_PATH), f"Input file not found at {SENSOR_A_PATH}"
    assert os.path.isfile(SENSOR_B_PATH), f"Input file not found at {SENSOR_B_PATH}"

    expected_output = compute_expected()
    with open(OUTPUT_PATH, "r") as f:
        student_output = f.read().strip()

    assert student_output == expected_output, (
        f"Contents of {OUTPUT_PATH} do not match expected output.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{student_output}"
    )


def test_script_regenerates_original_output():
    expected_output = compute_expected()
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_script()
    with open(OUTPUT_PATH, "r") as f:
        student_output = f.read().strip()
    assert student_output == expected_output, (
        f"Script did not regenerate the expected output.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{student_output}"
    )


def test_script_processes_altered_inputs_and_ties():
    paths = [SENSOR_A_PATH, SENSOR_B_PATH, OUTPUT_PATH]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        rng = random.SystemRandom()
        base = rng.randrange(1704067200, 1735680000)
        base -= base % 10

        a_lines = []
        b_rows = []
        for i in range(6):
            epoch = base + i * 1000
            dt_text = datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
            lat = rng.uniform(-80.0, 80.0)
            lon = rng.uniform(-160.0, 160.0)
            a_lines.append(
                f"[{dt_text} UTC] POS: lat={lat:.5f}, lon={lon:.5f}"
            )

            if i % 2 == 0:
                delta = rng.randrange(11, 70)
                first_offset = delta if i % 4 == 0 else -delta
                second_offset = -first_offset
                b_rows.append((epoch + first_offset, f"{10 + i + rng.random():.3f}"))
                b_rows.append((epoch + second_offset, f"{30 + i + rng.random():.3f}"))
            else:
                near_offset = rng.randrange(15, 55)
                far_offset = -rng.randrange(90, 150)
                b_rows.append((epoch + far_offset, f"{40 + i + rng.random():.3f}"))
                b_rows.append((epoch + near_offset, f"{20 + i + rng.random():.3f}"))

        with open(SENSOR_A_PATH, "w") as f:
            f.write("\n".join(a_lines) + "\n")
        with open(SENSOR_B_PATH, "w") as f:
            f.write("epoch,temp\n")
            for epoch, temp in b_rows:
                f.write(f"{epoch},{temp}\n")

        expected_output = compute_expected()
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_script()
        with open(OUTPUT_PATH, "r") as f:
            student_output = f.read().strip()

        assert student_output == expected_output, (
            "Script failed on altered inputs, including closest-timestamp ties.\n"
            f"Expected:\n{expected_output}\n\nGot:\n{student_output}"
        )
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
