#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def test_final_report_correctness():
    config_file = '/home/user/config.env'
    data_file = '/home/user/data/particles.csv'
    report_file = '/home/user/final_report.md'
    template_file = '/home/user/report.tmpl'

    assert os.path.isfile(config_file), f"Config file {config_file} is missing."
    assert os.path.isfile(data_file), f"Data file {data_file} is missing."
    assert os.path.isfile(report_file), f"Final report {report_file} was not generated."
    assert os.path.isfile(template_file), f"Template file {template_file} is missing."

    multiplier = None
    threshold = None

    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('MULTIPLIER='):
                multiplier = float(line.split('=', 1)[1])
            elif line.startswith('THRESHOLD='):
                threshold_str = line.split('=', 1)[1]
                threshold = float(threshold_str)

    assert multiplier is not None, "MULTIPLIER not found in config.env"
    assert threshold is not None, "THRESHOLD not found in config.env"

    count = 0
    total_sum = 0.0

    with open(data_file, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 5:
                continue
            x, y, z, mass = float(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
            energy = mass * multiplier * math.sqrt(x**2 + y**2 + z**2)
            if energy > threshold:
                count += 1
                total_sum += energy

    expected_sum_str = f"{total_sum:.2f}"

    with open(template_file, 'r') as f:
        template_content = f.read()

    canonical_template = (
        "# Particle Energy Report\n"
        "Threshold Configured: {{THRESHOLD}}\n"
        "Total High Energy Particles: {{COUNT}}\n"
        "Total High Energy Sum: {{SUM}}\n"
    )
    assert template_content == canonical_template, "The supplied report template was modified."

    expected_report = template_content.replace('{{THRESHOLD}}', threshold_str)
    expected_report = expected_report.replace('{{COUNT}}', str(count))
    expected_report = expected_report.replace('{{SUM}}', expected_sum_str)

    with open(report_file, 'r') as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), (
        f"Final report content does not match expected output.\n"
        f"Expected:\n{expected_report.strip()}\n\n"
        f"Actual:\n{actual_report.strip()}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
