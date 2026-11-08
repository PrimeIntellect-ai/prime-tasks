#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
import tempfile

import numpy as np
import pytest
import requests

SEQ_STATS = "/app/seq_stats"
READS = "/app/reads.fasta"
GC_DATA = "/app/gc_data.txt"
IMAGE = "/app/gel_band.png"


def run_seq_stats(path):
    result = subprocess.run(
        [SEQ_STATS, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"/app/seq_stats failed with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def parse_fasta_gc(path):
    values = []
    gc = total = 0
    seen_sequence = False
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith(">"):
                if seen_sequence and total > 0:
                    values.append(gc / total)
                gc = total = 0
                seen_sequence = True
            else:
                for ch in line:
                    if "A" <= ch <= "Z":
                        total += 1
                        if ch in "GC":
                            gc += 1
    if seen_sequence and total > 0:
        values.append(gc / total)
    return values


def parse_numeric_output(raw):
    text = raw.decode("ascii").strip()
    assert text, "seq_stats produced empty output"
    values = [float(line) for line in text.splitlines()]
    assert all(math.isfinite(x) for x in values)
    return values


def ocr_prior_params():
    result = subprocess.run(
        ["tesseract", IMAGE, "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"tesseract failed: {result.stderr}"
    match = re.search(
        r"PRIOR_MU\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
        r"\s*,\s*PRIOR_SIGMA\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
        result.stdout,
        flags=re.IGNORECASE,
    )
    assert match, f"Could not extract prior parameters from OCR output: {result.stdout!r}"
    return float(match.group(1)), float(match.group(2))


def expected_posterior(data, prior_mu, prior_sigma):
    def log_posterior(mu):
        likelihood = -0.5 * np.sum(((data - mu) / 0.05) ** 2)
        prior = -0.5 * ((mu - prior_mu) / prior_sigma) ** 2
        return float(likelihood + prior)

    np.random.seed(42)
    current = prior_mu
    current_lp = log_posterior(current)
    samples = []
    for _ in range(10000):
        proposal = np.random.normal(current, 0.01)
        uniform = np.random.uniform()
        proposal_lp = log_posterior(proposal)
        if math.log(uniform) < min(0.0, proposal_lp - current_lp):
            current = proposal
            current_lp = proposal_lp
        samples.append(current)
    return float(np.mean(samples[1000:]))


def test_compiled_executable_exists():
    assert os.path.isfile(SEQ_STATS), "The C program was not compiled to /app/seq_stats."
    assert os.access(SEQ_STATS, os.X_OK), "/app/seq_stats is not executable."
    with open(SEQ_STATS, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/seq_stats is not a compiled ELF executable."


def test_compiled_executable_on_unpredictable_input():
    rng = random.SystemRandom()
    expected = []
    with tempfile.NamedTemporaryFile("w", suffix=".fasta", delete=False) as f:
        path = f.name
        for i in range(7):
            length = rng.randint(11, 73)
            sequence = "".join(rng.choice("ACGT") for _ in range(length))
            expected.append(sum(ch in "GC" for ch in sequence) / length)
            f.write(f">random_{i}_{rng.getrandbits(64):016x}\n")
            split = rng.randint(1, length)
            f.write(sequence[:split] + "\n")
            if split < length:
                f.write(sequence[split:] + "\n")
    try:
        actual = parse_numeric_output(run_seq_stats(path))
    finally:
        os.unlink(path)
    assert len(actual) == len(expected)
    assert np.allclose(actual, expected, rtol=0, atol=6e-7), (
        f"seq_stats returned {actual}, expected {expected}"
    )


def test_gc_data_exists_and_is_real_program_output():
    assert os.path.isfile(GC_DATA), "The output file /app/gc_data.txt does not exist."
    with open(GC_DATA, "rb") as f:
        saved = f.read()
    assert len(saved.splitlines()) > 0, "The /app/gc_data.txt file is empty."

    actual_stdout = run_seq_stats(READS)
    assert saved == actual_stdout, (
        "/app/gc_data.txt is not the exact output produced by running "
        "/app/seq_stats on /app/reads.fasta."
    )

    actual = parse_numeric_output(saved)
    expected = parse_fasta_gc(READS)
    assert len(actual) == len(expected)
    assert np.allclose(actual, expected, rtol=0, atol=6e-7), (
        f"GC fractions are incorrect: got {actual}, expected {expected}"
    )


def test_http_service_prior_params():
    url = "http://127.0.0.1:9090/prior_params"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse JSON from response: {response.text}")

    assert "mu" in data, "JSON response missing 'mu' key."
    assert "sigma" in data, "JSON response missing 'sigma' key."
    assert isinstance(data["mu"], (int, float)) and not isinstance(data["mu"], bool)
    assert isinstance(data["sigma"], (int, float)) and not isinstance(data["sigma"], bool)

    ocr_mu, ocr_sigma = ocr_prior_params()
    assert abs(data["mu"] - ocr_mu) < 1e-4, (
        f"Service mu {data['mu']} does not match OCR-derived value {ocr_mu}"
    )
    assert abs(data["sigma"] - ocr_sigma) < 1e-4, (
        f"Service sigma {data['sigma']} does not match OCR-derived value {ocr_sigma}"
    )

    assert abs(data["mu"] - 0.45) < 1e-4, f"Expected mu to be 0.45, got {data['mu']}"
    assert abs(data["sigma"] - 0.08) < 1e-4, f"Expected sigma to be 0.08, got {data['sigma']}"


def test_http_service_posterior_mean():
    url = "http://127.0.0.1:9090/posterior_mean"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    text = response.text.strip()
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", text), (
        f"Posterior mean must be plain text rounded to exactly 4 decimal places, got {text!r}"
    )

    with open(GC_DATA, "r", encoding="ascii") as f:
        gc_values = np.array([float(line.strip()) for line in f if line.strip()], dtype=float)
    prior_mu, prior_sigma = ocr_prior_params()
    expected = f"{expected_posterior(gc_values, prior_mu, prior_sigma):.4f}"
    assert text == expected, f"Expected independently calculated posterior mean {expected!r}, got {text!r}"
    assert text == "0.5849", f"Expected posterior mean to be '0.5849', got '{text}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
