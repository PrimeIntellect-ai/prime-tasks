#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import subprocess
import pytest

def test_mcmc_and_histogram_results():
    ref_data_path = "/home/user/ref_data.txt"
    synth_data_path = "/home/user/synthetic_data.txt"
    hist_data_path = "/home/user/histogram.txt"

    assert os.path.isfile(ref_data_path), f"File {ref_data_path} is missing."
    assert os.path.isfile(synth_data_path), f"File {synth_data_path} is missing."
    assert os.path.isfile(hist_data_path), f"File {hist_data_path} is missing."

    # 1. Calculate Reference Statistics
    with open(ref_data_path, "r") as f:
        data = [float(line.strip()) for line in f if line.strip()]

    n = len(data)
    mu = sum(data) / n
    variance = sum((x - mu)**2 for x in data) / (n - 1)
    sigma = math.sqrt(variance)

    # 2. Generate Expected Data using gawk
    awk_script = f"""
    BEGIN {{
        mu = {mu}
        sigma = {sigma}
        srand(42)
        x = mu
        for(i=0; i<10000; i++) {{
            print x > "/tmp/expected_synth.txt"
            x_prop = x + (rand() - 0.5) * 4 * sigma
            delta = -((x_prop - mu)^2)/(2*sigma^2) + ((x - mu)^2)/(2*sigma^2)
            alpha = exp(delta)
            if (alpha >= 1) {{
                x = x_prop
            }} else {{
                if (rand() < alpha) {{
                    x = x_prop
                }}
            }}
        }}

        w = (6 * sigma) / 10
        start = mu - 3 * sigma
        for(i=0; i<10; i++) bins[i] = 0

        while((getline v < "/tmp/expected_synth.txt") > 0) {{
            q = (v - start) / w
            k = int(q)
            if (q < 0 && q != k) k--
            if (k >= 0 && k <= 9) {{
                bins[k]++
            }}
        }}
        for(i=0; i<10; i++) {{
            print bins[i] > "/tmp/expected_hist.txt"
        }}
    }}
    """

    with open("/tmp/generate_expected.awk", "w") as f:
        f.write(awk_script)

    subprocess.run(["gawk", "-f", "/tmp/generate_expected.awk"], check=True)

    # 3. Verify Synthetic Data
    with open("/tmp/expected_synth.txt", "r") as f:
        expected_synth = [float(line.strip()) for line in f if line.strip()]

    with open(synth_data_path, "r") as f:
        actual_synth = [float(line.strip()) for line in f if line.strip()]

    assert len(actual_synth) == 10000, f"Expected 10000 lines in {synth_data_path}, found {len(actual_synth)}"

    for i, (exp, act) in enumerate(zip(expected_synth, actual_synth)):
        assert math.isclose(exp, act, rel_tol=1e-5, abs_tol=1e-5), f"Mismatch in {synth_data_path} at line {i+1}: expected {exp}, got {act}"

    # 4. Verify Histogram Data
    with open("/tmp/expected_hist.txt", "r") as f:
        expected_hist = [int(line.strip()) for line in f if line.strip()]

    with open(hist_data_path, "r") as f:
        actual_hist = [int(line.strip()) for line in f if line.strip()]

    assert len(actual_hist) == 10, f"Expected 10 lines in {hist_data_path}, found {len(actual_hist)}"

    for i, (exp, act) in enumerate(zip(expected_hist, actual_hist)):
        assert exp == act, f"Mismatch in {hist_data_path} at bin {i}: expected {exp}, got {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
