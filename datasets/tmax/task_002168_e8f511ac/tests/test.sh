#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

GOLDEN_C_CODE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
    double x, y;
} Point;

int main() {
    FILE *f = fopen("/home/user/dataset.csv", "r");
    if (!f) return 1;
    char line[256];
    Point points[100];
    int count = 0;

    fgets(line, sizeof(line), f);
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "?") != NULL) continue;
        sscanf(line, "%lf,%lf", &points[count].x, &points[count].y);
        count++;
    }
    fclose(f);

    double sum_x = 0, sum_y = 0;
    for (int i = 0; i < count; i++) {
        sum_x += points[i].x;
        sum_y += points[i].y;
    }
    double mean_x = sum_x / count;
    double mean_y = sum_y / count;

    double dists[100];
    double sum_dist = 0;
    for (int i = 0; i < count; i++) {
        dists[i] = sqrt(pow(points[i].x - mean_x, 2) + pow(points[i].y - mean_y, 2));
        sum_dist += dists[i];
    }
    double mean_dist = sum_dist / count;

    double sum_sq_diff = 0;
    for (int i = 0; i < count; i++) {
        sum_sq_diff += pow(dists[i] - mean_dist, 2);
    }
    double std_dist = sqrt(sum_sq_diff / count);

    Point cleaned[100];
    int clean_count = 0;
    for (int i = 0; i < count; i++) {
        if (dists[i] <= mean_dist + 2.0 * std_dist) {
            cleaned[clean_count++] = points[i];
        }
    }

    srand(42);
    double sum_corr = 0;
    int N = clean_count;

    for (int iter = 0; iter < 10000; iter++) {
        Point sample[100];
        double sx = 0, sy = 0;
        for (int i = 0; i < N; i++) {
            int idx = rand() % N;
            sample[i] = cleaned[idx];
            sx += sample[i].x;
            sy += sample[i].y;
        }
        double mx = sx / N, my = sy / N;

        double num = 0, den_x = 0, den_y = 0;
        for (int i = 0; i < N; i++) {
            double dx = sample[i].x - mx;
            double dy = sample[i].y - my;
            num += dx * dy;
            den_x += dx * dx;
            den_y += dy * dy;
        }

        double corr = 0;
        if (den_x > 0 && den_y > 0) {
            corr = num / sqrt(den_x * den_y);
        }
        sum_corr += corr;
    }

    printf("%.4f\n", sum_corr / 10000.0);
    return 0;
}
'''

DATASET = "/home/user/dataset.csv"
SOURCE = "/home/user/prepare_data.c"
OUTPUT = "/home/user/robust_corr.txt"


def compile_c(source, executable):
    proc = subprocess.run(
        ["gcc", str(source), "-o", str(executable), "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Failed to compile {source}: {proc.stderr}"


def test_c_program_exists():
    assert os.path.isfile(SOURCE), "The required C program /home/user/prepare_data.c is missing."


def test_robust_corr_exists():
    assert os.path.isfile(OUTPUT), "The output file /home/user/robust_corr.txt is missing."


def test_robust_corr_value(tmp_path):
    c_file = tmp_path / "golden.c"
    c_file.write_text(GOLDEN_C_CODE)

    exe_file = tmp_path / "golden"
    compile_c(c_file, exe_file)

    run_proc = subprocess.run([str(exe_file)], capture_output=True, text=True, timeout=20)
    assert run_proc.returncode == 0, "Failed to run golden C code in test."
    expected_value = run_proc.stdout.strip()

    with open(OUTPUT, "r") as f:
        actual_value = f.read().strip()

    assert actual_value == expected_value, (
        f"Expected correlation {expected_value}, but got {actual_value} in {OUTPUT}"
    )


def make_dataset(kind):
    rows = ["X,Y"]
    offset = secrets.randbelow(100000) / 997.0
    for i in range(1, 29):
        x = offset + i * 0.73 + secrets.randbelow(1000) / 10000.0
        if kind == 0:
            y = 1.4 * x + ((i % 5) - 2) * 0.41 + (i * i % 7) * 0.09
        else:
            y = -0.65 * x + ((i % 6) - 3) * 1.17 + (i * i % 11) * 0.13
        rows.append(f"{x:.8f},{y:.8f}")
    rows.insert(5, "?,12.5")
    rows.insert(14, "3.25,?")
    rows.append(f"{offset + 50000.0:.8f},{offset - 70000.0:.8f}")
    return "\n".join(rows) + "\n"


def test_submitted_program_compiles_runs_and_handles_unseen_inputs(tmp_path):
    golden_source = tmp_path / "golden.c"
    golden_source.write_text(GOLDEN_C_CODE)
    golden_exe = tmp_path / "golden"
    submitted_exe = tmp_path / "prepare_data"
    compile_c(golden_source, golden_exe)
    compile_c(SOURCE, submitted_exe)

    original_dataset = open(DATASET, "rb").read()
    original_output = open(OUTPUT, "rb").read()
    datasets = [original_dataset.decode(), make_dataset(0), make_dataset(1)]

    try:
        for dataset in datasets:
            with open(DATASET, "w") as f:
                f.write(dataset)

            golden_run = subprocess.run(
                [str(golden_exe)], capture_output=True, text=True, timeout=20
            )
            assert golden_run.returncode == 0, "Golden program failed on a test dataset."
            expected = golden_run.stdout.strip()

            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            submitted_run = subprocess.run(
                [str(submitted_exe)], capture_output=True, text=True, timeout=20,
                cwd="/home/user"
            )
            assert submitted_run.returncode == 0, (
                f"Submitted program exited with {submitted_run.returncode}: "
                f"{submitted_run.stderr}"
            )
            assert os.path.isfile(OUTPUT), "Submitted program did not create robust_corr.txt."
            actual_raw = open(OUTPUT, "r").read()
            actual = actual_raw.strip()
            assert re.fullmatch(r"[+-]?\d+\.\d{4}", actual), (
                f"Output is not formatted to exactly four decimal places: {actual_raw!r}"
            )
            assert actual == expected, (
                f"Submitted program produced {actual}, expected {expected} on a test dataset."
            )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
