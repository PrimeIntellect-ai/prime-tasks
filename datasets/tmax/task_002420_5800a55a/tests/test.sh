#!/bin/bash
mkdir -p /logs/verifier

TRACE_DIR=$(mktemp -d)
TRACE_LIB="$TRACE_DIR/libkltrace.so"
export TRACE_LIB

cat > "$TRACE_DIR/trace.c" <<'TRACE_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned long long log_calls = 0;

static void count_log(void) {
    __sync_fetch_and_add(&log_calls, 1);
}

double log(double x) {
    static double (*real_log)(double) = NULL;
    if (!real_log) real_log = (double (*)(double))dlsym(RTLD_NEXT, "log");
    count_log();
    return real_log(x);
}

float logf(float x) {
    static float (*real_logf)(float) = NULL;
    if (!real_logf) real_logf = (float (*)(float))dlsym(RTLD_NEXT, "logf");
    count_log();
    return real_logf(x);
}

long double logl(long double x) {
    static long double (*real_logl)(long double) = NULL;
    if (!real_logl) real_logl = (long double (*)(long double))dlsym(RTLD_NEXT, "logl");
    count_log();
    return real_logl(x);
}

__attribute__((destructor))
static void write_counts(void) {
    const char *path = getenv("KL_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "%llu\n", log_calls);
    fclose(f);
}
TRACE_EOF

gcc -shared -fPIC -O2 "$TRACE_DIR/trace.c" -o "$TRACE_LIB" -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import pytest


def p(x):
    return math.exp(-x*x/2.0) / math.sqrt(2.0 * math.pi)


def q(x, nu):
    return math.gamma((nu+1)/2.0) / (math.sqrt(nu * math.pi) * math.gamma(nu/2.0)) * math.pow(1.0 + x*x/nu, -(nu+1)/2.0)


def integrand(x, nu):
    P = p(x)
    Q = q(x, nu)
    return P * math.log((P + 1e-15) / (Q + 1e-15))


def simpsons(nu):
    a = -20.0
    b = 20.0
    N = 100000
    dx = (b - a) / N
    S = integrand(a, nu) + integrand(b, nu)
    for i in range(1, N, 2):
        S += 4.0 * integrand(a + i*dx, nu)
    for i in range(2, N-1, 2):
        S += 2.0 * integrand(a + i*dx, nu)
    return S * dx / 3.0


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission(tmp_path_factory):
    source = "/home/user/kl_div.cpp"
    executable = "/home/user/kl_calc"
    results = "/home/user/results.txt"

    assert os.path.exists(source), f"{source} does not exist"
    assert os.path.isfile(source), f"{source} is not a regular file"

    compile_result = subprocess.run(
        ["g++", "-O3", "-std=c++11", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, "Compilation failed:\n" + compile_result.stderr

    if os.path.exists(results):
        os.remove(results)

    trace_file = str(tmp_path_factory.mktemp("runtime_trace") / "counts.txt")
    env = os.environ.copy()
    env["LD_PRELOAD"] = os.environ["TRACE_LIB"]
    env["KL_TRACE_FILE"] = trace_file
    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, "Compiled program failed:\n" + run_result.stderr
    assert os.path.exists(results), "Running /home/user/kl_calc did not create /home/user/results.txt"
    assert os.path.exists(trace_file), "Could not collect runtime math-call trace"

    with open(trace_file, "r") as f:
        log_calls = int(f.read().strip())
    assert log_calls >= 300000, (
        "The executable did not perform the per-point logarithm evaluations required "
        "for three 100,001-point Simpson integrations"
    )


def test_source_code_exists():
    assert os.path.exists("/home/user/kl_div.cpp"), "/home/user/kl_div.cpp does not exist"


def test_source_contains_required_implementation_elements():
    with open("/home/user/kl_div.cpp", "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\b(?:std::)?tgamma\s*\(", source), "Student's t PDF must use std::tgamma"
    assert re.search(r"\b100000\b", source), "Source does not specify the required 100,000 intervals"
    assert re.search(r"(?:0\.01(?:0*)?|1(?:\.0*)?[eE]-2)", source), "Source does not contain the required h = 0.01"


def test_executable_exists():
    assert os.path.exists("/home/user/kl_calc"), "/home/user/kl_calc does not exist"
    assert os.access("/home/user/kl_calc", os.X_OK), "/home/user/kl_calc is not executable"


def test_results_file_and_values():
    results_path = "/home/user/results.txt"
    assert os.path.exists(results_path), f"{results_path} does not exist"

    with open(results_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {results_path}, found {len(lines)}"
    number_format = re.compile(r"^[+-]?\d+\.\d{6}$")
    assert number_format.fullmatch(lines[0]), "First result is not formatted to exactly 6 decimal places"
    assert number_format.fullmatch(lines[1]), "Second result is not formatted to exactly 6 decimal places"

    try:
        kl_val = float(lines[0])
        deriv_val = float(lines[1])
    except ValueError:
        assert False, "Could not parse the outputs as floats"
    assert math.isfinite(kl_val) and math.isfinite(deriv_val), "Outputs must be finite"

    kl_3 = simpsons(3.0)
    kl_301 = simpsons(3.01)
    kl_299 = simpsons(2.99)
    expected_deriv = (kl_301 - kl_299) / 0.02

    assert abs(kl_val - kl_3) <= 2e-6, f"Expected KL divergence to be approx {kl_3:.6f}, got {kl_val}"
    assert abs(deriv_val - expected_deriv) <= 2e-6, f"Expected derivative to be approx {expected_deriv:.6f}, got {deriv_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$TRACE_DIR"
