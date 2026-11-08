#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

LIB_DIR = "/app/minifft-1.2.0"
LIB_FILE = os.path.join(LIB_DIR, "libminifft.a")
SCRIPT_PATH = "/home/user/workspace/run_pipeline.sh"
CPP_PATH = "/home/user/workspace/wave_sim.cpp"
CSV_PATH = "/home/user/workspace/spectrum.csv"


def run_pipeline(env=None):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user/workspace",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"
    assert os.path.isfile(CSV_PATH), "run_pipeline.sh did not produce spectrum.csv."


def load_spectrum():
    try:
        return pd.read_csv(CSV_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to read {CSV_PATH} as CSV: {exc}")


def assert_csv_shape(df):
    assert "bin_index" in df.columns, "The CSV file must contain a 'bin_index' column."
    assert "magnitude" in df.columns, "The CSV file must contain a 'magnitude' column."
    assert len(df) >= 50, f"Expected at least 50 bins in the output, but got {len(df)}."
    indices = pd.to_numeric(df["bin_index"].iloc[:50], errors="coerce").to_numpy()
    assert np.all(np.isfinite(indices)), "bin_index must contain numeric values."
    assert np.array_equal(indices, np.arange(50)), "The first 50 bin indices must be 0 through 49."


def test_artifacts_build_and_pipeline_behavior():
    # Preserve the original artifact assertions.
    assert os.path.isfile(LIB_FILE), f"Expected static library {LIB_FILE} was not built."
    assert os.path.isfile(SCRIPT_PATH), f"Pipeline script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."

    # The repaired Makefile must genuinely build a valid static archive.
    clean = subprocess.run(["make", "clean"], cwd=LIB_DIR, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=30)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"
    build = subprocess.run(["make"], cwd=LIB_DIR, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=60)
    assert build.returncode == 0, f"The repaired MiniFFT Makefile does not build:\n{build.stdout}"
    assert os.path.isfile(LIB_FILE), f"Expected static library {LIB_FILE} was not built."
    listing = subprocess.run(["ar", "t", LIB_FILE], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, timeout=10)
    assert listing.returncode == 0 and listing.stdout.strip(), \
        f"{LIB_FILE} is not a valid nonempty static archive: {listing.stdout}"

    # Execute the submitted pipeline with the real library.
    run_pipeline()
    real_df = load_spectrum()
    assert_csv_shape(real_df)

    # Replace only the archive temporarily with a fresh behavioral probe. A pipeline
    # that really links and uses MiniFFT will pass the generated signal to this code
    # and emit the unpredictable magnitudes returned by it.
    original_archive = open(LIB_FILE, "rb").read()
    rng = np.random.default_rng(secrets.randbits(128))
    reals = rng.uniform(-80.0, 80.0, 50)
    imags = rng.uniform(-80.0, 80.0, 50)
    expected_probe = np.hypot(reals, imags)
    nonce = secrets.token_hex(24)

    with tempfile.TemporaryDirectory(prefix="minifft_probe_") as td:
        probe_cpp = os.path.join(td, "probe.cpp")
        probe_obj = os.path.join(td, "probe.o")
        marker = os.path.join(td, "called.marker")
        real_init = ",".join(format(float(x), ".17g") for x in reals)
        imag_init = ",".join(format(float(x), ".17g") for x in imags)
        source = f'''\
#include "minifft.h"
#include <cmath>
#include <complex>
#include <cstdlib>
#include <fstream>
#include <vector>
namespace MiniFFT {{
void forward_transform(const std::vector<double>& input,
                       std::vector<std::complex<double>>& output) {{
    if (input.size() != 1024) return;
    const double pi = std::acos(-1.0);
    for (std::size_t n = 0; n < input.size(); ++n) {{
        const double t = static_cast<double>(n) / 1024.0;
        const double want = std::sin(2.0*pi*10.0*t) + 0.5*std::cos(2.0*pi*25.0*t);
        if (std::abs(input[n] - want) > 1e-9) return;
    }}
    const double r[50] = {{{real_init}}};
    const double i[50] = {{{imag_init}}};
    output.assign(input.size(), std::complex<double>(0.0, 0.0));
    for (std::size_t k = 0; k < 50; ++k) output[k] = std::complex<double>(r[k], i[k]);
    const char* path = std::getenv("MINIFFT_PROBE_MARKER");
    const char* token = std::getenv("MINIFFT_PROBE_NONCE");
    if (path && token) {{ std::ofstream f(path); f << token; }}
}}
}}
'''
        with open(probe_cpp, "w") as f:
            f.write(source)
        compile_probe = subprocess.run(
            ["g++", "-O2", "-I/app/minifft-1.2.0/include", "-c", probe_cpp, "-o", probe_obj],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
        assert compile_probe.returncode == 0, f"Could not build verifier probe:\n{compile_probe.stdout}"
        probe_archive = os.path.join(td, "libminifft.a")
        archive_probe = subprocess.run(["ar", "rcs", probe_archive, probe_obj],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, timeout=10)
        assert archive_probe.returncode == 0, f"Could not archive verifier probe:\n{archive_probe.stdout}"

        shutil.copyfile(probe_archive, LIB_FILE)
        probe_hash = hashlib.sha256(open(LIB_FILE, "rb").read()).hexdigest()
        env = os.environ.copy()
        env["MINIFFT_PROBE_MARKER"] = marker
        env["MINIFFT_PROBE_NONCE"] = nonce
        try:
            run_pipeline(env)
            assert hashlib.sha256(open(LIB_FILE, "rb").read()).hexdigest() == probe_hash, \
                "run_pipeline.sh replaced the required MiniFFT archive instead of linking it."
            assert os.path.isfile(marker), \
                "MiniFFT::forward_transform was not called with the required 1024-sample signal."
            assert open(marker).read() == nonce, "Invalid MiniFFT probe marker."
            probe_df = load_spectrum()
            assert_csv_shape(probe_df)
            probe_mag = pd.to_numeric(probe_df["magnitude"].iloc[:50], errors="coerce").to_numpy()
            assert np.all(np.isfinite(probe_mag)), "Probe magnitudes must be finite numeric values."
            assert np.allclose(probe_mag, expected_probe, rtol=2e-5, atol=2e-5), \
                "spectrum.csv was not generated from the output of MiniFFT::forward_transform."
        finally:
            with open(LIB_FILE, "wb") as f:
                f.write(original_archive)

    # Re-run with the genuine archive and retain the original numerical assertion.
    run_pipeline()
    df = load_spectrum()
    assert_csv_shape(df)
    N = 1024
    t = np.linspace(0, 1, N, endpoint=False)
    y = np.sin(2 * np.pi * 10 * t) + 0.5 * np.cos(2 * np.pi * 25 * t)
    fft_gt = np.abs(np.fft.fft(y))[:50]
    agent_mag = pd.to_numeric(df["magnitude"].iloc[:50], errors="coerce").to_numpy()
    assert np.all(np.isfinite(agent_mag)), "Magnitude values must be finite numbers."
    mse = np.mean((fft_gt - agent_mag) ** 2)
    threshold = 1e-4
    assert mse < threshold, f"MSE of magnitudes is {mse}, which is not below {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
