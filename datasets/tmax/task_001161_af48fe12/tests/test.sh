#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import itertools
import re
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pytest

SCRIPT = '/home/user/analyze_sequences.py'
SEQ1 = '/home/user/seq1.txt'
SEQ2 = '/home/user/seq2.txt'
OUT = '/home/user/js_distance.txt'
PLOT = '/home/user/kmer_plot.png'


def get_kmer_distribution(seq, k=3):
    kmers = ["".join(p) for p in itertools.product("ACGT", repeat=k)]
    counts = {kmer: 0 for kmer in kmers}
    for i in range(len(seq) - k + 1):
        kmer = seq[i:i+k]
        if kmer in counts:
            counts[kmer] += 1
    total = sum(counts.values())
    if total == 0:
        return [0.0] * len(kmers)
    return [counts[kmer] / total for kmer in sorted(kmers)]


def kl_divergence(p, q):
    return sum(p[i] * math.log(p[i] / q[i]) for i in range(len(p)) if p[i] > 0)


def jensen_shannon_distance(p, q):
    m = [0.5 * (p[i] + q[i]) for i in range(len(p))]
    jsd = 0.5 * kl_divergence(p, m) + 0.5 * kl_divergence(q, m)
    return math.sqrt(jsd)


def run_script():
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}:\n{result.stderr}"
    )


def load_plot(path=PLOT):
    with open(path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'Plot is not a PNG file'
    try:
        image = np.asarray(mpimg.imread(path))
    except Exception as exc:
        pytest.fail(f'Plot is not a readable PNG: {exc}')
    assert image.ndim in (2, 3), 'Plot has an invalid image shape'
    assert image.shape[0] > 1 and image.shape[1] > 1, 'Plot has invalid dimensions'
    assert np.isfinite(image).all(), 'Plot contains invalid pixel values'
    assert float(np.max(image) - np.min(image)) > 1e-6, 'Plot is visually blank'
    return image.copy()


def test_analyze_sequences_script_exists():
    path = '/home/user/analyze_sequences.py'
    assert os.path.exists(path), f"Missing script: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"


def test_script_runs_successfully():
    run_script()


def test_kmer_plot_exists():
    path = '/home/user/kmer_plot.png'
    assert os.path.exists(path), f"Missing plot file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"
    assert os.path.getsize(path) > 0, f"Plot file {path} is empty"


def test_kmer_plot_is_valid_png():
    load_plot()


def test_js_distance_output():
    seq1_path = '/home/user/seq1.txt'
    seq2_path = '/home/user/seq2.txt'
    out_path = '/home/user/js_distance.txt'

    assert os.path.exists(out_path), f"Missing output file: {out_path}"
    assert os.path.isfile(out_path), f"Path is not a file: {out_path}"

    with open(seq1_path, 'r') as f:
        seq1 = f.read().strip()
    with open(seq2_path, 'r') as f:
        seq2 = f.read().strip()

    p = get_kmer_distribution(seq1)
    q = get_kmer_distribution(seq2)
    expected_dist = jensen_shannon_distance(p, q)
    expected_str = f"{expected_dist:.4f}"

    with open(out_path, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected JS distance {expected_str}, but got {actual_str}"


def test_script_recomputes_outputs_and_visualizes_both_distributions():
    with open(SEQ1, 'r') as f:
        original_seq1 = f.read()
    with open(SEQ2, 'r') as f:
        original_seq2 = f.read()

    def exercise(seq1, seq2):
        with open(SEQ1, 'w') as f:
            f.write(seq1)
        with open(SEQ2, 'w') as f:
            f.write(seq2)
        run_script()

        expected = f"{jensen_shannon_distance(get_kmer_distribution(seq1), get_kmer_distribution(seq2)):.4f}"
        assert os.path.isfile(OUT), f'Missing output file: {OUT}'
        with open(OUT, 'r') as f:
            raw = f.read()
        assert re.fullmatch(r'\d+\.\d{4}\n?', raw), (
            'JS distance must be written with exactly four decimal places'
        )
        assert raw.strip() == expected, f'Expected JS distance {expected}, but got {raw.strip()}'
        assert os.path.isfile(PLOT), f'Missing plot file: {PLOT}'
        return load_plot()

    try:
        # seq1 is held fixed while only seq2 changes. A plot comparing both
        # distributions must therefore change between these two executions.
        first_plot = exercise('A' * 120, 'T' * 120)
        second_plot = exercise('A' * 120, 'A' * 120)
        plots_equal = first_plot.shape == second_plot.shape and np.array_equal(first_plot, second_plot)
        assert not plots_equal, (
            'Plot did not change when the second sequence distribution changed'
        )
    finally:
        with open(SEQ1, 'w') as f:
            f.write(original_seq1)
        with open(SEQ2, 'w') as f:
            f.write(original_seq2)
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
