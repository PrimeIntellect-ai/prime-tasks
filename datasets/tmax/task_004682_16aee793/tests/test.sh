#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'C_EOF' > /tmp/expected_power.c
#include <hdf5.h>
#include <fftw3.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define NSIG 1000
#define N 1024
#define NBIN 513

int main(void) {
    hid_t file = H5Fopen("/home/user/data/signals.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file < 0) return 2;
    hid_t ds = H5Dopen2(file, "signals", H5P_DEFAULT);
    if (ds < 0) return 3;

    float *signals = malloc((size_t)NSIG * N * sizeof(float));
    float *in = fftwf_malloc(N * sizeof(float));
    fftwf_complex *out = fftwf_malloc(NBIN * sizeof(fftwf_complex));
    if (!signals || !in || !out) return 4;
    if (H5Dread(ds, H5T_NATIVE_FLOAT, H5S_ALL, H5S_ALL, H5P_DEFAULT, signals) < 0) return 5;

    fftwf_plan plan = fftwf_plan_dft_r2c_1d(N, in, out, FFTW_ESTIMATE);
    if (!plan) return 6;

    double sum = 0.0;
    double compensation = 0.0;
    const double pi = acos(-1.0);
    for (int s = 0; s < NSIG; ++s) {
        for (int n = 0; n < N; ++n) {
            double w = 0.5 * (1.0 - cos(2.0 * pi * n / 1023.0));
            in[n] = (float)(signals[(size_t)s * N + n] * w);
        }
        fftwf_execute(plan);
        for (int k = 0; k < NBIN; ++k) {
            float power = out[k][0] * out[k][0] + out[k][1] * out[k][1];
            double y = (double)power - compensation;
            double next = sum + y;
            compensation = (next - sum) - y;
            sum = next;
        }
    }

    printf("Total Power: %.6f\n", sum);
    fftwf_destroy_plan(plan);
    fftwf_free(out);
    fftwf_free(in);
    free(signals);
    H5Dclose(ds);
    H5Fclose(file);
    return 0;
}
C_EOF
h5cc /tmp/expected_power.c -lfftw3f -lm -o /tmp/expected_power

cat <<'PY_EOF' > /tmp/validate_plot.py
import os
import runpy
import sys
import h5py
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.axes

with h5py.File("/home/user/data/signals.h5", "r") as f:
    signals = f["signals"][:]
window = 0.5 * (1.0 - np.cos(2.0 * np.pi * np.arange(1024) / 1023.0))
transformed = np.fft.rfft(signals * window, axis=1)
expected = np.mean(transformed.real ** 2 + transformed.imag ** 2, axis=0)
expected_x = np.arange(513)
captured = []

def record(args):
    try:
        if len(args) >= 2:
            x = np.asarray(args[0])
            y = np.asarray(args[1])
        elif len(args) == 1:
            y = np.asarray(args[0])
            x = np.arange(y.size)
        else:
            return
        if x.ndim == 1 and y.ndim == 1:
            captured.append((x.astype(float), y.astype(float)))
    except Exception:
        pass

for name in ("plot", "step", "scatter", "bar", "fill_between"):
    original = getattr(matplotlib.axes.Axes, name)
    def make_wrapper(fn):
        def wrapper(self, *args, **kwargs):
            record(args)
            return fn(self, *args, **kwargs)
        return wrapper
    setattr(matplotlib.axes.Axes, name, make_wrapper(original))

os.chdir("/home/user")
runpy.run_path("/home/user/plot_spectrum.py", run_name="__main__")

matched = False
for x, y in captured:
    if x.shape == expected_x.shape and y.shape == expected.shape:
        if np.allclose(x, expected_x, rtol=0, atol=1e-9) and np.allclose(
            y, expected, rtol=2e-5, atol=max(1e-7, float(expected.max()) * 1e-8)
        ):
            matched = True
            break
if not matched:
    print("The generated plot did not contain the required mean power spectrum.", file=sys.stderr)
    sys.exit(1)
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import sys


def test_c_program_and_total_power_output():
    source = "/home/user/process_signals.c"
    assert os.path.isfile(source), f"C source is missing: {source}"
    text = open(source, encoding="utf-8", errors="replace").read()
    assert "fftwf_plan_dft_r2c_1d" in text, "C program does not use the required single-precision FFTW API"
    assert re.search(r"\bdouble\b", text), "C program does not declare double-precision accumulation variables"

    executable = "/tmp/process_signals_submission"
    subprocess.run(
        ["h5cc", source, "-lfftw3f", "-lm", "-o", executable],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    output_file = "/home/user/total_power.txt"
    if os.path.exists(output_file):
        os.remove(output_file)
    subprocess.run([executable], check=True, timeout=120)
    assert os.path.isfile(output_file), f"Output file is missing: {output_file}"

    with open(output_file, "r") as f:
        actual_content = f.read().strip()
    assert re.fullmatch(r"Total Power: [-+]?(?:\d+\.\d{6})", actual_content), (
        "total_power.txt does not use the required format with six decimal places"
    )
    expected_content = subprocess.check_output(["/tmp/expected_power"], text=True).strip()
    assert actual_content == expected_content, (
        f"Contents of {output_file} do not match single-precision FFTW computation.\n"
        f"Expected: '{expected_content}'\nActual:   '{actual_content}'"
    )


def test_mean_spectrum_plot_exists_and_is_correct():
    script = "/home/user/plot_spectrum.py"
    assert os.path.isfile(script), f"Plot script is missing: {script}"
    plot_file = "/home/user/mean_spectrum.png"
    if os.path.exists(plot_file):
        os.remove(plot_file)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run([sys.executable, "/tmp/validate_plot.py"], check=True, timeout=120, env=env)
    assert os.path.isfile(plot_file), f"Plot file is missing: {plot_file}"
    with open(plot_file, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"File {plot_file} is not a valid PNG image."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
