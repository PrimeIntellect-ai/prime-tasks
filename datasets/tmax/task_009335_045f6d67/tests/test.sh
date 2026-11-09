#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def get_bin(val, min_v, max_v, num_bins):
    if val == max_v:
        return num_bins - 1
    return int((val - min_v) / (max_v - min_v) * num_bins)

def test_final_state():
    cpp_source = "/home/user/profiler.cpp"
    cpp_exec = "/home/user/profiler"
    csv_file = "/home/user/profiling_data.csv"
    json_file = "/home/user/scaling_report.json"

    assert os.path.isfile(cpp_source), f"C++ source file missing: {cpp_source}"
    assert os.path.isfile(cpp_exec), f"C++ executable missing: {cpp_exec}"
    assert os.path.isfile(csv_file), f"CSV data missing: {csv_file}"
    assert os.path.isfile(json_file), f"Output JSON missing: {json_file}"

    # Read the CSV data to compute the truth values
    data = []
    with open(csv_file, 'r') as f:
        header = f.readline()
        for line in f:
            if line.strip():
                x_str, time_str = line.strip().split(',')
                data.append((float(x_str), float(time_str)))

    assert len(data) > 0, "CSV file has no data rows"

    T_min = min(d[1] for d in data)
    T_max = max(d[1] for d in data)

    N_vals = [2, 4, 8, 16, 32]
    D_N = []

    for N in N_vals:
        max_tvd = 0.0
        for i in range(N):
            sub_min = i / N
            sub_max = (i + 1) / N

            # Filter data for this sub-domain
            if i == N - 1:
                sub_data = [d[1] for d in data if sub_min <= d[0] <= sub_max]
            else:
                sub_data = [d[1] for d in data if sub_min <= d[0] < sub_max]

            if len(sub_data) == 0:
                max_tvd = max(max_tvd, 1.0)
                continue

            counts = [0] * 10
            for t in sub_data:
                b = get_bin(t, T_min, T_max, 10)
                counts[b] += 1

            tvd = 0.0
            for k in range(10):
                P_k = counts[k] / len(sub_data)
                Q_k = 0.1
                tvd += abs(P_k - Q_k)
            tvd *= 0.5

            max_tvd = max(max_tvd, tvd)
        D_N.append(max_tvd)

    log_N = [math.log(n) for n in N_vals]
    log_D = [math.log(d) for d in D_N]

    mean_x = sum(log_N) / len(log_N)
    mean_y = sum(log_D) / len(log_D)

    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(log_N, log_D))
    denominator = sum((x - mean_x)**2 for x in log_N)
    expected_b = numerator / denominator
    expected_D_32 = D_N[-1]

    # Read student JSON
    with open(json_file, 'r') as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {json_file} as valid JSON.")

    assert "exponent_b" in student_results, "Missing 'exponent_b' in JSON output"
    assert "D_32" in student_results, "Missing 'D_32' in JSON output"

    student_b = float(student_results["exponent_b"])
    student_D_32 = float(student_results["D_32"])

    tolerance = 0.0002

    assert abs(student_b - expected_b) <= tolerance, \
        f"exponent_b mismatch: expected {expected_b:.4f}, got {student_b:.4f} (tolerance {tolerance})"

    assert abs(student_D_32 - expected_D_32) <= tolerance, \
        f"D_32 mismatch: expected {expected_D_32:.4f}, got {student_D_32:.4f} (tolerance {tolerance})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
