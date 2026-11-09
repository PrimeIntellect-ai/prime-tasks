#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import subprocess

SOURCE = "/home/user/perf_model.c"
BINARY = "/home/user/perf_model"
DATA = "/home/user/perf_data.csv"
LOG = "/home/user/perf_analysis.log"


def matmul(A, B):
    return [[sum(a * b for a, b in zip(A_row, B_col)) for B_col in zip(*B)] for A_row in A]


def transpose(A):
    return [list(col) for col in zip(*A)]


def invert_matrix(A):
    n = len(A)
    M = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(A)]
    for i in range(n):
        max_row = max(range(i, n), key=lambda r: abs(M[r][i]))
        M[i], M[max_row] = M[max_row], M[i]

        pivot = M[i][i]
        if abs(pivot) < 1e-12:
            raise ValueError("Matrix is singular")

        for j in range(i, 2*n):
            M[i][j] /= pivot

        for k in range(n):
            if k == i:
                continue
            factor = M[k][i]
            for j in range(i, 2*n):
                M[k][j] -= factor * M[i][j]

    return [row[n:] for row in M]


def calculate_expected_ols(csv_path):
    X = []
    y = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            X.append([1.0, float(row['cpu_util']), float(row['mem_util']), float(row['io_wait'])])
            y.append([float(row['response_time'])])

    Xt = transpose(X)
    XtX = matmul(Xt, X)
    Xty = matmul(Xt, y)
    XtX_inv = invert_matrix(XtX)
    beta = matmul(XtX_inv, Xty)
    return [b[0] for b in beta]


def parse_log():
    assert os.path.exists(LOG), "Log file missing."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, "Log file must contain at least two lines."
    ols_line = None
    mcmc_line = None
    for line in lines:
        if line.startswith("OLS_COEFS:"):
            ols_line = line
        elif line.startswith("MCMC_MEANS:"):
            mcmc_line = line

    assert ols_line is not None, "Missing OLS_COEFS line in log."
    assert mcmc_line is not None, "Missing MCMC_MEANS line in log."
    assert re.fullmatch(r"OLS_COEFS:(?: [-+]?\d+\.\d{4}){4}", ols_line), "OLS line must contain four values printed to 4 decimal places."
    assert re.fullmatch(r"MCMC_MEANS:(?: [-+]?\d+\.\d{4}){4}", mcmc_line), "MCMC line must contain four values printed to 4 decimal places."

    try:
        ols_vals = [float(x) for x in ols_line.split()[1:]]
        mcmc_vals = [float(x) for x in mcmc_line.split()[1:]]
    except ValueError:
        assert False, "Could not parse float values from log lines."

    assert len(ols_vals) == 4, "Expected 4 coefficients for OLS."
    assert len(mcmc_vals) == 4, "Expected 4 coefficients for MCMC."
    assert all(math.isfinite(x) for x in ols_vals + mcmc_vals), "All reported values must be finite."
    return ols_vals, mcmc_vals


def run_model(trace_path=None):
    env = os.environ.copy()
    stderr = subprocess.PIPE
    trace_file = None
    if trace_path is not None:
        env["LD_DEBUG"] = "bindings"
        trace_file = open(trace_path, "wb")
        stderr = trace_file
    try:
        result = subprocess.run(
            [BINARY], stdout=subprocess.PIPE, stderr=stderr, env=env,
            timeout=60, check=False
        )
    finally:
        if trace_file is not None:
            trace_file.close()
    assert result.returncode == 0, f"perf_model exited with status {result.returncode}."


def test_files_exist_compile_and_execute():
    assert os.path.isfile(SOURCE), "/home/user/perf_model.c is missing."
    assert os.path.isfile(BINARY), "/home/user/perf_model executable is missing."
    assert os.path.exists(LOG), "/home/user/perf_analysis.log is missing."

    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    assert re.search(r"\b(rand|rand_r|random|drand48)\s*\(", source_text), "The C source does not contain a random-number generator for MCMC."
    assert re.search(r"\b(for|while)\s*\(", source_text), "The C source does not contain an MCMC iteration loop."
    assert re.search(r"\b(exp|log)\s*\(", source_text), "The C source does not contain a Metropolis-Hastings likelihood/acceptance calculation."
    assert re.search(r"(?:0\.0*5(?:[fFlL])?|5(?:\.0*)?[eE]-?2)", source_text), "The required 0.05 proposal scale is not present in the C implementation."
    assert re.search(r"(?:50000|50\s*\*\s*1000|5(?:\.0*)?[eE]\+?4)", source_text), "The required 50,000-iteration chain is not present in the C implementation."
    assert re.search(r"(?:10000|10\s*\*\s*1000|1(?:\.0*)?[eE]\+?4)", source_text), "The required 10,000-iteration burn-in is not present in the C implementation."

    compiled = subprocess.run(
        ["gcc", "-O2", "-o", BINARY, SOURCE, "-llapacke", "-llapack", "-lblas", "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compiled.returncode == 0, "C source failed to compile:\n" + compiled.stderr
    assert os.access(BINARY, os.X_OK), "/home/user/perf_model is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/perf_model is not an ELF executable."

    trace = "/tmp/perf_model.ld_debug"
    run_model(trace)
    with open(trace, "r", errors="replace") as f:
        trace_text = f.read()
    assert re.search(r"symbol [`']LAPACKE_[A-Za-z0-9_]+", trace_text), "The executed program did not call a LAPACKE routine."


def test_mcmc_is_actually_sampled_on_derived_input():
    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        with open(DATA, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "cpu_util", "mem_util", "io_wait", "response_time"])
            for i in range(1000):
                x1 = 0.5 * math.sin(2.0 * math.pi * i / 37.0)
                x2 = 0.5 * math.cos(2.0 * math.pi * i / 53.0)
                x3 = 0.5 * (((i * 17) % 101) / 50.0 - 1.0)
                noise = 0.6 * math.sin(2.0 * math.pi * i / 19.0) + 0.2 * math.cos(2.0 * math.pi * i / 29.0)
                y = 3.25 + 1.4 * x1 - 0.8 * x2 + 2.1 * x3 + noise
                writer.writerow([i, x1, x2, x3, y])

        run_model()
        ols_vals, mcmc_vals = parse_log()
        expected_ols = calculate_expected_ols(DATA)
        for i, (val, exp) in enumerate(zip(ols_vals, expected_ols)):
            assert abs(val - exp) < 1e-2, f"OLS coefficient {i} ({val}) differs from derived expected value ({exp})."
        for i, (m_val, o_val) in enumerate(zip(mcmc_vals, ols_vals)):
            assert abs(m_val - o_val) < 0.1, f"MCMC mean {i} ({m_val}) differs from OLS ({o_val}) by more than 0.1."
        assert any(m != o for m, o in zip(mcmc_vals, ols_vals)), "MCMC_MEANS exactly duplicate OLS_COEFS on an input designed to exercise sampling."
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        subprocess.run([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60, check=False)


def test_analysis_log_contents():
    ols_vals, mcmc_vals = parse_log()
    expected_ols = calculate_expected_ols(DATA)

    for i, (val, exp) in enumerate(zip(ols_vals, expected_ols)):
        assert abs(val - exp) < 1e-2, f"OLS coefficient {i} ({val}) differs from expected ({exp}) by more than 1e-2."

    for i, (m_val, o_val) in enumerate(zip(mcmc_vals, ols_vals)):
        assert abs(m_val - o_val) < 0.1, f"MCMC mean {i} ({m_val}) differs from OLS ({o_val}) by more than 0.1."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
