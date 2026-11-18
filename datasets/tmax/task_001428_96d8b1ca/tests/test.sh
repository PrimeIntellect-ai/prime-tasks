#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

SOURCE = "/home/user/sensor_analysis.c"
BINARY = "/home/user/sensor_analysis"
NETWORK = "/home/user/network.txt"
SPECTRA = "/home/user/spectra.csv"
SOLUTION = "/home/user/solution.txt"
VERIFIED_BINARY = "/tmp/sensor_analysis_verified"


def expected_content(network_path=NETWORK, spectra_path=SPECTRA):
    with open(network_path, "r") as f:
        lines = f.read().strip().split('\n')

    max_deg = -1
    best_node = -1
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        degree = sum(int(x) for x in line.strip().split())
        if degree > max_deg:
            max_deg = degree
            best_node = i

    x_vals = []
    y_vals = []
    with open(spectra_path, "r") as f:
        f.readline()
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            if int(parts[0]) == best_node:
                x_vals.append(float(parts[1]))
                y_vals.append(float(parts[2]))

    assert x_vals, f"No spectral data found for node {best_node}."
    n = len(x_vals)
    sum_x = sum(x_vals)
    sum_y = sum(y_vals)
    sum_xx = sum(x * x for x in x_vals)
    sum_xy = sum(x * y for x, y in zip(x_vals, y_vals))
    det = n * sum_xx - sum_x ** 2
    assert det != 0, "Regression data are singular."
    b1 = (n * sum_xy - sum_x * sum_y) / det
    b0 = (sum_y - b1 * sum_x) / n
    return "\n".join([
        f"Node: {best_node}",
        f"Intercept: {b0:.4f}",
        f"Slope: {b1:.4f}",
    ])


def run_and_check(executable):
    if os.path.exists(SOLUTION):
        os.remove(SOLUTION)
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SOLUTION), (
        f"File {SOLUTION} is missing. The C program must create this file."
    )
    with open(SOLUTION, "r") as f:
        actual = f.read().strip()
    expected = expected_content()
    assert actual == expected, (
        f"Content of {SOLUTION} does not match the expected output.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def write_challenge(case_number):
    rng = secrets.SystemRandom()
    n_nodes = rng.randrange(4, 8)
    matrix = [[0] * n_nodes for _ in range(n_nodes)]

    if case_number % 2 == 0:
        # Every node ties at degree two, so the required tie-break selects node 0.
        for i in range(n_nodes):
            j = (i + 1) % n_nodes
            matrix[i][j] = matrix[j][i] = 1
    else:
        # A randomly selected star center is uniquely most central.
        center = rng.randrange(n_nodes)
        for i in range(n_nodes):
            if i != center:
                matrix[center][i] = matrix[i][center] = 1

    with open(NETWORK, "w") as f:
        for row in matrix:
            f.write(" ".join(str(v) for v in row) + "\n")

    with open(SPECTRA, "w") as f:
        f.write("NodeID,Wavelength,Absorbance\n")
        for node in range(n_nodes):
            intercept = rng.randrange(-60, 91) / 13.0 + node / 17.0
            slope = rng.randrange(7, 80) / 19.0 + node / 23.0
            base = rng.randrange(1, 20) / 3.0
            for k in range(5):
                x = base + k * 0.7
                noise = [0.031, -0.047, 0.018, 0.052, -0.026][k]
                y = intercept + slope * x + noise
                f.write(f"{node},{x:.8f},{y:.8f}\n")


def test_program_artifacts_gsl_and_behavior():
    assert os.path.isfile(NETWORK), f"{NETWORK} is missing."
    assert os.path.isfile(SPECTRA), f"{SPECTRA} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(BINARY), f"{BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    elf = subprocess.run(["readelf", "-h", BINARY], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    assert elf.returncode == 0, f"{BINARY} is not a compiled ELF executable."

    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    for function in ("gsl_linalg_cholesky_decomp", "gsl_linalg_cholesky_solve"):
        assert re.search(r"\b" + re.escape(function) + r"\s*\(", source_text), (
            f"{SOURCE} does not call required GSL function {function}."
        )

    build = subprocess.run([
        "gcc", "-o", VERIFIED_BINARY, SOURCE, "-lgsl", "-lgslcblas", "-lm"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert build.returncode == 0, (
        f"The required compile command failed.\nstdout:\n{build.stdout}"
        f"\nstderr:\n{build.stderr}"
    )

    symbols = subprocess.run(["nm", "-D", VERIFIED_BINARY], check=True,
                             stdout=subprocess.PIPE, text=True).stdout
    for function in ("gsl_linalg_cholesky_decomp", "gsl_linalg_cholesky_solve"):
        assert re.search(r"\bU\s+" + re.escape(function) + r"(?:@|$)", symbols, re.M), (
            f"The compiled program does not link a call to required GSL function {function}."
        )

    with open(NETWORK, "rb") as f:
        original_network = f.read()
    with open(SPECTRA, "rb") as f:
        original_spectra = f.read()

    try:
        # Preserve the original verifier's exact content assertion on the supplied data.
        run_and_check(VERIFIED_BINARY)

        # Exercise the submitted source on unpredictable alternate networks and spectra.
        for case_number in range(4):
            write_challenge(case_number)
            run_and_check(VERIFIED_BINARY)
    finally:
        with open(NETWORK, "wb") as f:
            f.write(original_network)
        with open(SPECTRA, "wb") as f:
            f.write(original_spectra)

    # Leave the requested original result in place and also execute the submitted binary.
    run_and_check(VERIFIED_BINARY)
    run_and_check(BINARY)


if __name__ == "__main__":
    test_program_artifacts_gsl_and_behavior()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
