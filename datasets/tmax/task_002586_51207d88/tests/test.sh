#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
from scipy.optimize import curve_fit


def test_overhang_extracted():
    overhang_file = "/home/user/overhang.txt"
    seq_file = "/home/user/sequence.txt"

    assert os.path.exists(overhang_file), f"File {overhang_file} does not exist."
    assert os.path.exists(seq_file), f"File {seq_file} does not exist."

    with open(seq_file, "r") as f:
        seq = f.read().strip()

    idx = seq.find("GGTCTC")
    assert idx != -1, "BsaI site not found in sequence.txt."

    next_4 = seq[idx+6:idx+10]
    complement = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'}
    expected_overhang = "".join(complement.get(base, base) for base in reversed(next_4))

    with open(overhang_file, "r") as f:
        actual_overhang = f.read().strip()

    assert actual_overhang == expected_overhang, f"Expected overhang '{expected_overhang}', but got '{actual_overhang}'."


def test_qpcr_col_max_r():
    result_file = "/home/user/col_max_r.txt"
    data_file = "/home/user/qpcr_data.csv"

    assert os.path.exists(result_file), f"File {result_file} does not exist."
    assert os.path.exists(data_file), f"File {data_file} does not exist."

    data = np.loadtxt(data_file, delimiter=',')
    assert data.shape == (96, 40), f"Expected qPCR data shape (96, 40), got {data.shape}."

    x = np.arange(5, 16, dtype=float)

    def exponential(x, A, r):
        return A * np.exp(r * x)

    rates = []
    for row in data:
        params, _ = curve_fit(exponential, x, row[4:15], p0=[10, 0.2])
        rates.append(params[1])

    column_maxima = np.asarray(rates).reshape(8, 12).max(axis=0)
    expected_content = ",".join(f"{value:.4f}" for value in column_maxima)

    with open(result_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Expected col_max_r content '{expected_content}', but got '{actual_content}'."
    )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
