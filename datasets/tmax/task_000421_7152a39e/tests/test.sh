#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/reference_mcmc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 1000000
#define ITERS 5000

static float reference_sse(float *x, float *y, int n, float m, float c) {
    float sum = 0.0f;
    float compensation = 0.0f;
    for (int i = 0; i < n; i++) {
        float pred = m * x[i] + c;
        float err = y[i] - pred;
        float term = err * err;
        float adjusted = term - compensation;
        float next = sum + adjusted;
        compensation = (next - sum) - adjusted;
        sum = next;
    }
    return sum;
}

int main(void) {
    float *x = malloc(N * sizeof(float));
    float *y = malloc(N * sizeof(float));
    if (!x || !y) return 1;

    FILE *fp = fopen("/home/user/data.csv", "r");
    if (!fp) return 1;
    for (int i = 0; i < N; i++) {
        if (fscanf(fp, "%f,%f", &x[i], &y[i]) != 2) return 1;
    }
    fclose(fp);

    srand(12345);
    float current_m = 0.0f;
    float current_c = 0.0f;
    float current_sse = reference_sse(x, y, N, current_m, current_c);
    float sum_m = 0.0f;
    float sum_c = 0.0f;
    int accepted = 0;

    for (int i = 0; i < ITERS; i++) {
        float prop_m = current_m + ((float)rand() / RAND_MAX - 0.5f) * 0.1f;
        float prop_c = current_c + ((float)rand() / RAND_MAX - 0.5f) * 0.1f;
        float prop_sse = reference_sse(x, y, N, prop_m, prop_c);
        float alpha = expf(-0.0001f * (prop_sse - current_sse));
        if (((float)rand() / RAND_MAX) < alpha) {
            current_m = prop_m;
            current_c = prop_c;
            current_sse = prop_sse;
        }
        if (i >= ITERS / 2) {
            sum_m += current_m;
            sum_c += current_c;
            accepted++;
        }
    }

    printf("m=%.4f,c=%.4f\n", sum_m / accepted, sum_c / accepted);
    free(x);
    free(y);
    return 0;
}
REF_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import struct
import subprocess
import pytest

SOURCE = "/home/user/mcmc_fit.c"
POSTERIOR = "/home/user/posterior.txt"
BINARY = "/home/user/mcmc_fit"


def run_checked(command, timeout=600, cwd=None):
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


@pytest.fixture(scope="session")
def executions():
    run_checked(["gcc", "-O2", "-o", BINARY, SOURCE, "-lm"])
    run_checked(["gcc", "-O2", "-o", "/tmp/reference_mcmc", "/tmp/reference_mcmc.c", "-lm"])
    run_checked([
        "gcc", "-O2", "-shared", "-fPIC", "-Dmain=mcmc_program_main",
        "-o", "/tmp/submission.so", SOURCE, "-lm"
    ])

    reference = run_checked(["/tmp/reference_mcmc"]).stdout.strip()
    submission = run_checked([BINARY], cwd="/home/user").stdout.strip()
    return reference, submission


def test_posterior_txt_exists():
    """Test that the posterior.txt file exists."""
    assert os.path.isfile(POSTERIOR), f"File {POSTERIOR} is missing. Did you create it?"


def test_posterior_values():
    """Retain the original format and broad posterior checks."""
    with open(POSTERIOR, "r") as f:
        content = f.read().strip()

    match = re.match(r'^m=([0-9\.\-]+),c=([0-9\.\-]+)$', content)
    assert match is not None, (
        f"Content of {POSTERIOR} is not in the expected format "
        f"'m=<value>,c=<value>'. Found: {content}"
    )
    m_val = float(match.group(1))
    c_val = float(match.group(2))
    assert 3.10 <= m_val <= 3.20, f"Value of m ({m_val}) is not within the expected range."
    assert 2.65 <= c_val <= 2.80, f"Value of c ({c_val}) is not within the expected range."


def test_mcmc_fit_c_kahan_implementation():
    """Retain the original source assertions."""
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "float compute_sse(float* x, float* y, int n, float m, float c)" in content, \
        "The compute_sse function signature was changed. It must remain the same."

    lines = content.split('\n')
    in_compute_sse = False
    loop_lines = []
    for line in lines:
        if "float compute_sse" in line:
            in_compute_sse = True
        if in_compute_sse:
            loop_lines.append(line)
            if "return" in line:
                break

    compute_sse_body = "\n".join(loop_lines)
    assignments = compute_sse_body.count('=')
    assert assignments >= 5, "compute_sse does not seem to contain the Kahan summation algorithm (not enough operations)."


def f32(value):
    return struct.unpack("=f", struct.pack("=f", value))[0]


def kahan_expected(values):
    total = f32(0.0)
    compensation = f32(0.0)
    for value in values:
        term = f32(f32(value) * f32(value))
        adjusted = f32(term - compensation)
        next_total = f32(total + adjusted)
        compensation = f32(f32(next_total - total) - adjusted)
        total = next_total
    return total


def test_compute_sse_numerically_uses_compensated_reduction(executions):
    """Exercise the submitted function on an input where naive float reduction loses terms."""
    lib = ctypes.CDLL("/tmp/submission.so")
    func = lib.compute_sse
    func.argtypes = [
        ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float),
        ctypes.c_int, ctypes.c_float, ctypes.c_float,
    ]
    func.restype = ctypes.c_float

    values = [4096.0] + [1.0] * 10000
    n = len(values)
    x = (ctypes.c_float * n)(*([0.0] * n))
    y = (ctypes.c_float * n)(*values)
    actual = func(x, y, n, ctypes.c_float(0.0), ctypes.c_float(0.0))
    expected = kahan_expected(values)
    assert struct.pack("=f", actual) == struct.pack("=f", expected), (
        f"compute_sse returned {actual}, but float Kahan summation returns {expected}"
    )
    assert actual != f32(4096.0 * 4096.0), "Small SSE terms were lost as in the original naive loop."


def test_compiled_program_and_posterior_match_reference(executions):
    """Run the compiled submission and compare its result with an independently derived Kahan result."""
    reference, submission = executions
    exact_format = r"^m=-?\d+\.\d{4},c=-?\d+\.\d{4}$"
    assert re.fullmatch(exact_format, submission), f"Unexpected program output: {submission!r}"
    assert submission == reference, (
        f"Compiled program output {submission!r} does not match the independently computed result {reference!r}"
    )
    with open(POSTERIOR, "r") as f:
        posterior = f.read().strip()
    assert posterior == submission, (
        f"posterior.txt contains {posterior!r}, but the fixed compiled program outputs {submission!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
