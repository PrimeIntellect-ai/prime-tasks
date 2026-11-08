#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def test_venv_exists():
    python_path = "/home/user/sensor_env/bin/python"
    assert os.path.isfile(python_path), f"Virtual environment python not found at {python_path}"


def test_processed_sensors_dir():
    target_dir = "/home/user/processed_sensors"
    assert os.path.isdir(target_dir), f"Directory {target_dir} does not exist"


def test_partitions_exist():
    for sensor in ["A", "B", "C"]:
        part_dir = f"/home/user/processed_sensors/sensor_id={sensor}"
        assert os.path.isdir(part_dir), f"Partition directory {part_dir} does not exist"
        files = os.listdir(part_dir)
        assert any(f.endswith('.parquet') for f in files), f"No .parquet files found in {part_dir}"


def test_data_correctness():
    python_path = "/home/user/sensor_env/bin/python"

    script = r'''
import csv
import io
import random
import sys

try:
    import pandas as pd
    from pandas.testing import assert_frame_equal
except ImportError:
    print("pandas is not installed in the virtual environment")
    sys.exit(1)

# Reconstruct the deterministic source generated during image setup so replacing
# the writable raw CSV cannot change the verifier's expected answer.
buffer = io.StringIO(newline="")
writer = csv.writer(buffer)
writer.writerow(["timestamp", "sensor_id", "temperature", "humidity"])
random.seed(42)
for i in range(1000):
    if i % 50 == 0:
        writer.writerow([f"2023-10-01T{i:04d}", "A", "", "45.0"])
        continue

    sensor = random.choice(["A", "B", "C"])
    temp = random.gauss(20, 5)
    hum = random.gauss(50, 10)
    if i == 10:
        temp = 1000.0
    if i == 20:
        temp = -1000.0
    if i == 30:
        hum = 1000.0
    if i == 40:
        hum = -1000.0
    writer.writerow([
        f"2023-10-01T{i:04d}", sensor, round(temp, 2), round(hum, 2)
    ])

trusted_raw = buffer.getvalue().encode()
try:
    with open("/home/user/raw_sensor_data.csv", "rb") as f:
        submitted_raw = f.read()
except OSError as e:
    print(f"Error reading raw CSV: {e}")
    sys.exit(1)

if submitted_raw != trusted_raw:
    print("The raw sensor CSV was modified")
    sys.exit(1)

try:
    source = pd.read_csv("/home/user/raw_sensor_data.csv")
except Exception as e:
    print(f"Error reading raw CSV with pandas: {e}")
    sys.exit(1)

expected = source.dropna(axis=0, how="any").copy()
temp_low = expected["temperature"].quantile(0.01)
temp_high = expected["temperature"].quantile(0.99)
hum_low = expected["humidity"].quantile(0.01)
hum_high = expected["humidity"].quantile(0.99)
expected["temperature"] = expected["temperature"].clip(temp_low, temp_high)
expected["humidity"] = expected["humidity"].clip(hum_low, hum_high)

try:
    df = pd.read_parquet("/home/user/processed_sensors")
except Exception as e:
    print(f"Error reading parquet dataset: {e}")
    sys.exit(1)

# Preserve the original checks.
if df.isna().sum().sum() != 0:
    print("There are missing values in the dataset")
    sys.exit(1)
if len(df) != 980:
    print(f"Expected 980 rows, got {len(df)}")
    sys.exit(1)
if df['temperature'].max() >= 50:
    print("Temperature outliers were not capped")
    sys.exit(1)
if df['temperature'].min() <= -50:
    print("Temperature outliers were not floored")
    sys.exit(1)
if df['humidity'].max() >= 150:
    print("Humidity outliers were not capped")
    sys.exit(1)
if df['humidity'].min() <= -50:
    print("Humidity outliers were not floored")
    sys.exit(1)

required_columns = ["timestamp", "sensor_id", "temperature", "humidity"]
if set(df.columns) != set(required_columns):
    print(f"Unexpected columns: expected {required_columns}, got {list(df.columns)}")
    sys.exit(1)

# Normalize representation differences introduced by partition discovery, then
# compare every output row against the source cleaned with freshly computed
# percentiles. Timestamps are unique, so sorting removes irrelevant file order.
actual = df[required_columns].copy()
expected = expected[required_columns].copy()
for frame in (actual, expected):
    frame["timestamp"] = frame["timestamp"].astype("string")
    frame["sensor_id"] = frame["sensor_id"].astype("string")
    frame["temperature"] = pd.to_numeric(frame["temperature"])
    frame["humidity"] = pd.to_numeric(frame["humidity"])

actual = actual.sort_values("timestamp").reset_index(drop=True)
expected = expected.sort_values("timestamp").reset_index(drop=True)
try:
    assert_frame_equal(
        actual,
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )
except AssertionError as e:
    print(f"Parquet data does not exactly match the cleaned source data: {e}")
    sys.exit(1)

print("OK")
sys.exit(0)
'''
    result = subprocess.run(
        [python_path, "-c", script],
        capture_output=True,
        text=True,
    )

    error_msg = result.stdout.strip() if result.stdout.strip() else result.stderr.strip()
    assert result.returncode == 0, f"Data validation failed: {error_msg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
