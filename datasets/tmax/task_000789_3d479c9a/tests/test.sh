#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

TRUSTED_TEMPLATE = """# Daily Sensor Report

* Minimum Temperature: {{MIN}}
* Maximum Temperature: {{MAX}}
* Average Temperature: {{MEAN}}

End of report.
"""

def test_daily_report_generated_correctly():
    data_file = "/home/user/sensor_data.csv"
    template_file = "/home/user/report_template.md"
    report_file = "/home/user/daily_report.md"

    assert os.path.isfile(data_file), f"Missing data file: {data_file}"
    assert os.path.isfile(template_file), f"Missing template file: {template_file}"
    assert os.path.isfile(report_file), f"Missing report file: {report_file}"

    # Ensure expected output is based on the supplied template, not an
    # agent-modified replacement.
    with open(template_file, "r") as f:
        template_content = f.read()
    assert template_content == TRUSTED_TEMPLATE, (
        f"Template file was modified: {template_file}"
    )

    # 1. Parse valid records
    valid_records = []
    with open(data_file, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) != 3:
                continue
            ts_str, _, temp_str = parts
            try:
                ts = int(ts_str)
                temp = float(temp_str)
            except ValueError:
                continue

            if -20.0 <= temp <= 60.0:
                valid_records.append((ts, temp))

    # Sort by timestamp just in case
    valid_records.sort(key=lambda x: x[0])

    # 2. Resample
    start_ts = 1710000000
    end_ts = 1710086400
    step = 3600
    target_timestamps = list(range(start_ts, end_ts + step, step))
    assert len(target_timestamps) == 25, "Expected exactly 25 target timestamps."

    resampled_temps = []
    for t in target_timestamps:
        # Find most recent valid record <= t
        closest_temp = 0.0
        for r_ts, r_temp in valid_records:
            if r_ts <= t:
                closest_temp = r_temp
            else:
                break
        resampled_temps.append(closest_temp)

    # 3. Compute stats
    min_temp = min(resampled_temps)
    max_temp = max(resampled_temps)
    mean_temp = sum(resampled_temps) / len(resampled_temps)

    min_str = f"{min_temp:.1f}"
    max_str = f"{max_temp:.1f}"
    mean_str = f"{mean_temp:.2f}"

    # 4. Generate expected content from the verified original template
    expected_content = template_content.replace("{{MIN}}", min_str)
    expected_content = expected_content.replace("{{MAX}}", max_str)
    expected_content = expected_content.replace("{{MEAN}}", mean_str)

    # 5. Verify report
    with open(report_file, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {report_file} does not match expected output.\n"
        f"Expected:\n{expected_content.strip()}\n\n"
        f"Actual:\n{actual_content.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
