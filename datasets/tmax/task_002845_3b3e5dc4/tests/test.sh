#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

ORIGINAL_ALPHA_LOG = """[1700000000] host=alpha reqs=5
[1700000001] host=alpha reqs=2
[1700000004] host=alpha reqs=8
[1700000005] host=alpha reqs=3
[1700000010] host=alpha reqs=1
[1700000012] host=alpha reqs=6
[1700000015] host=alpha reqs=4
"""

ORIGINAL_BETA_LOG = """[1700000002] host=beta reqs=4
[1700000004] host=beta reqs=8
[1700000006] host=beta reqs=2
[1700000009] host=beta reqs=5
[1700000010] host=beta reqs=3
[1700000011] host=beta reqs=7
[1700000015] host=beta reqs=4
"""


def parse_log(content):
    data = {}
    pattern = re.compile(r"\[(\d+)\]\s+host=\w+\s+reqs=(\d+)")
    for line in content.splitlines():
        match = pattern.search(line)
        if match:
            data[int(match.group(1))] = int(match.group(2))
    return data


def compute_expected_distance():
    alpha_data = parse_log(ORIGINAL_ALPHA_LOG)
    beta_data = parse_log(ORIGINAL_BETA_LOG)

    if not alpha_data and not beta_data:
        return 0

    min_ts = min(list(alpha_data.keys()) + list(beta_data.keys()))
    max_ts = max(list(alpha_data.keys()) + list(beta_data.keys()))

    total_distance = 0
    for ts in range(min_ts, max_ts + 1):
        a_reqs = alpha_data.get(ts, 0)
        b_reqs = beta_data.get(ts, 0)
        total_distance += abs(a_reqs - b_reqs)

    return total_distance


def test_distance_result():
    result_file = "/home/user/distance_result.txt"
    assert os.path.isfile(result_file), f"Expected result file {result_file} does not exist."

    with open(result_file, "r") as f:
        content = f.read().strip()

    expected_distance = compute_expected_distance()
    expected_content = f"Total Distance: {expected_distance}"

    assert content == expected_content, f"Result file content '{content}' does not match expected '{expected_content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
