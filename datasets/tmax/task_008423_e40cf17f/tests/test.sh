#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math

def test_rust_source_exists():
    """Check if the Rust source file was created."""
    assert os.path.isfile("/home/user/integrate.rs"), "The file /home/user/integrate.rs does not exist."

def test_report_json_exists():
    """Check if the report.json file was generated."""
    assert os.path.isfile("/home/user/report.json"), "The file /home/user/report.json does not exist."

def test_report_json_contents():
    """Check if the report.json contains the correct calculated values."""
    with open("/home/user/report.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/report.json is not a valid JSON file."

    # Verify keys
    expected_keys = {"integral", "x1", "x2"}
    assert set(data.keys()) == expected_keys, f"report.json keys {set(data.keys())} do not match expected {expected_keys}."

    # Compute expected values
    # x1, x2 where 15.0 / ((x - 12.0)^2 + 0.04) = 100.0
    # (x - 12.0)^2 = 0.15 - 0.04 = 0.11
    # x = 12.0 +/- sqrt(0.11)
    x1_expected = round(12.0 - math.sqrt(0.11), 4)
    x2_expected = round(12.0 + math.sqrt(0.11), 4)

    # Simpson's 1/3 rule for integral
    def f(x):
        return 15.0 / ((x - 12.0)**2 + 0.04)

    a, b = 0.0, 24.0
    N = 1000
    h = (b - a) / N
    s = f(a) + f(b)
    for i in range(1, N, 2):
        s += 4 * f(a + i * h)
    for i in range(2, N, 2):
        s += 2 * f(a + i * h)
    integral_expected = round(s * h / 3, 4)

    # Check values
    assert isinstance(data["integral"], (int, float)), "integral must be a number."
    assert isinstance(data["x1"], (int, float)), "x1 must be a number."
    assert isinstance(data["x2"], (int, float)), "x2 must be a number."

    assert math.isclose(data["integral"], integral_expected, rel_tol=1e-4), f"Expected integral ~{integral_expected}, got {data['integral']}"
    assert math.isclose(data["x1"], x1_expected, rel_tol=1e-4), f"Expected x1 ~{x1_expected}, got {data['x1']}"
    assert math.isclose(data["x2"], x2_expected, rel_tol=1e-4), f"Expected x2 ~{x2_expected}, got {data['x2']}"
TEST_EOF

rm -f /tmp/integrate_submission
if rustc /home/user/integrate.rs -o /tmp/integrate_submission; then
    # Remove any pre-existing or compile-time-created report so the submitted
    # executable itself must generate the file being checked.
    rm -f /home/user/report.json
    if timeout 20s /tmp/integrate_submission && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        echo "1" > /logs/verifier/reward.txt
    else
        echo "0" > /logs/verifier/reward.txt
    fi
else
    echo "0" > /logs/verifier/reward.txt
fi
