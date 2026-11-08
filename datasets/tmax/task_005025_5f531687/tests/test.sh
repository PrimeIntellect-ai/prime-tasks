#!/bin/bash
set -e
mkdir -p /logs/verifier

WORK=$(mktemp -d)
cp /home/user/genomic_signals.txt "$WORK/original.txt"

cleanup() {
    cp "$WORK/original.txt" /home/user/genomic_signals.txt 2>/dev/null || true
    if [ -x /home/user/analyze_motifs ]; then
        timeout 30s /home/user/analyze_motifs >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

run_checks() {
    test -f /home/user/analyze_motifs.c || return 1

    gcc -O2 /home/user/analyze_motifs.c -lgsl -lgslcblas -lm -o /home/user/analyze_motifs || return 1
    test -x /home/user/analyze_motifs || return 1

    # Confirm that the compiled submission actually references the required GSL APIs.
    nm -D /home/user/analyze_motifs | grep -q ' U gsl_linalg_SV_decomp' || return 1
    nm -D /home/user/analyze_motifs | grep -q ' U gsl_rng_uniform_int' || return 1
    nm -D /home/user/analyze_motifs | grep -q ' U gsl_rng_set' || return 1

    rm -f /home/user/motif_results.txt
    timeout 30s /home/user/analyze_motifs || return 1

    cat << 'TEST_EOF' > "$WORK/test_original.py"
import os
import re

def test_source_code_exists():
    assert os.path.isfile("/home/user/analyze_motifs.c"), "C source file /home/user/analyze_motifs.c is missing."

def test_results_file_exists():
    assert os.path.isfile("/home/user/motif_results.txt"), "Results file /home/user/motif_results.txt is missing."

def test_results_content():
    with open("/home/user/motif_results.txt", "r") as f:
        content = f.read().strip()

    sigma1_match = re.search(r"Smoothed Sigma1:\s*([0-9.]+)", content)
    assert sigma1_match is not None, "Could not find 'Smoothed Sigma1: [Value]' in the results file."

    ci_match = re.search(r"Bootstrap 95% CI:\s*\[([0-9.]+),\s*([0-9.]+)\]", content)
    assert ci_match is not None, "Could not find 'Bootstrap 95% CI: [[Lower], [Upper]]' in the results file."

    sigma1 = float(sigma1_match.group(1))
    lower = float(ci_match.group(1))
    upper = float(ci_match.group(2))

    assert 44.4924 <= sigma1 <= 44.4926, f"Smoothed Sigma1 {sigma1} is out of expected range [44.4924, 44.4926]."
    assert 38.2 <= lower <= 40.5, f"Bootstrap CI Lower bound {lower} is out of expected range [38.2, 40.5]."
    assert 48.5 <= upper <= 50.5, f"Bootstrap CI Upper bound {upper} is out of expected range [48.5, 50.5]."
TEST_EOF
    python3 -m pytest "$WORK/test_original.py" -x --tb=short || return 1

    python3 - "$WORK" << 'PY'
import math
import os
import sys
import numpy as np

work = sys.argv[1]

case1 = np.empty((50, 20), dtype=float)
for i in range(50):
    for j in range(20):
        case1[i, j] = (1.7 * math.sin((i + 1) * (j + 2) * 0.071)
                       + 0.035 * i - 0.09 * j
                       + 3.2 * math.cos(i * 0.11) * math.sin(j * 0.27))

rng = np.random.RandomState(8675309)
case2 = rng.normal(-0.35, 1.25, size=(50, 20))
u = np.linspace(-2.0, 1.5, 50)
v = np.cos(np.linspace(0.2, 7.4, 20))
case2 += 2.75 * np.outer(u, v)

for name, matrix in (("case1.txt", case1), ("case2.txt", case2)):
    with open(os.path.join(work, name), "w") as f:
        for row in matrix:
            f.write(" ".join(f"{x:.9f}" for x in row) + "\n")
PY

    cat << 'REF_EOF' > "$WORK/reference.c"
#include <stdio.h>
#include <stdlib.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_linalg.h>
#include <gsl/gsl_rng.h>

#define ROWS 50
#define COLS 20
#define BOOTS 1000

static double largest_sv(const double a[ROWS][COLS]) {
    gsl_matrix *m = gsl_matrix_alloc(ROWS, COLS);
    gsl_matrix *v = gsl_matrix_alloc(COLS, COLS);
    gsl_vector *s = gsl_vector_alloc(COLS);
    gsl_vector *work = gsl_vector_alloc(COLS);
    if (!m || !v || !s || !work) exit(20);
    for (size_t i = 0; i < ROWS; ++i)
        for (size_t j = 0; j < COLS; ++j)
            gsl_matrix_set(m, i, j, a[i][j]);
    if (gsl_linalg_SV_decomp(m, v, s, work) != 0) exit(21);
    double answer = gsl_vector_get(s, 0);
    gsl_vector_free(work);
    gsl_vector_free(s);
    gsl_matrix_free(v);
    gsl_matrix_free(m);
    return answer;
}

static int cmp_double(const void *aa, const void *bb) {
    double a = *(const double *)aa;
    double b = *(const double *)bb;
    return (a > b) - (a < b);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 3;
    double x[ROWS][COLS], smooth[ROWS][COLS], sample[ROWS][COLS];
    double boot[BOOTS];
    for (int i = 0; i < ROWS; ++i)
        for (int j = 0; j < COLS; ++j)
            if (fscanf(f, "%lf", &x[i][j]) != 1) return 4;
    fclose(f);

    for (int i = 0; i < ROWS; ++i) {
        for (int j = 0; j < COLS; ++j) {
            double left = x[i][j == 0 ? 0 : j - 1];
            double right = x[i][j == COLS - 1 ? COLS - 1 : j + 1];
            smooth[i][j] = (left + x[i][j] + right) / 3.0;
        }
    }

    double sigma = largest_sv(smooth);
    gsl_rng *r = gsl_rng_alloc(gsl_rng_mt19937);
    if (!r) return 5;
    gsl_rng_set(r, 42);
    for (int b = 0; b < BOOTS; ++b) {
        for (int i = 0; i < ROWS; ++i) {
            unsigned long pick = gsl_rng_uniform_int(r, ROWS);
            for (int j = 0; j < COLS; ++j)
                sample[i][j] = smooth[pick][j];
        }
        boot[b] = largest_sv(sample);
    }
    gsl_rng_free(r);
    qsort(boot, BOOTS, sizeof(double), cmp_double);
    printf("Smoothed Sigma1: %.4f\n", sigma);
    printf("Bootstrap 95%% CI: [%.4f, %.4f]\n", boot[24], boot[974]);
    return 0;
}
REF_EOF

    gcc -O2 "$WORK/reference.c" -lgsl -lgslcblas -lm -o "$WORK/reference" || return 1
    "$WORK/reference" "$WORK/original.txt" > "$WORK/expected_original.txt" || return 1
    "$WORK/reference" "$WORK/case1.txt" > "$WORK/expected_case1.txt" || return 1
    "$WORK/reference" "$WORK/case2.txt" > "$WORK/expected_case2.txt" || return 1
    rm -f "$WORK/reference" "$WORK/reference.c"

    export WORK
    python3 - << 'PY' || return 1
import math
import os
import re
import shutil
import subprocess

work = os.environ["WORK"]
result_path = "/home/user/motif_results.txt"
input_path = "/home/user/genomic_signals.txt"
pattern = re.compile(
    r"\ASmoothed Sigma1:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*\n"
    r"Bootstrap 95% CI:\s*\[\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*"
    r"([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*\]\s*\Z"
)

def parse(path):
    with open(path, "r") as f:
        text = f.read()
    match = pattern.match(text)
    assert match is not None, f"Incorrect results format in {path}: {text!r}"
    values = tuple(float(x) for x in match.groups())
    assert all(math.isfinite(x) for x in values), "Results must be finite numbers"
    return values

cases = [
    ("original.txt", "expected_original.txt"),
    ("case1.txt", "expected_case1.txt"),
    ("case2.txt", "expected_case2.txt"),
]

for data_name, expected_name in cases:
    expected = parse(os.path.join(work, expected_name))
    shutil.copyfile(os.path.join(work, data_name), input_path)
    try:
        os.unlink(result_path)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        ["/home/user/analyze_motifs"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, (
        f"Program failed on {data_name} with exit code {completed.returncode}: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(result_path), "Program did not create /home/user/motif_results.txt"
    actual = parse(result_path)
    for label, got, want in zip(("sigma1", "CI lower", "CI upper"), actual, expected):
        assert abs(got - want) <= 0.00011, (
            f"Incorrect {label} on {data_name}: got {got:.4f}, expected {want:.4f}"
        )
PY

    cp "$WORK/original.txt" /home/user/genomic_signals.txt || return 1
    rm -f /home/user/motif_results.txt
    timeout 30s /home/user/analyze_motifs || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
