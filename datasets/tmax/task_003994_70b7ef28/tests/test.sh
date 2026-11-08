#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
ANALYZER_C = f"{HOME}/analyzer.c"
ANALYZER = f"{HOME}/analyzer"
PLOT_SCRIPT = f"{HOME}/plot_hist.sh"


def parse_fasta(filepath):
    lengths = []
    gcs = []
    with open(filepath, 'r') as f:
        current_seq = []
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if current_seq:
                    seq = "".join(current_seq)
                    lengths.append(len(seq))
                    gc = sum(1 for c in seq if c in 'GCgc') / len(seq)
                    gcs.append(gc)
                current_seq = []
            else:
                current_seq.append(line)
        if current_seq:
            seq = "".join(current_seq)
            lengths.append(len(seq))
            gc = sum(1 for c in seq if c in 'GCgc') / len(seq)
            gcs.append(gc)
    return lengths, gcs


def assert_required_artifacts():
    assert os.path.isfile(ANALYZER_C), f"{ANALYZER_C} is missing or not a regular file."
    assert os.path.isfile(ANALYZER), f"{ANALYZER} is missing or not a regular file."
    assert os.access(ANALYZER, os.X_OK), f"{ANALYZER} is not executable."
    with open(ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{ANALYZER} is not a compiled ELF executable."
    assert os.path.isfile(PLOT_SCRIPT), f"{PLOT_SCRIPT} is missing or not a regular file."


def run(cmd):
    subprocess.run(cmd, check=True, timeout=20, cwd=HOME)


def expected_variance_lines(gcs):
    n = len(gcs)
    assert n > 1
    sum_x = sum(gcs)
    sum_x2 = sum(x * x for x in gcs)
    naive_var = (sum_x2 - (sum_x * sum_x) / n) / (n - 1)

    mean = 0.0
    m2 = 0.0
    for i, x in enumerate(gcs, 1):
        delta = x - mean
        mean += delta / i
        delta2 = x - mean
        m2 += delta * delta2
    welford_var = m2 / (n - 1)
    return [
        f"Total sequences: {n}",
        f"Naive variance: {naive_var:.8f}",
        f"Welford variance: {welford_var:.8f}",
    ]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_variance_results():
    """Verify that the variance results are computed correctly and written to the exact format."""
    assert_required_artifacts()
    run([ANALYZER, f"{HOME}/data.fasta"])

    results_path = "/home/user/variance_results.txt"
    assert os.path.exists(results_path), f"{results_path} is missing."

    lengths, gcs = parse_fasta("/home/user/data.fasta")
    N = len(gcs)
    assert N > 1, "Need at least two sequences to compute sample variance."

    # Compute Naive variance
    sum_x = sum(gcs)
    sum_x2 = sum(x*x for x in gcs)
    naive_var = (sum_x2 - (sum_x*sum_x)/N) / (N - 1)

    # Compute Welford variance
    mean = 0.0
    M2 = 0.0
    for i, x in enumerate(gcs, 1):
        delta = x - mean
        mean += delta / i
        delta2 = x - mean
        M2 += delta * delta2
    welford_var = M2 / (N - 1)

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {results_path}, got {len(lines)}."

    expected_line1 = f"Total sequences: {N}"
    assert lines[0] == expected_line1, f"Line 1 incorrect. Expected '{expected_line1}', got '{lines[0]}'."

    expected_naive = f"Naive variance: {naive_var:.8f}"
    assert lines[1] == expected_naive, f"Line 2 incorrect. Expected '{expected_naive}', got '{lines[1]}'."

    expected_welford = f"Welford variance: {welford_var:.8f}"
    assert lines[2] == expected_welford, f"Line 3 incorrect. Expected '{expected_welford}', got '{lines[2]}'."


def test_histogram_results():
    """Verify that the histogram matches the actual sequence lengths."""
    assert_required_artifacts()
    run([ANALYZER, f"{HOME}/data.fasta"])
    assert os.path.isfile(f"{HOME}/lengths.txt"), f"{HOME}/lengths.txt is missing."
    run(["bash", PLOT_SCRIPT])

    histogram_path = "/home/user/histogram.txt"
    assert os.path.exists(histogram_path), f"{histogram_path} is missing."

    lengths, _ = parse_fasta("/home/user/data.fasta")
    bin1 = sum(1 for l in lengths if l <= 15)
    bin2 = sum(1 for l in lengths if 15 < l <= 25)
    bin3 = sum(1 for l in lengths if l > 25)

    expected_lines = [
        f"Bin 1: {'*' * bin1}",
        f"Bin 2: {'*' * bin2}",
        f"Bin 3: {'*' * bin3}"
    ]

    with open(histogram_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {histogram_path}, got {len(lines)}."

    for i in range(3):
        assert lines[i] == expected_lines[i], (
            f"Histogram line {i+1} incorrect.\n"
            f"Expected: '{expected_lines[i]}'\n"
            f"Got: '{lines[i]}'"
        )


def test_programs_on_fresh_inputs():
    """Compile the submitted source and exercise both required programs on fresh data."""
    assert_required_artifacts()
    compiled = "/tmp/analyzer_from_source"
    run(["gcc", "-std=c11", "-O2", ANALYZER_C, "-o", compiled])

    rng = secrets.SystemRandom()
    fasta_path = "/tmp/verifier_input.fasta"
    sequences = []
    for _ in range(rng.randint(7, 12)):
        length = rng.randint(4, 43)
        seq = "".join(rng.choice("ACGT") for _ in range(length))
        sequences.append(seq)

    with open(fasta_path, "w") as f:
        for i, seq in enumerate(sequences, 1):
            f.write(f">fresh_{i}\n")
            cut = rng.randint(1, len(seq))
            f.write(seq[:cut] + "\n")
            if cut < len(seq):
                f.write(seq[cut:] + "\n")

    expected_lengths, expected_gcs = parse_fasta(fasta_path)
    expected_results = expected_variance_lines(expected_gcs)

    # Exercise the required executable, not merely pre-created result files.
    run([ANALYZER, fasta_path])
    assert read_nonempty_lines(f"{HOME}/variance_results.txt") == expected_results
    assert read_nonempty_lines(f"{HOME}/lengths.txt") == [str(x) for x in expected_lengths]

    # The submitted C source must independently compile and implement the same behavior.
    run([compiled, fasta_path])
    assert read_nonempty_lines(f"{HOME}/variance_results.txt") == expected_results
    assert read_nonempty_lines(f"{HOME}/lengths.txt") == [str(x) for x in expected_lengths]

    # Exercise the plotting script on independently generated lengths.
    histogram_lengths = [rng.randint(1, 45) for _ in range(rng.randint(9, 18))]
    with open(f"{HOME}/lengths.txt", "w") as f:
        for length in histogram_lengths:
            f.write(f"{length}\n")
    run(["bash", PLOT_SCRIPT])

    bins = [
        sum(length <= 15 for length in histogram_lengths),
        sum(15 < length <= 25 for length in histogram_lengths),
        sum(length > 25 for length in histogram_lengths),
    ]
    expected_histogram = [f"Bin {i}: {'*' * count}" for i, count in enumerate(bins, 1)]
    assert read_nonempty_lines(f"{HOME}/histogram.txt") == expected_histogram
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
