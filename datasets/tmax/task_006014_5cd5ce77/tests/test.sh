#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import tempfile


def test_source_code_exists():
    assert os.path.isfile("/home/user/mc_spectroscopy.c"), "Source code /home/user/mc_spectroscopy.c is missing."


def test_log_exists():
    assert os.path.isfile("/home/user/mc_regression.log"), "Log file /home/user/mc_regression.log is missing."


def test_kl_divergence_value_and_executable_behavior():
    reference_c_code = r'''
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(void) {
    FILE *f = fopen("/home/user/baseline.txt", "r");
    if (!f) return 1;
    double Q[100];
    double sum_Q = 0;
    for (int i = 0; i < 100; i++) {
        if (fscanf(f, "%lf", &Q[i]) != 1) return 2;
        sum_Q += Q[i];
    }
    fclose(f);

    for (int i = 0; i < 100; i++) Q[i] /= sum_Q;

    srand(42);
    int hits[100] = {0};
    for (int i = 0; i < 10000; i++) {
        double r = (double)rand() / RAND_MAX;
        double cumulative = 0;
        for (int j = 0; j < 100; j++) {
            cumulative += Q[j];
            if (r <= cumulative) {
                hits[j]++;
                break;
            }
        }
    }

    double P[100];
    for (int i = 0; i < 100; i++) P[i] = (double)hits[i] / 10000.0;

    double sum_P_new = 0, sum_Q_new = 0;
    for (int i = 0; i < 100; i++) {
        P[i] += 1e-6;
        Q[i] += 1e-6;
        sum_P_new += P[i];
        sum_Q_new += Q[i];
    }
    for (int i = 0; i < 100; i++) {
        P[i] /= sum_P_new;
        Q[i] /= sum_Q_new;
    }

    double kl = 0;
    for (int i = 0; i < 100; i++) kl += P[i] * log(P[i] / Q[i]);

    printf("KL: %.6f\n", kl);
    return 0;
}
'''

    canonical = [math.exp(-((i - 50) ** 2) / 200.0) + 0.1 for i in range(100)]
    cases = [
        [float(f"{v:.6f}") for v in canonical],
        [float(i + 1) for i in range(100)],
        [0.2 + ((i * 37) % 23) / 10.0 for i in range(100)],
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        ref_src = os.path.join(tmpdir, "ref.c")
        ref_bin = os.path.join(tmpdir, "ref_bin")
        submitted_bin = os.path.join(tmpdir, "mc_spectroscopy")

        with open(ref_src, "w") as f:
            f.write(reference_c_code)

        compile_ref = subprocess.run(
            ["gcc", ref_src, "-o", ref_bin, "-lm"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_ref.returncode == 0, f"Failed to compile reference C code: {compile_ref.stderr}"

        compile_submitted = subprocess.run(
            ["gcc", "/home/user/mc_spectroscopy.c", "-o", submitted_bin, "-lm"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_submitted.returncode == 0, f"Submitted C program did not compile: {compile_submitted.stderr}"

        try:
            for case_number, values in enumerate(cases):
                with open("/home/user/baseline.txt", "w") as f:
                    for value in values:
                        f.write(f"{value:.6f}\n")

                reference_run = subprocess.run(
                    [ref_bin], capture_output=True, text=True, timeout=10
                )
                assert reference_run.returncode == 0, "Failed to execute reference binary."
                expected_output = reference_run.stdout.strip()

                # Restore the exact controlled input in case anything changed it.
                with open("/home/user/baseline.txt", "w") as f:
                    for value in values:
                        f.write(f"{value:.6f}\n")

                if os.path.exists("/home/user/mc_regression.log"):
                    os.remove("/home/user/mc_regression.log")

                submitted_run = subprocess.run(
                    [submitted_bin],
                    cwd="/home/user",
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert submitted_run.returncode == 0, (
                    f"Submitted program failed on test case {case_number}: "
                    f"{submitted_run.stderr}"
                )
                assert os.path.isfile("/home/user/mc_regression.log"), (
                    "Submitted program did not generate /home/user/mc_regression.log"
                )

                with open("/home/user/mc_regression.log", "r") as f:
                    actual_output = f.read().strip()

                assert actual_output == expected_output, (
                    f"Log file content mismatch on test case {case_number}. "
                    f"Expected '{expected_output}', got '{actual_output}'."
                )
        finally:
            with open("/home/user/baseline.txt", "w") as f:
                for value in cases[0]:
                    f.write(f"{value:.6f}\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
