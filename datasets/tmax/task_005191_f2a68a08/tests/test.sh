#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def test_total_distance_calculation():
    """
    Re-derives the expected total Euclidean travel distance from the base toolpath
    using the extracted scale factor S = 42, and compares it against the agent's output.
    The relative error must be <= 0.01% (0.0001).
    """
    gcode_path = '/app/base_toolpath.gcode'
    output_path = '/home/user/total_distance.txt'

    assert os.path.exists(gcode_path), f"Base GCode file missing at {gcode_path}"
    assert os.path.exists(output_path), f"Agent output file missing at {output_path}"

    # Re-derive expected distance
    expected_dist = 0.0
    curr_x, curr_y = 0.0, 0.0
    S = 42.0

    with open(gcode_path, 'r') as f:
        for line in f:
            if line.startswith('G1 X'):
                parts = line.strip().split()
                # Parse X and Y values
                x_str = next((p[1:] for p in parts if p.startswith('X')), None)
                y_str = next((p[1:] for p in parts if p.startswith('Y')), None)

                if x_str is not None and y_str is not None:
                    try:
                        x_orig = float(x_str)
                        y_orig = float(y_str)
                    except ValueError:
                        continue

                    # Apply transformation macro
                    if x_orig < 0:
                        x_new = x_orig * S
                        y_new = y_orig * S
                    else:
                        x_new = x_orig * (S / 2.0)
                        y_new = y_orig * (S / 2.0)

                    # Calculate Euclidean distance
                    dist = math.sqrt((x_new - curr_x)**2 + (y_new - curr_y)**2)
                    expected_dist += dist
                    curr_x, curr_y = x_new, y_new

    # Read agent's calculated distance
    with open(output_path, 'r') as f:
        content = f.read().strip()

    try:
        agent_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse agent output '{content}' as a float from {output_path}")

    # Calculate relative error
    if expected_dist > 0:
        error = abs(agent_val - expected_dist) / expected_dist
    else:
        error = abs(agent_val)

    assert error <= 0.0001, (
        f"Distance {agent_val} is outside acceptable range. "
        f"Expected ~{expected_dist:.4f}, Relative Error: {error:.6f} (Threshold: 0.0001)"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
