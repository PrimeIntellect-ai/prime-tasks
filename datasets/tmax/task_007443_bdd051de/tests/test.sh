#!/bin/bash
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/reference_fit_sampler.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_linalg.h>
#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>

static double log_likelihood(const double *x, const double *y, const double *b) {
    double sse = 0.0;
    for (int i = 0; i < 50; ++i) {
        double e = y[i] - (b[0] + b[1] * x[i] + b[2] * x[i] * x[i]);
        sse += e * e;
    }
    return -0.5 * sse;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 2;

    double x[50], y[50];
    for (int i = 0; i < 50; ++i) {
        if (fscanf(f, "%lf,%lf", &x[i], &y[i]) != 2) {
            fclose(f);
            return 2;
        }
    }
    fclose(f);

    gsl_matrix *v = gsl_matrix_alloc(50, 3);
    gsl_vector *response = gsl_vector_alloc(50);
    gsl_vector *tau = gsl_vector_alloc(3);
    gsl_vector *beta = gsl_vector_alloc(3);
    gsl_vector *residual = gsl_vector_alloc(50);
    if (!v || !response || !tau || !beta || !residual) return 2;

    for (int i = 0; i < 50; ++i) {
        gsl_matrix_set(v, i, 0, 1.0);
        gsl_matrix_set(v, i, 1, x[i]);
        gsl_matrix_set(v, i, 2, x[i] * x[i]);
        gsl_vector_set(response, i, y[i]);
    }

    if (gsl_linalg_QR_decomp(v, tau) != 0 ||
        gsl_linalg_QR_lssolve(v, tau, response, beta, residual) != 0) return 2;

    double ols[3], state[3], sum[3] = {0.0, 0.0, 0.0};
    for (int j = 0; j < 3; ++j) ols[j] = state[j] = gsl_vector_get(beta, j);

    gsl_rng *r = gsl_rng_alloc(gsl_rng_mt19937);
    if (!r) return 2;
    gsl_rng_set(r, 42);
    double current_ll = log_likelihood(x, y, state);

    for (int t = 1; t <= 10000; ++t) {
        double proposal[3];
        proposal[0] = state[0] + gsl_ran_gaussian(r, 0.1);
        proposal[1] = state[1] + gsl_ran_gaussian(r, 0.1);
        proposal[2] = state[2] + gsl_ran_gaussian(r, 0.1);
        double u = gsl_rng_uniform(r);
        double proposal_ll = log_likelihood(x, y, proposal);

        if (log(u) < proposal_ll - current_ll) {
            for (int j = 0; j < 3; ++j) state[j] = proposal[j];
            current_ll = proposal_ll;
        }
        if (t > 1000) {
            for (int j = 0; j < 3; ++j) sum[j] += state[j];
        }
    }

    printf("OLS: beta0=%.4f, beta1=%.4f, beta2=%.4f\n",
           ols[0], ols[1], ols[2]);
    printf("MCMC: beta0=%.4f, beta1=%.4f, beta2=%.4f\n",
           sum[0] / 9000.0, sum[1] / 9000.0, sum[2] / 9000.0);

    gsl_rng_free(r);
    gsl_vector_free(residual);
    gsl_vector_free(beta);
    gsl_vector_free(tau);
    gsl_vector_free(response);
    gsl_matrix_free(v);
    return 0;
}
REF_EOF

cat << 'PY_EOF' > /tmp/verify_fit_sampler.py
import math
import os
import random
import re
import secrets
import subprocess

SOURCE = "/home/user/fit_sampler.c"
DATA = "/home/user/data.csv"
RESULTS = "/home/user/results.txt"
BINARY = "/tmp/submitted_fit_sampler"
REFERENCE = "/tmp/reference_fit_sampler"

pattern_ols = re.compile(r"OLS:\s*beta0=([^,]+),\s*beta1=([^,]+),\s*beta2=([^\s]+)")
pattern_mcmc = re.compile(r"MCMC:\s*beta0=([^,]+),\s*beta1=([^,]+),\s*beta2=([^\s]+)")

def parse_results(content):
    ols_match = pattern_ols.search(content)
    mcmc_match = pattern_mcmc.search(content)
    assert ols_match is not None, "OLS line not found or formatted incorrectly in results.txt."
    assert mcmc_match is not None, "MCMC line not found or formatted incorrectly in results.txt."
    values = tuple(float(x) for x in ols_match.groups() + mcmc_match.groups())
    assert all(math.isfinite(x) for x in values), "Results contain non-finite values."
    return values

def check_original_assertions(content):
    values = parse_results(content)
    ols_b0, ols_b1, ols_b2, mcmc_b0, mcmc_b1, mcmc_b2 = values
    assert abs(ols_b0 - 1.4883) < 0.005, f"OLS beta0 is incorrect: {ols_b0}"
    assert abs(ols_b1 - (-0.8268)) < 0.005, f"OLS beta1 is incorrect: {ols_b1}"
    assert abs(ols_b2 - 0.2037) < 0.005, f"OLS beta2 is incorrect: {ols_b2}"
    assert abs(mcmc_b0 - ols_b0) < 0.1, f"MCMC beta0 ({mcmc_b0}) is too far from OLS beta0 ({ols_b0})"
    assert abs(mcmc_b1 - ols_b1) < 0.1, f"MCMC beta1 ({mcmc_b1}) is too far from OLS beta1 ({ols_b1})"
    assert abs(mcmc_b2 - ols_b2) < 0.1, f"MCMC beta2 ({mcmc_b2}) is too far from OLS beta2 ({ols_b2})"
    return values

def run_submission(data_bytes):
    with open(DATA, "wb") as f:
        f.write(data_bytes)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=25,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.isfile(RESULTS), "The compiled program did not create /home/user/results.txt."
    with open(DATA, "rb") as f:
        assert f.read() == data_bytes, "The program modified the input data."
    with open(RESULTS, "r") as f:
        content = f.read()
    return content, parse_results(content)

def reference_values(data_bytes):
    with open(DATA, "wb") as f:
        f.write(data_bytes)
    out = subprocess.run([REFERENCE, DATA], check=True, timeout=25,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True).stdout
    return parse_results(out)

def assert_matches_reference(actual, expected):
    for name, got, want in zip(
        ("OLS beta0", "OLS beta1", "OLS beta2", "MCMC beta0", "MCMC beta1", "MCMC beta2"),
        actual, expected
    ):
        assert abs(got - want) <= 0.00011, f"{name} is incorrect: got {got:.4f}, expected {want:.4f}"

def random_dataset():
    rng = random.Random(secrets.randbits(256))
    xs = sorted(rng.uniform(-5.0, 5.0) for _ in range(50))
    b = [rng.uniform(-2.5, 2.5), rng.uniform(-1.5, 1.5), rng.uniform(-0.4, 0.4)]
    rows = []
    for x in xs:
        y = b[0] + b[1] * x + b[2] * x * x + rng.gauss(0.0, 1.0)
        rows.append(f"{x:.6f},{y:.6f}\n")
    return "".join(rows).encode()

# Preserve the verifier's original existence and results assertions.
assert os.path.isfile(RESULTS), "The file /home/user/results.txt does not exist."
assert os.path.isfile(SOURCE), "The file /home/user/fit_sampler.c does not exist."
assert os.path.getsize(SOURCE) > 0, "The C source file is empty."
with open(RESULTS, "r") as f:
    check_original_assertions(f.read())

with open(SOURCE, "r", errors="replace") as f:
    source_text = f.read()
for required in (
    "gsl_linalg_QR_decomp", "gsl_linalg_QR_lssolve", "gsl_rng_mt19937",
    "gsl_rng_set", "gsl_ran_gaussian", "gsl_rng_uniform"
):
    assert required in source_text, f"The source does not use required GSL API {required}."

original_data = open(DATA, "rb").read()
original_result_after_run = None
try:
    subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lgsl", "-lgslcblas", "-lm"],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    subprocess.run(
        ["gcc", "/tmp/reference_fit_sampler.c", "-o", REFERENCE,
         "-lgsl", "-lgslcblas", "-lm"],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    content, actual = run_submission(original_data)
    check_original_assertions(content)
    expected = reference_values(original_data)
    assert_matches_reference(actual, expected)
    original_result_after_run = content.encode()

    for _ in range(2):
        generated = random_dataset()
        expected = reference_values(generated)
        _, actual = run_submission(generated)
        assert_matches_reference(actual, expected)

    # Restore the seed data and leave results produced by the submitted program for it.
    final_content, final_actual = run_submission(original_data)
    check_original_assertions(final_content)
    assert_matches_reference(final_actual, reference_values(original_data))
finally:
    with open(DATA, "wb") as f:
        f.write(original_data)
    if original_result_after_run is not None and not os.path.isfile(RESULTS):
        with open(RESULTS, "wb") as f:
            f.write(original_result_after_run)
PY_EOF

if python3 /tmp/verify_fit_sampler.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
