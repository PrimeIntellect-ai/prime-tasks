#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_solve_cpp_exists_and_uses_eigen_qr():
    cpp_file = '/home/user/solve.cpp'
    assert os.path.isfile(cpp_file), f"The file {cpp_file} is missing."

    with open(cpp_file, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'Eigen' in content, f"{cpp_file} does not appear to include Eigen headers."
    assert 'Qr' in content or 'QR' in content or 'qr' in content.lower(), f"{cpp_file} does not appear to use a QR decomposition method from Eigen."

def test_beta_txt():
    beta_file = '/home/user/beta.txt'
    expected_beta_file = '/tests/.expected_beta.txt'

    assert os.path.isfile(beta_file), f"The file {beta_file} is missing."
    assert os.path.isfile(expected_beta_file), f"The verifier oracle {expected_beta_file} is missing."

    with open(beta_file, 'r') as f:
        beta_lines = [line.strip() for line in f if line.strip()]

    with open(expected_beta_file, 'r') as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    assert len(beta_lines) == 4, f"{beta_file} should contain exactly 4 lines."
    assert len(expected_lines) == 4, f"{expected_beta_file} should contain exactly 4 lines."

    for i, (b_str, exp_str) in enumerate(zip(beta_lines, expected_lines)):
        try:
            b_val = float(b_str)
        except ValueError:
            pytest.fail(f"Could not parse '{b_str}' as a float in {beta_file}.")
        exp_val = float(exp_str)

        assert b_val == pytest.approx(exp_val, abs=1e-3), f"Coefficient {i} in {beta_file} ({b_val}) does not match expected ({exp_val})."

def test_residuals_txt():
    res_file = '/home/user/residuals.txt'
    expected_res_file = '/tests/.expected_residuals.txt'

    assert os.path.isfile(res_file), f"The file {res_file} is missing."
    assert os.path.isfile(expected_res_file), f"The verifier oracle {expected_res_file} is missing."

    with open(res_file, 'r') as f:
        res_lines = [line.strip() for line in f if line.strip()]

    with open(expected_res_file, 'r') as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    assert len(res_lines) == 50, f"{res_file} should contain exactly 50 lines."
    assert len(expected_lines) == 50, f"{expected_res_file} should contain exactly 50 lines."

    for i, (r_str, exp_str) in enumerate(zip(res_lines, expected_lines)):
        try:
            r_val = float(r_str)
        except ValueError:
            pytest.fail(f"Could not parse '{r_str}' as a float in {res_file}.")
        exp_val = float(exp_str)

        assert r_val == pytest.approx(exp_val, abs=1e-2), f"Residual {i} in {res_file} ({r_val}) does not match expected ({exp_val})."

def test_residuals_png():
    png_file = '/home/user/residuals.png'
    assert os.path.isfile(png_file), f"The file {png_file} is missing."

    with open(png_file, 'rb') as f:
        header = f.read(8)

    # Check PNG magic bytes
    expected_magic = b'\x89PNG\r\n\x1a\n'
    assert header == expected_magic, f"{png_file} is not a valid PNG file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
