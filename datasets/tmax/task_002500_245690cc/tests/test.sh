#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import shutil
import subprocess
import tempfile


def test_package_installed():
    """Verify that the libfftw3-dev package is installed."""
    result = subprocess.run(["dpkg", "-s", "libfftw3-dev"], capture_output=True, text=True)
    assert result.returncode == 0, "The package 'libfftw3-dev' is not installed."


def test_c_source_and_executable_exist():
    """Check that the C source code and compiled executable exist."""
    assert os.path.isfile("/home/user/generate_data.c"), "/home/user/generate_data.c does not exist."
    assert os.path.isfile("/home/user/generate_data"), "/home/user/generate_data executable does not exist."
    assert os.access("/home/user/generate_data", os.X_OK), "/home/user/generate_data is not executable."


def test_build_execute_and_use_fftw_pipeline():
    """Rebuild the submitted source, execute it, and verify its output depends on FFTW results."""
    source = "/home/user/generate_data.c"
    executable = "/home/user/generate_data"
    rebuilt = "/home/user/generate_data.verifier"
    csv_path = "/home/user/training_metadata.csv"

    build = subprocess.run(
        ["gcc", source, "-o", rebuilt, "-lfftw3", "-lm"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Submitted C source did not compile:\n{build.stderr}"
    os.replace(rebuilt, executable)
    os.chmod(executable, 0o755)

    symbols = subprocess.run(["nm", "-D", executable], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Could not inspect rebuilt executable: {symbols.stderr}"
    assert "fftw_plan_dft_r2c_1d" in symbols.stdout, \
        "The rebuilt program does not use fftw_plan_dft_r2c_1d."
    assert ("fftw_execute" in symbols.stdout or "fftw_execute_dft_r2c" in symbols.stdout), \
        "The rebuilt program does not execute an FFTW transform."

    if os.path.exists(csv_path):
        os.unlink(csv_path)
    run = subprocess.run([executable], capture_output=True, text=True, timeout=30)
    assert run.returncode == 0, f"Rebuilt generate_data failed:\n{run.stderr}"
    assert os.path.isfile(csv_path), "Executing /home/user/generate_data did not create the CSV."
    with open(csv_path, "r") as f:
        normal_output = f.read()

    shim_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>

typedef void *fftw_plan;
typedef double fftw_complex[2];

static fftw_plan watched_plan = NULL;
static fftw_complex *watched_output = NULL;
static int watched_n = 0;

static void poison(fftw_complex *out, int n) {
    int last = n / 2;
    int hi = last < 40 ? last : 40;
    for (int k = 10; k <= hi; ++k) {
        out[k][0] = 1000.0 * k;
        out[k][1] = 0.0;
    }
}

fftw_plan fftw_plan_dft_r2c_1d(int n, double *in, fftw_complex *out, unsigned flags) {
    typedef fftw_plan (*real_fn)(int, double *, fftw_complex *, unsigned);
    static real_fn real = NULL;
    if (!real) real = (real_fn)dlsym(RTLD_NEXT, "fftw_plan_dft_r2c_1d");
    fftw_plan plan = real(n, in, out, flags);
    watched_plan = plan;
    watched_output = out;
    watched_n = n;
    return plan;
}

void fftw_execute(const fftw_plan plan) {
    typedef void (*real_fn)(const fftw_plan);
    static real_fn real = NULL;
    if (!real) real = (real_fn)dlsym(RTLD_NEXT, "fftw_execute");
    real(plan);
    if (plan == watched_plan && watched_output) poison(watched_output, watched_n);
}

void fftw_execute_dft_r2c(const fftw_plan plan, double *in, fftw_complex *out) {
    typedef void (*real_fn)(const fftw_plan, double *, fftw_complex *);
    static real_fn real = NULL;
    if (!real) real = (real_fn)dlsym(RTLD_NEXT, "fftw_execute_dft_r2c");
    real(plan, in, out);
    poison(out, watched_n ? watched_n : 100);
}
'''
    with tempfile.TemporaryDirectory() as tmp:
        shim_c = os.path.join(tmp, "fftw_poison.c")
        shim_so = os.path.join(tmp, "fftw_poison.so")
        with open(shim_c, "w") as f:
            f.write(shim_source)
        shim_build = subprocess.run(
            ["gcc", "-shared", "-fPIC", shim_c, "-o", shim_so, "-ldl"],
            capture_output=True,
            text=True,
        )
        assert shim_build.returncode == 0, f"Could not build FFTW audit shim:\n{shim_build.stderr}"

        os.unlink(csv_path)
        env = os.environ.copy()
        env["LD_PRELOAD"] = shim_so
        poisoned_run = subprocess.run(
            [executable], capture_output=True, text=True, timeout=30, env=env
        )
        assert poisoned_run.returncode == 0, \
            f"Program failed while auditing FFTW use:\n{poisoned_run.stderr}"
        assert os.path.isfile(csv_path), "Program did not create CSV during FFTW audit run."
        with open(csv_path, "r") as f:
            poisoned_output = f.read()
        assert poisoned_output != normal_output, \
            "CSV output does not depend on the FFTW transform results."

    os.unlink(csv_path)
    final_run = subprocess.run([executable], capture_output=True, text=True, timeout=30)
    assert final_run.returncode == 0, f"Final execution of generate_data failed:\n{final_run.stderr}"


def compute_expected_csv():
    """Compute the expected CSV output using the exact specified PRNG and math logic."""
    state = 42

    def next_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648.0

    lines = []
    for id_val in range(100):
        A = 0.1 + 1.9 * next_rand()
        y = []
        for i in range(100):
            t = i * 0.01
            v = -A + 2.0 * A * next_rand()
            y.append(math.sin(2.0 * math.pi * 5.0 * t) + v)

        M = []
        for k in range(10, 41):
            re = 0.0
            im = 0.0
            for n in range(100):
                angle = -2.0 * math.pi * k * n / 100.0
                re += y[n] * math.cos(angle)
                im += y[n] * math.sin(angle)
            M.append(math.sqrt(re * re + im * im))

        sum_x = 0.0
        sum_y = 0.0
        sum_xy = 0.0
        sum_xx = 0.0
        n_points = 31

        for i, k in enumerate(range(10, 41)):
            mag = M[i]
            sum_x += k
            sum_y += mag
            sum_xy += k * mag
            sum_xx += k * k

        mean_x = sum_x / n_points
        mean_y = sum_y / n_points
        numerator = sum_xy - n_points * mean_x * mean_y
        denominator = sum_xx - n_points * mean_x * mean_x
        m = numerator / denominator
        lines.append(f"{id_val},{A:.4f},{m:.4f}")

    return lines


def test_csv_output():
    """Verify that the generated CSV file matches the expected output exactly."""
    csv_path = "/home/user/training_metadata.csv"
    assert os.path.exists(csv_path), f"File {csv_path} was not generated."

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = compute_expected_csv()
    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in the CSV, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f"Mismatch at line {i + 1} in {csv_path}:\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
