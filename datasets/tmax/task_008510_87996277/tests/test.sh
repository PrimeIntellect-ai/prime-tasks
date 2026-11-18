#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SCRIPT_PATH = "/home/user/prepare_data.sh"
NORM_PATH = "/home/user/norm_constant.txt"
TVD_PATH = "/home/user/tvd.txt"


def f(x):
    return (x**3) * (math.cos(x / 2)**2)


def get_expected_values():
    # 1. Normalization Constant (Z)
    N = 1000
    a, b = 0.0, 2.0
    dx = (b - a) / N

    Z = 0.0
    for i in range(N):
        x_i = a + i * dx
        x_next = a + (i + 1) * dx
        Z += (f(x_i) + f(x_next)) / 2.0 * dx

    expected_Z_str = f"{Z:.4f}"

    # 2 & 3. Bin probabilities and TVD
    num_bins = 10
    bin_width = (b - a) / num_bins
    steps_per_bin = 100
    dx_bin = bin_width / steps_per_bin

    tvd = 0.0
    for j in range(num_bins):
        bin_a = a + j * bin_width
        P_A_unnorm = 0.0
        for k in range(steps_per_bin):
            x_k = bin_a + k * dx_bin
            x_next = bin_a + (k + 1) * dx_bin
            P_A_unnorm += (f(x_k) + f(x_next)) / 2.0 * dx_bin

        P_A = P_A_unnorm / Z
        P_B = 1.0 / num_bins
        tvd += abs(P_A - P_B)

    expected_tvd_str = f"{tvd / 2.0:.4f}"
    return expected_Z_str, expected_tvd_str


def uncommented_source(source):
    # Remove ordinary shell/Python/awk comment text so comments alone cannot
    # masquerade as an implementation.
    return "\n".join(line.split("#", 1)[0] for line in source.splitlines())


def test_script_contains_numerical_implementation():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as fh:
        source = fh.read()

    expected_z, expected_tvd = get_expected_values()
    assert expected_z not in source, "The rounded normalization answer is hardcoded in the script"
    assert expected_tvd not in source, "The rounded TVD answer is hardcoded in the script"

    code = uncommented_source(source).lower()
    assert re.search(r"\b1000\b", code), "Missing the required 1000-step integration"
    assert re.search(r"\b100\b", code), "Missing the required 100-step per-bin integration"
    assert re.search(r"\b10\b", code), "Missing the required 10-bin calculation"
    assert re.search(r"\b(?:cos|c)\s*\(", code), "Missing a cosine evaluation"
    assert re.search(r"\b(?:for|while)\b", code), "Missing iterative numerical integration"
    assert re.search(r"(?:/\s*2(?:\.0)?\b|\*\s*0\.5\b|\b0\.5\s*\*)", code), \
        "Missing trapezoidal half-weight calculation"


def test_script_exists_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    # Ensure the checked files are newly produced by this execution.
    for path in (NORM_PATH, TVD_PATH):
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"


def test_norm_constant_output():
    expected_z, _ = get_expected_values()
    assert os.path.isfile(NORM_PATH) and not os.path.islink(NORM_PATH), \
        f"Output file {NORM_PATH} not found or is not a regular file."

    with open(NORM_PATH, "r") as fobj:
        content = fobj.read().strip()

    assert content == expected_z, f"Expected normalization constant {expected_z}, but got {content}"


def test_tvd_output():
    _, expected_tvd = get_expected_values()
    assert os.path.isfile(TVD_PATH) and not os.path.islink(TVD_PATH), \
        f"Output file {TVD_PATH} not found or is not a regular file."

    with open(TVD_PATH, "r") as fobj:
        content = fobj.read().strip()

    assert content == expected_tvd, f"Expected TVD {expected_tvd}, but got {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
