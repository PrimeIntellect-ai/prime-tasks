#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import math

def get_expected_output():
    fasta_path = "/home/user/data/input.fasta"
    script_path = "/home/user/scripts/fft_power.py"

    # Parse FASTA
    sequences = []
    with open(fasta_path, "r") as f:
        seq = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq:
                    sequences.append(seq)
                    seq = ""
            else:
                seq += line
        if seq:
            sequences.append(seq)

    # Translate and get powers
    mapping = {'A': '1.1', 'C': '2.2', 'G': '3.3', 'T': '4.4'}
    powers = []
    for seq in sequences:
        signal = ",".join(mapping[c] for c in seq)
        res = subprocess.run([script_path, "--signal", signal], capture_output=True, text=True, check=True)
        powers.append(float(res.stdout.strip()))

    # Sort powers
    powers.sort()

    # Sum using bc, then format the displayed result to exactly four decimals.
    sum_expr = " + ".join(f"{p:.6f}" for p in powers)
    bc_input = f"scale=4; {sum_expr}\n"
    res_bc = subprocess.run(["bc"], input=bc_input, capture_output=True, text=True, check=True)
    total_power = f"{float(res_bc.stdout.strip()):.4f}"

    # Histogram
    bins = {}
    max_bin = 0
    for p in powers:
        b = math.floor(p)
        bins[b] = bins.get(b, 0) + 1
        if b > max_bin:
            max_bin = b

    expected_lines = [f"TOTAL_POWER: {total_power}", "HISTOGRAM:"]
    for b in range(max_bin + 1):
        count = bins.get(b, 0)
        expected_lines.append(f"Bin {b}: {count}")

    return "\n".join(expected_lines) + "\n"

def test_pipeline_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

def test_pipeline_output_chunk_1():
    path = "/home/user/pipeline.sh"
    res = subprocess.run([path, "1"], capture_output=True, text=True)
    assert res.returncode == 0, f"pipeline.sh failed with chunk size 1. Error: {res.stderr}"

    expected = get_expected_output()
    assert res.stdout.strip() == expected.strip(), f"Output mismatch for chunk size 1.\nExpected:\n{expected}\nGot:\n{res.stdout}"

def test_pipeline_output_chunk_2():
    path = "/home/user/pipeline.sh"
    res = subprocess.run([path, "2"], capture_output=True, text=True)
    assert res.returncode == 0, f"pipeline.sh failed with chunk size 2. Error: {res.stderr}"

    expected = get_expected_output()
    assert res.stdout.strip() == expected.strip(), f"Output mismatch for chunk size 2.\nExpected:\n{expected}\nGot:\n{res.stdout}"

def test_pipeline_output_chunk_3():
    path = "/home/user/pipeline.sh"
    res = subprocess.run([path, "3"], capture_output=True, text=True)
    assert res.returncode == 0, f"pipeline.sh failed with chunk size 3. Error: {res.stderr}"

    expected = get_expected_output()
    assert res.stdout.strip() == expected.strip(), f"Output mismatch for chunk size 3.\nExpected:\n{expected}\nGot:\n{res.stdout}"

def test_pipeline_output_chunk_10():
    path = "/home/user/pipeline.sh"
    res = subprocess.run([path, "10"], capture_output=True, text=True)
    assert res.returncode == 0, f"pipeline.sh failed with chunk size 10. Error: {res.stderr}"

    expected = get_expected_output()
    assert res.stdout.strip() == expected.strip(), f"Output mismatch for chunk size 10.\nExpected:\n{expected}\nGot:\n{res.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
