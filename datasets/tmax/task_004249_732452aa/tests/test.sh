#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

FIT_C = "/home/user/fit.c"
DATA = "/home/user/data.csv"
COEFF = "/home/user/coefficients.txt"
BINARY = "/tmp/fit_verifier_bin"
ORIGINAL_EXPECTED = "1.5000,-2.0000,0.5000,1.2000"


def read_coefficients(require_exact_format=True):
    assert os.path.isfile(COEFF), f"Error: {COEFF} does not exist."
    with open(COEFF, "rb") as f:
        raw = f.read()
    if require_exact_format:
        text = raw.decode("ascii")
        pattern = r"[-+]?\d+\.\d{4},[-+]?\d+\.\d{4},[-+]?\d+\.\d{4},[-+]?\d+\.\d{4}\n"
        assert re.fullmatch(pattern, text), f"Error: coefficients have the wrong format: {text!r}"
    return [float(v) for v in raw.decode("ascii").strip().split(",")]


def least_squares_qr(xs, ys):
    # Modified Gram-Schmidt QR, implemented here so expected answers are
    # independently derived from each verifier-generated data set.
    columns = [[1.0 for x in xs], list(xs), [x*x for x in xs], [x*x*x for x in xs]]
    q = []
    r = [[0.0] * 4 for _ in range(4)]
    for j in range(4):
        v = columns[j][:]
        for i in range(j):
            rij = sum(q[i][k] * v[k] for k in range(len(xs)))
            r[i][j] = rij
            for k in range(len(xs)):
                v[k] -= rij * q[i][k]
        norm = math.sqrt(sum(value * value for value in v))
        assert norm > 1e-10
        r[j][j] = norm
        q.append([value / norm for value in v])

    qty = [sum(q[i][k] * ys[k] for k in range(len(xs))) for i in range(4)]
    beta = [0.0] * 4
    for i in range(3, -1, -1):
        beta[i] = (qty[i] - sum(r[i][j] * beta[j] for j in range(i + 1, 4))) / r[i][i]
    return beta


def run_program():
    if os.path.exists(COEFF):
        os.remove(COEFF)
    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, text=True
    )
    assert result.returncode == 0, (
        f"Compiled fit program exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return read_coefficients()


def write_dataset(xs, ys):
    fields = []
    for x, y in zip(xs, ys):
        fields.extend((f"{x:.12g}", f"{y:.12g}"))
    with open(DATA, "w", encoding="ascii") as f:
        f.write(",".join(fields) + "\n")
    # Derive expectations from exactly the rounded values supplied to the C program.
    return ([float(fields[i]) for i in range(0, len(fields), 2)],
            [float(fields[i]) for i in range(1, len(fields), 2)])


def main():
    # Preserve the original verifier's assertions.
    assert os.path.isfile(FIT_C), "Error: /home/user/fit.c does not exist."
    assert os.path.isfile(COEFF), f"Error: {COEFF} does not exist."
    with open(COEFF, "r") as f:
        content = f.read().strip()
    assert content == ORIGINAL_EXPECTED, (
        f"Error: Expected coefficients '{ORIGINAL_EXPECTED}', got '{content}'"
    )

    with open(DATA, "rb") as f:
        saved_data = f.read()
    with open(COEFF, "rb") as f:
        saved_coeff = f.read()

    try:
        compile_result = subprocess.run(
            ["gcc", "-O2", "-std=c11", FIT_C, "-o", BINARY,
             "-lgsl", "-lgslcblas", "-llapacke", "-lopenblas", "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, text=True
        )
        assert compile_result.returncode == 0, (
            "Error: /home/user/fit.c did not compile as C.\n"
            f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
        )
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

        # Execute the compiled artifact against the original input as well.
        with open(DATA, "wb") as f:
            f.write(saved_data)
        original_values = run_program()
        assert ",".join(f"{v:.4f}" for v in original_values) == ORIGINAL_EXPECTED, (
            f"Error: compiled program produced {original_values} for the original data"
        )

        # Exercise varying, overdetermined, noisy data sets so a fixed output or
        # interpolation of only four rows cannot satisfy the verifier.
        rng = random.SystemRandom()
        grid = [i / 4.0 for i in range(-14, 15)]
        for count in (8, 11, 14):
            xs = rng.sample(grid, count)
            rng.shuffle(xs)
            beta_seed = [rng.uniform(-3.5, 3.5) for _ in range(4)]
            for i, value in enumerate(beta_seed):
                if abs(value) < 0.35:
                    beta_seed[i] = 0.35 if value >= 0 else -0.35
            ys = []
            for x in xs:
                model = sum(beta_seed[j] * (x ** j) for j in range(4))
                ys.append(model + rng.uniform(-0.08, 0.08))

            actual_xs, actual_ys = write_dataset(xs, ys)
            expected = least_squares_qr(actual_xs, actual_ys)
            actual = run_program()
            for index, (got, want) in enumerate(zip(actual, expected)):
                assert abs(got - want) <= 0.00012, (
                    f"Error: data-dependent coefficient beta_{index} was {got:.4f}; "
                    f"expected {want:.4f}"
                )
    finally:
        with open(DATA, "wb") as f:
            f.write(saved_data)
        with open(COEFF, "wb") as f:
            f.write(saved_coeff)
        if os.path.exists(BINARY):
            os.remove(BINARY)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
