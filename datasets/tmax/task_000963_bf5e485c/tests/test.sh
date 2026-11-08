#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import numpy as np
import pytest

FILTER_EXEC = "/home/user/filter"
FILTER_SOURCE = "/home/user/filter.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
KISSFFT_HEADER = "/app/kissfft/kiss_fft.h"


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_EXEC, path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out while processing {path}")


def test_executable_exists():
    assert os.path.isfile(FILTER_EXEC), f"Executable {FILTER_EXEC} not found. Did you compile your C program?"
    assert os.access(FILTER_EXEC, os.X_OK), f"File {FILTER_EXEC} is not executable."
    with open(FILTER_EXEC, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted filter must be a compiled native executable."


def test_filter_source_uses_kissfft():
    assert os.path.isfile(FILTER_SOURCE), f"Required C source {FILTER_SOURCE} was not found."
    source = open(FILTER_SOURCE, "r", encoding="utf-8", errors="replace").read()
    # Ignore comments before checking for actual API call syntax.
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    assert re.search(r"\bkiss_fft_alloc\s*\(", source), "filter.c does not call kiss_fft_alloc."
    assert re.search(r"\bkiss_fft\s*\(", source), "filter.c does not call the 1D kiss_fft routine."


def test_kissfft_scalar_is_native_float(tmp_path):
    probe = tmp_path / "scalar_probe.c"
    executable = tmp_path / "scalar_probe"
    probe.write_text(
        '#include "kiss_fft.h"\n'
        'int main(void) {\n'
        '  kiss_fft_scalar x = (kiss_fft_scalar)0.5f;\n'
        '  return (sizeof(kiss_fft_scalar) == sizeof(float) && x > 0 && x < 1) ? 0 : 1;\n'
        '}\n'
    )
    compiled = subprocess.run(
        ["gcc", "-I/app/kissfft", str(probe), "-o", str(executable)],
        capture_output=True,
        text=True,
    )
    assert compiled.returncode == 0, f"Could not compile against repaired kissfft: {compiled.stderr}"
    result = subprocess.run([str(executable)], capture_output=True)
    assert result.returncode == 0, "kiss_fft_scalar is not the required single-precision floating-point type."


def test_corpus_evaluation():
    if not os.path.isfile(FILTER_EXEC) or not os.access(FILTER_EXEC, os.X_OK):
        pytest.fail("Filter executable is missing or not executable.")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    failed_clean = []
    for cf in clean_files:
        res = run_filter(cf)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        res = run_filter(ef)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(ef))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files rejected (expected to be accepted/exit 0): {failed_clean}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed (expected to be rejected/exit 1): {failed_evil}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_hidden_generated_fft_signals():
    n = 1024
    t = np.arange(n, dtype=np.float64)
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "little"))
    cases = []
    target_bins = [400, 401, 412, 425, 438, 449, 450]

    # Every file has a random opaque name in the same directory. Expected results
    # are recomputed from the exact rounded values written to disk.
    for i in range(24):
        signal = np.zeros(n, dtype=np.float64)
        for _ in range(int(rng.integers(2, 6))):
            k = int(rng.integers(3, 181))
            amplitude = float(rng.uniform(0.03, 0.9))
            phase = float(rng.uniform(0.0, 2.0 * np.pi))
            signal += amplitude * np.cos(2.0 * np.pi * k * t / n + phase)

        # Add unrelated high-frequency content outside the inspected interval.
        outside_bin = int(rng.choice([230, 275, 330, 470]))
        signal += float(rng.uniform(0.02, 0.25)) * np.cos(
            2.0 * np.pi * outside_bin * t / n + float(rng.uniform(0.0, 2.0 * np.pi))
        )

        monitored_bin = target_bins[i % len(target_bins)] if i < len(target_bins) else int(rng.integers(400, 451))
        should_be_evil = (i % 2) == 1
        target_power = float(rng.uniform(90.0, 500.0) if should_be_evil else rng.uniform(0.0, 30.0))
        phase = float(rng.uniform(0.0, 2.0 * np.pi))
        signal += (2.0 * np.sqrt(target_power) / n) * np.cos(
            2.0 * np.pi * monitored_bin * t / n + phase
        )
        cases.append(signal)

    with tempfile.TemporaryDirectory(prefix="fft_eval_") as directory:
        failures = []
        order = rng.permutation(len(cases))
        for case_index in order:
            path = os.path.join(directory, secrets.token_hex(14) + ".dat")
            with open(path, "w", encoding="ascii") as f:
                for value in cases[int(case_index)]:
                    f.write(f"{value:.9g}\n")

            exact_input = np.loadtxt(path, dtype=np.float64)
            spectrum = np.fft.fft(exact_input)
            powers = spectrum.real * spectrum.real + spectrum.imag * spectrum.imag
            peak = float(np.max(powers[400:451]))
            assert peak < 40.0 or peak > 70.0, "Generated case was unexpectedly close to the decision threshold."
            expected = 1 if peak > 50.0 else 0

            result = run_filter(path)
            if result.returncode != expected:
                failures.append(
                    f"opaque case {case_index}: FFT peak={peak:.6f}, expected exit {expected}, got {result.returncode}"
                )

        assert not failures, "Hidden FFT evaluation failed: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
