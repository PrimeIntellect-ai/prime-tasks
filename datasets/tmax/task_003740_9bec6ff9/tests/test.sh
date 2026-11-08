#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile
import secrets
import pytest

SOURCE = "/home/user/mcmc_primer.c"
BINARY = "/home/user/mcmc_primer"
TARGET = "/home/user/target.txt"
RESULT = "/home/user/result.log"

REFERENCE_CODE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

float integrate_spectral_energy(float* energy_array, int n) {
    float sum = 0.0f;
    float c = 0.0f;
    for(int i=0; i<n; i++) {
        float y = energy_array[i] - c;
        float t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    return sum;
}

void generate_spectrum(const char* primer, float* out_array, int n) {
    float base_val = 0.0f;
    for(int i=0; i<8; i++) {
        base_val += (float)(primer[i] * (i+1));
    }
    for(int i=0; i<n; i++) {
        if (i % 2 == 0) out_array[i] = 10000.0f;
        else out_array[i] = -10000.0f + (base_val * 0.0001f);
    }
}

int main(void) {
    srand(42);
    char current_primer[9] = "AAAAAAAA";
    float best_score = -1e9;
    char best_primer[9] = "AAAAAAAA";
    int n_points = 50000;
    float* spectrum = malloc(n_points * sizeof(float));
    if (!spectrum) return 2;

    for(int step=0; step<1000; step++) {
        char proposed_primer[9];
        strcpy(proposed_primer, current_primer);
        int mut_idx = rand() % 8;
        char bases[] = "ATCG";
        proposed_primer[mut_idx] = bases[rand() % 4];
        generate_spectrum(proposed_primer, spectrum, n_points);
        float score = integrate_spectral_energy(spectrum, n_points);
        if(score > best_score) {
            best_score = score;
            strcpy(best_primer, proposed_primer);
            strcpy(current_primer, proposed_primer);
        }
    }
    printf("Best Primer: %s\n", best_primer);
    printf("Score: %.4f\n", best_score);
    free(spectrum);
    return 0;
}
'''

HARNESS_CODE = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

float integrate_spectral_energy(float*, int);

static uint32_t state;
static uint32_t next_u32(void) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static float reference_kahan(const float *a, int n) {
    float sum = 0.0f;
    float c = 0.0f;
    for (int i = 0; i < n; ++i) {
        float y = a[i] - c;
        float t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    return sum;
}

static uint32_t bits(float x) {
    uint32_t u;
    memcpy(&u, &x, sizeof(u));
    return u;
}

int main(int argc, char **argv) {
    if (argc != 2) return 90;
    state = (uint32_t)strtoul(argv[1], NULL, 10);
    if (state == 0) state = 0x9e3779b9u;

    for (int trial = 0; trial < 12; ++trial) {
        int n = 3003 + (int)(next_u32() % 2500u);
        float *a = malloc((size_t)n * sizeof(float));
        if (!a) return 91;

        a[0] = (trial & 1) ? 10000000.0f : -10000000.0f;
        a[n-1] = -a[0];
        for (int i = 1; i < n-1; ++i) {
            int v = (int)(next_u32() % 2001u) - 1000;
            a[i] = (float)v / 1024.0f;
        }
        for (int i = n-1; i > 0; --i) {
            int j = (int)(next_u32() % (uint32_t)(i + 1));
            float tmp = a[i]; a[i] = a[j]; a[j] = tmp;
        }

        float expected = reference_kahan(a, n);
        float actual = integrate_spectral_energy(a, n);
        if (bits(expected) != bits(actual)) {
            fprintf(stderr, "trial %d mismatch: expected bits %08x, got %08x\n",
                    trial, bits(expected), bits(actual));
            free(a);
            return 1;
        }
        free(a);
    }

    float empty = integrate_spectral_energy(NULL, 0);
    if (bits(empty) != bits(0.0f)) return 2;
    return 0;
}
'''


def compile_program(source, output, extra=None):
    cmd = ["gcc", source, "-o", output, "-lm"]
    if extra:
        cmd[1:1] = extra
    subprocess.run(cmd, check=True, capture_output=True, text=True)


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    td = str(tmp_path_factory.mktemp("build"))
    ref_src = os.path.join(td, "reference.c")
    ref_exe = os.path.join(td, "reference")
    fresh_exe = os.path.join(td, "submitted")
    with open(ref_src, "w") as f:
        f.write(REFERENCE_CODE)
    compile_program(ref_src, ref_exe)
    compile_program(SOURCE, fresh_exe)
    expected = subprocess.run([ref_exe], capture_output=True, check=True, timeout=20).stdout
    return td, fresh_exe, expected


def get_expected_output():
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "test.c")
        exe = os.path.join(td, "test_exe")
        with open(src, "w") as f:
            f.write(REFERENCE_CODE)
        compile_program(src, exe)
        result = subprocess.run([exe], capture_output=True, text=True, check=True, timeout=20)
        return result.stdout.strip()


def test_result_log_exists_and_correct():
    assert os.path.isfile(RESULT), f"Missing result file: {RESULT}"
    with open(RESULT, "r") as f:
        content = f.read().strip()
    expected_output = get_expected_output()
    assert expected_output in content, (
        f"The content of {RESULT} does not match the expected output of the Kahan-summed MCMC sampler.\n"
        f"Expected to find:\n{expected_output}\nBut found:\n{content}"
    )


def test_mcmc_primer_c_uses_kahan():
    assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()
    start_idx = content.find("float integrate_spectral_energy")
    assert start_idx != -1, "Could not find integrate_spectral_energy function"
    end_idx = content.find("}", start_idx)
    func_body = content[start_idx:end_idx]
    assert "-" in func_body, "Kahan summation requires subtraction to compute the compensation error."
    assert "+" in func_body, "Kahan summation requires addition."
    assignments = func_body.count("=")
    assert assignments >= 4, "Kahan summation requires multiple assignments inside the loop to track sum, error, and temporary values."


def test_compiled_artifact_and_exact_run(built):
    _, fresh_exe, expected = built
    assert os.path.isfile(BINARY), f"Missing compiled program: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled program is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mcmc_primer must be a compiled ELF executable"

    artifact_run = subprocess.run(
        [BINARY, TARGET, "42"], cwd="/home/user", capture_output=True,
        check=True, timeout=20
    )
    fresh_run = subprocess.run(
        [fresh_exe, TARGET, "42"], cwd="/home/user", capture_output=True,
        check=True, timeout=20
    )
    assert artifact_run.stderr == b""
    assert fresh_run.stderr == b""
    assert artifact_run.stdout == expected
    assert fresh_run.stdout == expected
    with open(RESULT, "rb") as f:
        assert f.read() == artifact_run.stdout, "result.log must be the exact standard output of the required run"


def test_integration_matches_kahan_on_unseen_inputs(built):
    td, _, _ = built
    obj = os.path.join(td, "submission.o")
    harness_src = os.path.join(td, "harness.c")
    harness_obj = os.path.join(td, "harness.o")
    harness_exe = os.path.join(td, "harness")

    subprocess.run(
        ["gcc", "-Dmain=submission_main", "-c", SOURCE, "-o", obj],
        check=True, capture_output=True, text=True
    )
    with open(harness_src, "w") as f:
        f.write(HARNESS_CODE)
    subprocess.run(["gcc", "-c", harness_src, "-o", harness_obj], check=True,
                   capture_output=True, text=True)
    subprocess.run(["gcc", obj, harness_obj, "-o", harness_exe, "-lm"], check=True,
                   capture_output=True, text=True)

    seed = secrets.randbits(32) or 1
    subprocess.run([harness_exe, str(seed)], check=True, capture_output=True,
                   text=True, timeout=20)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
