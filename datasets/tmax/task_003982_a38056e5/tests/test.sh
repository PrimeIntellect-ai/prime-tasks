#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import tempfile
import time
import uuid

import numpy as np
import pytest
from PIL import Image, ImageStat

PLOT_SCRIPT = "/app/plot_correlations.py"
OUTPUT_IMAGE = "/home/user/correlation.png"
FILTER_SCRIPT = "/home/user/filter_datasets.py"
BENCHMARK_FILE = "/home/user/benchmark.txt"


def run_filter(input_dir, output_dir):
    start = time.perf_counter()
    result = subprocess.run(
        ["python3", FILTER_SCRIPT, input_dir, output_dir],
        capture_output=True,
        text=True,
        timeout=120,
    )
    elapsed = time.perf_counter() - start
    assert result.returncode == 0, f"Filter failed: {result.stderr}"
    assert os.path.isfile(BENCHMARK_FILE), f"{BENCHMARK_FILE} does not exist."
    content = open(BENCHMARK_FILE, "r").read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Benchmark file does not contain a valid float. Content: '{content}'")
    assert np.isfinite(value) and value > 0, "Benchmark time should be a finite value greater than 0."
    return value, elapsed


def correlated_array(rho, seed, rows=320, columns=8):
    """Construct data whose first two columns have a controlled sample correlation."""
    rng = np.random.default_rng(seed)
    raw = rng.normal(size=(rows, columns + 1))
    raw -= raw.mean(axis=0, keepdims=True)
    q, _ = np.linalg.qr(raw)
    data = np.empty((rows, columns), dtype=np.float64)
    data[:, 0] = q[:, 0]
    data[:, 1] = rho * q[:, 0] + np.sqrt(1.0 - rho * rho) * q[:, 1]
    for index in range(2, columns):
        data[:, index] = q[:, index]
    actual = abs(np.corrcoef(data, rowvar=False)[0, 1])
    assert abs(actual - rho) < 1e-10
    return data


def test_correlation_plot_generated():
    """Execute the repaired plotting script and decode the resulting heatmap."""
    assert os.path.isfile(PLOT_SCRIPT), f"{PLOT_SCRIPT} does not exist."
    assert os.access(PLOT_SCRIPT, os.X_OK), f"{PLOT_SCRIPT} is not executable."
    if os.path.exists(OUTPUT_IMAGE):
        os.remove(OUTPUT_IMAGE)

    result = subprocess.run(["python3", PLOT_SCRIPT], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"Plot script failed: {result.stderr}"
    assert os.path.isfile(OUTPUT_IMAGE), f"{OUTPUT_IMAGE} does not exist."
    assert os.path.getsize(OUTPUT_IMAGE) > 1000, (
        f"{OUTPUT_IMAGE} seems to be empty or invalid (size: {os.path.getsize(OUTPUT_IMAGE)} bytes)."
    )

    try:
        with Image.open(OUTPUT_IMAGE) as image:
            image.verify()
        with Image.open(OUTPUT_IMAGE) as image:
            image.load()
            assert image.width >= 100 and image.height >= 100, "Rendered image is implausibly small."
            rgb = image.convert("RGB")
            stat = ImageStat.Stat(rgb)
            assert max(stat.stddev) > 10, "Rendered image is blank or nearly uniform."
            colors = rgb.resize((128, 128)).getcolors(maxcolors=16384)
            assert colors is not None and len(colors) > 32, "Image lacks heatmap color variation."
    except (OSError, SyntaxError) as exc:
        pytest.fail(f"{OUTPUT_IMAGE} is not a decodable image: {exc}")


def test_adversarial_corpus_filtering():
    """Preserve the original clean/evil corpus checks."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script {FILTER_SCRIPT} does not exist."
    assert os.access(FILTER_SCRIPT, os.X_OK), f"{FILTER_SCRIPT} is not executable."

    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"
    with tempfile.TemporaryDirectory() as eval_clean, tempfile.TemporaryDirectory() as eval_evil:
        clean_result = subprocess.run(
            ["python3", FILTER_SCRIPT, clean_corpus, eval_clean],
            capture_output=True, text=True, timeout=120,
        )
        assert clean_result.returncode == 0, f"Script failed on clean corpus: {clean_result.stderr}"
        evil_result = subprocess.run(
            ["python3", FILTER_SCRIPT, evil_corpus, eval_evil],
            capture_output=True, text=True, timeout=120,
        )
        assert evil_result.returncode == 0, f"Script failed on evil corpus: {evil_result.stderr}"

        clean_input_files = {os.path.basename(f) for f in glob.glob(os.path.join(clean_corpus, "*.npy"))}
        clean_output_files = {os.path.basename(f) for f in glob.glob(os.path.join(eval_clean, "*.npy"))}
        missing_clean = clean_input_files - clean_output_files
        assert len(clean_output_files) == len(clean_input_files), (
            f"{len(missing_clean)} of {len(clean_input_files)} clean files modified/rejected: {missing_clean}"
        )

        evil_input_files = {os.path.basename(f) for f in glob.glob(os.path.join(evil_corpus, "*.npy"))}
        evil_output_files = {os.path.basename(f) for f in glob.glob(os.path.join(eval_evil, "*.npy"))}
        assert len(evil_output_files) == 0, (
            f"{len(evil_output_files)} of {len(evil_input_files)} evil files bypassed: {evil_output_files}"
        )


def test_filter_on_unseen_mixed_corpus():
    """Exercise correlation decisions in one unpredictable directory around threshold 0.85."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script {FILTER_SCRIPT} does not exist."
    rng = np.random.default_rng()
    cases = [0.12, 0.61, 0.849, 0.851, 0.91, 0.98]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="dataset_input_") as input_dir, \
         tempfile.TemporaryDirectory(prefix="dataset_output_") as output_dir:
        expected = set()
        source_bytes = {}
        for index, rho in enumerate(cases):
            name = f"{uuid.uuid4().hex}_{index}.npy"
            path = os.path.join(input_dir, name)
            np.save(path, correlated_array(rho, int(rng.integers(0, 2**31 - 1))))
            source_bytes[name] = open(path, "rb").read()
            if rho < 0.85:
                expected.add(name)

        with open(os.path.join(input_dir, "ignore_me.txt"), "w") as handle:
            handle.write("not a numpy dataset")

        run_filter(input_dir, output_dir)
        actual = {os.path.basename(path) for path in glob.glob(os.path.join(output_dir, "*.npy"))}
        assert actual == expected, f"Incorrect unseen-corpus decisions: expected {expected}, got {actual}"
        for name in expected:
            assert open(os.path.join(output_dir, name), "rb").read() == source_bytes[name], (
                f"Passing file {name} was not copied unchanged."
            )
        assert not os.path.exists(os.path.join(output_dir, "ignore_me.txt")), "Non-.npy input was copied."


def test_benchmark_file_exists_and_valid_and_is_updated():
    """Require a fresh per-run measurement that scales with substantially different work."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script {FILTER_SCRIPT} does not exist."

    with tempfile.TemporaryDirectory(prefix="bench_small_in_") as small_in, \
         tempfile.TemporaryDirectory(prefix="bench_small_out_") as small_out, \
         tempfile.TemporaryDirectory(prefix="bench_large_in_") as large_in, \
         tempfile.TemporaryDirectory(prefix="bench_large_out_") as large_out:
        rng = np.random.default_rng()
        for i in range(3):
            np.save(os.path.join(small_in, f"s_{uuid.uuid4().hex}_{i}.npy"), rng.normal(size=(80, 4)))
            np.save(os.path.join(large_in, f"l_{uuid.uuid4().hex}_{i}.npy"), rng.normal(size=(2500, 180)))

        with open(BENCHMARK_FILE, "w") as handle:
            handle.write("-123\n")
        small_value, small_elapsed = run_filter(small_in, small_out)
        assert open(BENCHMARK_FILE).read().strip() != "-123", "Benchmark was not rewritten after processing."
        assert small_value <= small_elapsed * 2 + 0.05, "Reported small-run time is not plausible."

        with open(BENCHMARK_FILE, "w") as handle:
            handle.write("-456\n")
        large_value, large_elapsed = run_filter(large_in, large_out)
        assert open(BENCHMARK_FILE).read().strip() != "-456", "Benchmark was not rewritten on the next run."
        assert large_value <= large_elapsed * 2 + 0.05, "Reported large-run time is not plausible."
        assert large_value > small_value * 1.2, (
            f"Benchmark does not reflect workload: small={small_value}, large={large_value}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
