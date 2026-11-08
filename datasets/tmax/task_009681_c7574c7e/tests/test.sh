#!/bin/bash
set -e
mkdir -p /logs/verifier

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
export TRUSTED_SENSOR_DATA="$WORKDIR/sensor_data.csv"

cat << 'DATA_EOF' > "$TRUSTED_SENSOR_DATA"
timestamp,temperature,humidity
2023-10-01T00:15:00,20.0,50.0
2023-10-01T00:45:00,22.0,52.0
2023-10-01T02:30:00,24.0,56.0
2023-10-01T03:10:00,25.0,58.0
2023-10-01T03:50:00,27.0,60.0
2023-10-02T22:00:00,18.0,45.0
2023-10-02T23:55:00,19.0,46.0
DATA_EOF

cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
import os
import csv
from datetime import datetime, timedelta
import pytest


def parse_datetime(dt_str):
    return datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")


def format_hour(dt):
    return dt.strftime("%Y-%m-%dT%H")


def compute_expected_report():
    input_file = os.environ["TRUSTED_SENSOR_DATA"]
    if not os.path.exists(input_file):
        pytest.fail(f"Trusted input file {input_file} is missing.")

    buckets = {}

    with open(input_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt = parse_datetime(row["timestamp"])
            hour_key = format_hour(dt)
            temp = float(row["temperature"])
            hum = float(row["humidity"])

            if hour_key not in buckets:
                buckets[hour_key] = {"temp_sum": 0.0, "hum_sum": 0.0, "count": 0}

            buckets[hour_key]["temp_sum"] += temp
            buckets[hour_key]["hum_sum"] += hum
            buckets[hour_key]["count"] += 1

    if not buckets:
        return ""

    hourly_data = {}
    for k, v in buckets.items():
        hourly_data[k] = {
            "temp": v["temp_sum"] / v["count"],
            "hum": v["hum_sum"] / v["count"]
        }

    sorted_hours = sorted(hourly_data.keys())
    min_hour_dt = datetime.strptime(sorted_hours[0], "%Y-%m-%dT%H")
    max_hour_dt = datetime.strptime(sorted_hours[-1], "%Y-%m-%dT%H")

    full_range = []
    current_dt = min_hour_dt
    while current_dt <= max_hour_dt:
        full_range.append(format_hour(current_dt))
        current_dt += timedelta(hours=1)

    for i, h in enumerate(full_range):
        if h not in hourly_data:
            prev_idx = i - 1
            while prev_idx >= 0 and full_range[prev_idx] not in hourly_data:
                prev_idx -= 1

            next_idx = i + 1
            while next_idx < len(full_range) and full_range[next_idx] not in hourly_data:
                next_idx += 1

            prev_h = full_range[prev_idx]
            next_h = full_range[next_idx]
            prev_temp = hourly_data[prev_h]["temp"]
            prev_hum = hourly_data[prev_h]["hum"]
            next_temp = hourly_data[next_h]["temp"]
            next_hum = hourly_data[next_h]["hum"]
            fraction = (i - prev_idx) / (next_idx - prev_idx)

            hourly_data[h] = {
                "temp": prev_temp + (next_temp - prev_temp) * fraction,
                "hum": prev_hum + (next_hum - prev_hum) * fraction,
                "interpolated": True
            }

    daily_max = {}
    for h in full_range:
        day = h[:10]
        temp = hourly_data[h]["temp"]
        hum = hourly_data[h]["hum"]
        stress_index = (temp * 1.5) + (hum * 0.5)

        if day not in daily_max or stress_index > daily_max[day]:
            daily_max[day] = stress_index

    lines = []
    for day in sorted(daily_max.keys()):
        lines.append(f"Date: {day} - Max Stress Index: {daily_max[day]:.2f}")

    return "\n".join(lines)


def test_daily_report_exists_and_correct():
    source_file = "/home/user/sensor_data.csv"
    assert os.path.exists(source_file), f"Input file {source_file} is missing."
    assert os.path.isfile(source_file), f"Path {source_file} is not a file."

    report_file = "/home/user/daily_report.txt"
    assert os.path.exists(report_file), f"Report file {report_file} does not exist."
    assert os.path.isfile(report_file), f"Path {report_file} is not a file."

    expected_content = compute_expected_report()

    with open(report_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of {report_file} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Got:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
