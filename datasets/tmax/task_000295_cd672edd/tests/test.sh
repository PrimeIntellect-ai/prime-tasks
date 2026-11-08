#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

HOME = "/home/user"
CSV_PATH = f"{HOME}/baseline_load.csv"
PARAMS_PATH = f"{HOME}/baseline_params.txt"
MCMC_SOURCE = f"{HOME}/mcmc_fit.c"
CLASSIFIER_SOURCE = f"{HOME}/trace_classifier.c"
CLASSIFIER_PATH = f"{HOME}/classifier"
VIDEO_PATH = "/app/diagnostic_screen.mp4"


def read_params(path=PARAMS_PATH):
    with open(path, "r") as f:
        content = f.read().strip()
    parts = content.split()
    assert len(parts) == 2, f"Expected 2 values in {path}, found {len(parts)}."
    assert re.fullmatch(r"[-+]?\d+(?:\.\d{2})", parts[0]), "mu must be formatted to 2 decimal places."
    assert re.fullmatch(r"[-+]?\d+(?:\.\d{2})", parts[1]), "sigma must be formatted to 2 decimal places."
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        pytest.fail(f"Values in {path} are not valid floats: '{content}'")


def decoded_video_counts():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", VIDEO_PATH],
        check=True, capture_output=True, text=True,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH, "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        check=True, capture_output=True,
    ).stdout
    frame_size = width * height
    assert len(decoded) % frame_size == 0, "Decoded video did not contain complete frames."
    frames = np.frombuffer(decoded, dtype=np.uint8).reshape((-1, height, width))
    assert len(frames) == 100, f"Expected 100 decoded frames, found {len(frames)}."
    return [int(np.count_nonzero(frame > 127)) for frame in frames]


def test_baseline_load_csv():
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} is missing."
    with open(CSV_PATH, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 100, f"Expected 100 lines in {CSV_PATH}, found {len(lines)}."
    values = []
    for i, line in enumerate(lines):
        try:
            values.append(int(line.strip()))
        except ValueError:
            pytest.fail(f"Line {i+1} in {CSV_PATH} is not an integer: '{line}'")
    expected = decoded_video_counts()
    assert values == expected, "baseline_load.csv does not contain the white-pixel counts decoded from the video."


def test_baseline_params_txt():
    assert os.path.isfile(PARAMS_PATH), f"File {PARAMS_PATH} is missing."
    mu, sigma = read_params()
    assert 145000 <= mu <= 155000, f"Estimated mu ({mu}) is too far from expected 150000."
    assert 2000 <= sigma <= 8000, f"Estimated sigma ({sigma}) is too far from expected 5000."


def test_mcmc_source_compiles_and_fits_unseen_data():
    assert os.path.isfile(MCMC_SOURCE), f"File {MCMC_SOURCE} is missing."
    source = open(MCMC_SOURCE, "r", errors="replace").read()
    lowered = source.lower()
    assert re.search(r"\b(rand|random|drand48)\s*\(", lowered), "MCMC source does not use a random-number generator."
    assert re.search(r"\b(for|while)\s*\(", lowered), "MCMC source does not contain a sampling loop."
    assert ("metropolis" in lowered or "accept" in lowered) and ("exp(" in lowered or "log(" in lowered), \
        "MCMC source does not appear to implement a Metropolis-Hastings acceptance calculation."

    exe = f"/tmp/mcmc_fit_{secrets.token_hex(8)}"
    compiled = subprocess.run(
        ["gcc", "-O2", "-std=c11", MCMC_SOURCE, "-lm", "-o", exe],
        capture_output=True, text=True,
    )
    assert compiled.returncode == 0, f"mcmc_fit.c did not compile:\n{compiled.stderr}"

    original_csv = open(CSV_PATH, "rb").read()
    original_params = open(PARAMS_PATH, "rb").read()
    seed = secrets.randbits(64)
    rng = random.Random(seed)
    target_mu = rng.uniform(225000.0, 275000.0)
    target_sigma = rng.uniform(9000.0, 14000.0)
    synthetic = [int(round(rng.gauss(target_mu, target_sigma))) for _ in range(180)]
    sample_mu = sum(synthetic) / len(synthetic)
    sample_sigma = math.sqrt(sum((x - sample_mu) ** 2 for x in synthetic) / len(synthetic))

    try:
        with open(CSV_PATH, "w") as f:
            f.writelines(f"{x}\n" for x in synthetic)
        run = subprocess.run([exe], cwd=HOME, capture_output=True, text=True, timeout=90)
        assert run.returncode == 0, f"Compiled MCMC program failed on valid unseen data: {run.stderr}"
        assert os.path.isfile(PARAMS_PATH), "MCMC program did not write baseline_params.txt."
        fitted_mu, fitted_sigma = read_params()
        assert abs(fitted_mu - sample_mu) <= 5000, \
            f"MCMC fit did not track the mean of unseen input data ({fitted_mu} vs {sample_mu:.2f})."
        assert abs(fitted_sigma - sample_sigma) <= 4500, \
            f"MCMC fit did not track the standard deviation of unseen input data ({fitted_sigma} vs {sample_sigma:.2f})."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(PARAMS_PATH, "wb") as f:
            f.write(original_params)
        try:
            os.remove(exe)
        except FileNotFoundError:
            pass


def test_classifier_executable():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier executable {CLASSIFIER_PATH} is missing."
    assert os.access(CLASSIFIER_PATH, os.X_OK), f"File {CLASSIFIER_PATH} is not executable."


def test_classifier_source_compiles_and_uses_params_on_unseen_paths():
    assert os.path.isfile(CLASSIFIER_SOURCE), f"File {CLASSIFIER_SOURCE} is missing."
    exe = f"/tmp/classifier_{secrets.token_hex(8)}"
    compiled = subprocess.run(
        ["gcc", "-O2", "-std=c11", CLASSIFIER_SOURCE, "-lm", "-o", exe],
        capture_output=True, text=True,
    )
    assert compiled.returncode == 0, f"trace_classifier.c did not compile:\n{compiled.stderr}"

    original_params = open(PARAMS_PATH, "rb").read()
    temp_dir = tempfile.mkdtemp(prefix="holdout_", dir="/tmp")
    try:
        assert subprocess.run([exe], capture_output=True).returncode != 0, "Classifier must require exactly one argument."
        dummy = os.path.join(temp_dir, "extra.txt")
        open(dummy, "w").write("0\n")
        assert subprocess.run([exe, dummy, dummy], capture_output=True).returncode != 0, \
            "Classifier must reject more than one argument."

        for _ in range(3):
            mu = secrets.randbelow(90001) + 90000
            sigma = secrets.randbelow(7001) + 2500
            threshold = mu + 4 * sigma
            with open(PARAMS_PATH, "w") as f:
                f.write(f"{mu:.2f} {sigma:.2f}\n")

            safe = os.path.join(temp_dir, secrets.token_hex(8) + ".txt")
            spike = os.path.join(temp_dir, secrets.token_hex(8) + ".txt")
            with open(safe, "w") as f:
                f.write(f"{threshold - 20000}\n{threshold}\n{threshold - 1}\n")
            with open(spike, "w") as f:
                f.write(f"{threshold - 1}\n{threshold + 1}\n{threshold - 5000}\n")

            assert subprocess.run([exe, safe], capture_output=True).returncode == 0, \
                "Classifier rejected an unseen trace with no value above mu + 4*sigma."
            assert subprocess.run([exe, spike], capture_output=True).returncode == 1, \
                "Classifier failed to reject an unseen trace containing a value above mu + 4*sigma."
    finally:
        with open(PARAMS_PATH, "wb") as f:
            f.write(original_params)
        shutil.rmtree(temp_dir, ignore_errors=True)
        try:
            os.remove(exe)
        except FileNotFoundError:
            pass


def test_classifier_clean_corpus():
    clean_dir = "/app/traces/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    files = os.listdir(clean_dir)
    assert len(files) > 0, f"No files found in {clean_dir}."
    failed_files = []
    for file in files:
        filepath = os.path.join(clean_dir, file)
        result = subprocess.run([CLASSIFIER_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(file)
    assert not failed_files, f"{len(failed_files)} of {len(files)} clean modified/rejected (expected exit 0). Offending files: {', '.join(failed_files[:5])}"


def test_classifier_evil_corpus():
    evil_dir = "/app/traces/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    files = os.listdir(evil_dir)
    assert len(files) > 0, f"No files found in {evil_dir}."
    failed_files = []
    for file in files:
        filepath = os.path.join(evil_dir, file)
        result = subprocess.run([CLASSIFIER_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(file)
    assert not failed_files, f"{len(failed_files)} of {len(files)} evil bypassed (expected exit 1). Offending files: {', '.join(failed_files[:5])}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
