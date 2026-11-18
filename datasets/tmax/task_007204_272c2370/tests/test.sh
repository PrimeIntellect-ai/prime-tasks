#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np

HOME = "/home/user"
LATENCY = os.path.join(HOME, "latency_data.txt")
CPP = os.path.join(HOME, "compute_metrics.cpp")
PLOT = os.path.join(HOME, "plot_data.py")
CSV = os.path.join(HOME, "normalized_data.csv")
KL = os.path.join(HOME, "kl_divergence.txt")
PNG = os.path.join(HOME, "distributions.png")
DX = 0.1


def require_file(path, message, nonempty=False):
    assert os.path.isfile(path), message
    if nonempty:
        assert os.path.getsize(path) > 0, f"{path} is empty."


def read_input():
    with open(LATENCY, "r") as f:
        lines = f.readlines()
    assert len(lines) == 2, "Input data should have 2 lines."
    rows = [[float(x) for x in line.strip().split()] for line in lines]
    assert all(len(row) == 1000 for row in rows), "Each input row must contain 1000 values."
    assert all(math.isfinite(x) for row in rows for x in row), "Input contains non-finite values."
    return rows


def expected_results(rows):
    smooth = [[x + 1e-9 for x in row] for row in rows]

    def trapz(values):
        return sum((values[i] + values[i + 1]) / 2.0 for i in range(len(values) - 1)) * DX

    areas = [trapz(row) for row in smooth]
    normalized = [[x / area for x in row] for row, area in zip(smooth, areas)]
    integrand = [p * math.log(p / q) for p, q in zip(normalized[0], normalized[1])]
    return normalized, trapz(integrand)


def read_csv_basic():
    require_file(CSV, f"Normalized data file {CSV} is missing.")
    with open(CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {CSV}, found {len(lines)}."
    rows = []
    for i, line in enumerate(lines):
        values = line.split(",")
        assert len(values) == 1000, f"Expected 1000 comma-separated values on line {i + 1}, found {len(values)}."
        try:
            row = [float(v) for v in values]
        except ValueError:
            raise AssertionError(f"Non-float values found in {CSV} on line {i + 1}.")
        assert all(math.isfinite(v) for v in row), f"Non-finite values found in {CSV} on line {i + 1}."
        rows.append(row)
    return rows


def validate_outputs(input_rows):
    expected_rows, expected_kl = expected_results(input_rows)
    actual_rows = read_csv_basic()

    for row_index, (actual, expected) in enumerate(zip(actual_rows, expected_rows), 1):
        for column, (a, e) in enumerate(zip(actual, expected), 1):
            assert math.isclose(a, e, rel_tol=2e-5, abs_tol=2e-8), (
                f"Normalized value at row {row_index}, column {column} does not correspond to the smoothed input."
            )
        area = sum((actual[i] + actual[i + 1]) / 2.0 for i in range(999)) * DX
        assert math.isclose(area, 1.0, rel_tol=2e-5, abs_tol=2e-5), (
            f"CSV row {row_index} is not normalized by trapezoidal integration."
        )

    require_file(KL, f"KL divergence file {KL} is missing.")
    with open(KL, "r") as f:
        actual_kl = f.read().strip()
    expected_text = f"KL: {expected_kl:.6f}"
    assert actual_kl == expected_text, f"Expected KL divergence output '{expected_text}', but got '{actual_kl}'."


def run_binary(binary):
    subprocess.run([binary], cwd=HOME, check=True, timeout=20)


def run_plot():
    if os.path.exists(PNG):
        os.remove(PNG)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run(["python3", PLOT], cwd=HOME, env=env, check=True, timeout=30)
    require_file(PNG, f"Plot image {PNG} is missing.", nonempty=True)
    try:
        image = np.asarray(mpimg.imread(PNG), dtype=float)
    except Exception as exc:
        raise AssertionError(f"{PNG} is not a valid readable image: {exc}")
    assert image.ndim in (2, 3), "Plot image has an invalid pixel layout."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Plot image is implausibly small."
    assert np.isfinite(image).all(), "Plot image contains invalid pixel values."
    assert float(np.std(image)) > 0.005, "Plot image appears blank."
    return image.copy()


def write_challenge_input():
    x = np.arange(1000, dtype=float)
    p = 65.0 * np.exp(-((x - 230.0) ** 2) / (2.0 * 24.0 ** 2))
    q = 90.0 * np.exp(-((x - 710.0) ** 2) / (2.0 * 37.0 ** 2))
    p[::113] = 0.0
    q[::127] = 0.0
    with open(LATENCY, "w") as f:
        f.write(" ".join(f"{v:.12g}" for v in p) + "\n")
        f.write(" ".join(f"{v:.12g}" for v in q) + "\n")


def main():
    # Preserve the original verifier's existence and basic artifact assertions.
    require_file(CPP, "C++ source file /home/user/compute_metrics.cpp is missing.", nonempty=True)
    require_file(PLOT, "Python script /home/user/plot_data.py is missing.", nonempty=True)
    require_file(PNG, "Plot image /home/user/distributions.png is missing.", nonempty=True)
    read_csv_basic()
    original_rows = read_input()
    _, initial_expected_kl = expected_results(original_rows)
    require_file(KL, f"KL divergence file {KL} is missing.")
    with open(KL, "r") as f:
        initial_kl = f.read().strip()
    assert initial_kl == f"KL: {initial_expected_kl:.6f}", "Initial KL divergence output is incorrect."

    with open(LATENCY, "rb") as f:
        original_input = f.read()

    binary = os.path.join(tempfile.mkdtemp(prefix="verify_metrics_"), "compute_metrics")
    subprocess.run(["g++", "-std=c++17", "-O2", CPP, "-o", binary], check=True, timeout=30)

    challenge_image = None
    try:
        run_binary(binary)
        validate_outputs(original_rows)

        write_challenge_input()
        challenge_rows = read_input()
        run_binary(binary)
        validate_outputs(challenge_rows)
        challenge_image = run_plot()
    finally:
        with open(LATENCY, "wb") as f:
            f.write(original_input)

    # Leave all requested outputs corresponding to the real supplied input.
    restored_rows = read_input()
    run_binary(binary)
    validate_outputs(restored_rows)
    original_image = run_plot()

    assert challenge_image is not None
    if challenge_image.shape == original_image.shape:
        difference = float(np.mean(np.abs(challenge_image - original_image)))
        assert difference > 1e-4, "Plot output does not respond to changes in normalized_data.csv."


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
