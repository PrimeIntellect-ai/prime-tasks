#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import math
import os
import subprocess
import tempfile

SCRIPT = "/home/user/analyze_network.sh"
FASTA = "/home/user/sequences.fasta"
EDGES = "/home/user/edges.tsv"
HISTOGRAM = "/home/user/histogram.txt"


def read_fasta(path):
    sequences = {}
    current = None
    with open(path, "r") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                current = line[1:].split()[0]
                assert current and current not in sequences
                sequences[current] = ""
            else:
                assert current is not None, "Sequence data appeared before a FASTA header"
                sequences[current] += line
    return sequences


def expected_edges(path):
    sequences = read_fasta(path)
    distributions = {}
    for seq_id, sequence in sequences.items():
        assert len(sequence) >= 2
        total = len(sequence) - 1
        counts = {}
        for i in range(total):
            kmer = sequence[i:i + 2]
            counts[kmer] = counts.get(kmer, 0) + 1
        distributions[seq_id] = {k: value / total for k, value in counts.items()}

    expected = {}
    for seq1, seq2 in itertools.combinations(sorted(sequences), 2):
        kmers = set(distributions[seq1]) | set(distributions[seq2])
        distance = sum(abs(distributions[seq1].get(k, 0.0) -
                           distributions[seq2].get(k, 0.0)) for k in kmers)
        weight = 999.0 if distance == 0 else 1.0 / distance
        expected[(seq1, seq2)] = float(f"{weight:.2f}")
    return expected


def parse_edges(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]

    parsed = {}
    for line in lines:
        parts = line.split("\t")
        assert len(parts) == 3, f"Invalid format in edges.tsv: {line}"
        seq1, seq2, weight_text = parts
        assert seq1 != seq2, f"Self-comparison found in edges.tsv: {line}"
        pair = tuple(sorted((seq1, seq2)))
        assert pair not in parsed, f"Duplicate edge in edges.tsv: {pair}"
        try:
            weight = float(weight_text)
        except ValueError:
            raise AssertionError(f"Invalid weight in edges.tsv: {weight_text}")
        assert math.isfinite(weight), f"Non-finite weight in edges.tsv: {weight_text}"
        parsed[pair] = weight
    return lines, parsed


def run_script(fasta, cwd):
    result = subprocess.run(
        [SCRIPT, fasta], cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"analyze_network.sh failed with exit code {result.returncode}:\n{result.stderr}"
    )
    return os.path.join(cwd, "edges.tsv")


def assert_edges_match(path, expected):
    lines, actual = parse_edges(path)
    assert len(lines) == len(expected), (
        f"Expected {len(expected)} edges in {path}, found {len(lines)}"
    )
    assert set(actual) == set(expected), (
        f"Edge pairs differ. Expected {sorted(expected)}, got {sorted(actual)}"
    )
    for pair, expected_weight in expected.items():
        assert math.isclose(actual[pair], expected_weight, rel_tol=0, abs_tol=1e-9), (
            f"Expected weight {expected_weight:.2f} for {pair[0]}-{pair[1]}, "
            f"got {actual[pair]}"
        )
    return actual


def test_script_and_edges_tsv_correctness():
    assert os.path.isfile(SCRIPT), f"Missing script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"
    with open(SCRIPT, "r", errors="replace") as handle:
        first_line = handle.readline().strip()
    assert first_line.startswith("#!") and "bash" in first_line, (
        "analyze_network.sh must remain a Bash script"
    )

    # Exercise the submitted script on an independently derived probe, including
    # different sequences with exactly the same 2-mer distribution.
    with tempfile.TemporaryDirectory() as tmpdir:
        probe = os.path.join(tmpdir, "probe.fasta")
        with open(probe, "w") as handle:
            handle.write(">Probe1\nAAAAAA\n>Probe2\nAAAA\n>Probe3\nATATAT\n")
        probe_edges = run_script(probe, tmpdir)
        assert_edges_match(probe_edges, expected_edges(probe))

    # Run the fixed artifact on the required input and verify every pair.
    if os.path.exists(EDGES):
        os.remove(EDGES)
    generated = run_script(FASTA, "/home/user")
    assert generated == EDGES
    expected = expected_edges(FASTA)
    actual = assert_edges_match(EDGES, expected)

    # Preserve the original key assertions, with the corrected Seq1-Seq4 value.
    assert len(actual) == 6, f"Expected 6 edges in {EDGES}, found {len(actual)}"
    assert math.isclose(actual[("Seq1", "Seq2")], 999.00, rel_tol=1e-5)
    assert math.isclose(actual[("Seq1", "Seq3")], 0.50, rel_tol=1e-2)
    assert math.isclose(actual[("Seq1", "Seq4")], 0.68, rel_tol=1e-2)


def test_histogram_txt_correctness():
    assert os.path.isfile(HISTOGRAM), f"Missing file: {HISTOGRAM}"
    with open(HISTOGRAM, "r") as handle:
        lines = [line.strip() for line in handle if line.strip()]

    # Derive the histogram independently from all expected non-self edges.
    bins = {}
    for weight in expected_edges(FASTA).values():
        rounded = math.floor(weight + 0.5)
        bins[rounded] = bins.get(rounded, 0) + 1
    expected_lines = [f"{value}: {'*' * bins[value]}" for value in sorted(bins)]

    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in histogram.txt, got {len(lines)}"
    )
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, (
            f"Histogram line {i + 1} mismatch. Expected '{expected}', got '{lines[i]}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
