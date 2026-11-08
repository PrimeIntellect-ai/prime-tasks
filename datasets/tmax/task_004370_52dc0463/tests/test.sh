#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os

def test_simulate_c_exists():
    assert os.path.exists('/home/user/simulate.c'), "Source file /home/user/simulate.c does not exist"

def test_distance_computation():
    # 1. Read reference data and bin it
    ref_bins = [0] * 100
    ref_total = 0
    ref_path = '/home/user/reference.txt'
    assert os.path.exists(ref_path), f"Reference file {ref_path} is missing"

    with open(ref_path, 'r') as f:
        for line in f:
            val = float(line.strip())
            if 0.0 <= val < 10.0:
                idx = int(val / 0.1)
                if 0 <= idx < 100:
                    ref_bins[idx] += 1
                    ref_total += 1

    # 2. Generate simulated data and bin it
    state = 42
    def next_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) % 2147483648
        return state

    sim_bins = [0] * 100
    sim_total = 0
    for _ in range(10000):
        u1 = (next_rand() + 1.0) / 2147483649.0
        u2 = (next_rand() + 1.0) / 2147483649.0
        z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
        E = 5.0 + 2.0 * z

        if 0.0 <= E < 10.0:
            idx = int(E / 0.1)
            if 0 <= idx < 100:
                sim_bins[idx] += 1
                sim_total += 1

    # 3. Compute Bhattacharyya distance
    bc = 0.0
    for i in range(100):
        if ref_total > 0 and sim_total > 0:
            p = ref_bins[i] / ref_total
            q = sim_bins[i] / sim_total
            bc += math.sqrt(p * q)

    expected_dist = -math.log(bc)
    expected_str = f"{expected_dist:.4f}"

    # 4. Check user output
    dist_path = '/home/user/distance.txt'
    assert os.path.exists(dist_path), f"Output file {dist_path} does not exist"

    with open(dist_path, 'r') as f:
        user_str = f.read().strip()

    assert user_str == expected_str, f"Expected distance {expected_str}, but got {user_str} in {dist_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
