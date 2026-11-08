#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/primer_filter.py"
TARGET = "ATGCGTACGTAGCTAGCTAGCTGATCGATCGTAGCTAGCTAGCTGACTGACTAGCTAGCTAG"
MC_ITERS = "5000"
THRESH = "0.15"

CLEAN_DIR = "/app/corpora/clean/"
EVIL_DIR = "/app/corpora/evil/"


def parse_fasta(path):
    if not os.path.exists(path):
        return []
    with open(path, 'r') as f:
        lines = f.readlines()
    seqs = []
    curr_seq = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith('>'):
            if curr_seq:
                seqs.append("".join(curr_seq))
                curr_seq = []
        else:
            curr_seq.append(line)
    if curr_seq:
        seqs.append("".join(curr_seq))
    return seqs


def run_filter(records, target, mc_iters, thresh):
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.fasta")
        output_path = os.path.join(td, "output.fasta")
        with open(input_path, "w") as f:
            for name, seq in records:
                f.write(f">{name}\n{seq}\n")
        result = subprocess.run([
            "python3", SCRIPT_PATH,
            "--input", input_path,
            "--output", output_path,
            "--target", target,
            "--mc-iters", str(mc_iters),
            "--thresh", str(thresh),
        ], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "Script did not create the requested output file"
        return parse_fasta(output_path)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"


def test_clean_corpus_preserved():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.fasta')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for fname in clean_files:
        input_path = os.path.join(CLEAN_DIR, fname)
        with tempfile.NamedTemporaryFile(suffix=".fasta", delete=False) as tmp:
            output_path = tmp.name

        cmd = [
            "python3", SCRIPT_PATH,
            "--input", input_path,
            "--output", output_path,
            "--target", TARGET,
            "--mc-iters", MC_ITERS,
            "--thresh", THRESH
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            failed_files.append((fname, f"Script crashed with returncode {result.returncode}"))
            continue

        input_seqs = parse_fasta(input_path)
        output_seqs = parse_fasta(output_path)

        if input_seqs != output_seqs:
            failed_files.append((fname, "Output sequences do not match input sequences (clean sequences were modified or rejected)."))

        if os.path.exists(output_path):
            os.remove(output_path)

    if failed_files:
        msg = f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected.\n"
        for fname, err in failed_files:
            msg += f" - {fname}: {err}\n"
        pytest.fail(msg)


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.fasta')]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for fname in evil_files:
        input_path = os.path.join(EVIL_DIR, fname)
        with tempfile.NamedTemporaryFile(suffix=".fasta", delete=False) as tmp:
            output_path = tmp.name

        cmd = [
            "python3", SCRIPT_PATH,
            "--input", input_path,
            "--output", output_path,
            "--target", TARGET,
            "--mc-iters", MC_ITERS,
            "--thresh", THRESH
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            failed_files.append((fname, f"Script crashed with returncode {result.returncode}"))
            continue

        output_seqs = parse_fasta(output_path)

        if len(output_seqs) > 0:
            failed_files.append((fname, "Output sequences are not empty (evil sequences bypassed)."))

        if os.path.exists(output_path):
            os.remove(output_path)

    if failed_files:
        msg = f"{len(failed_files)} of {len(evil_files)} evil files bypassed.\n"
        for fname, err in failed_files:
            msg += f" - {fname}: {err}\n"
        pytest.fail(msg)


def test_unseen_target_alignment_uses_supplied_target():
    bases = "ACGT"
    base = secrets.choice(bases)
    complement = {"A": "T", "T": "A", "C": "G", "G": "C"}[base]
    length = 8 + secrets.randbelow(5)
    safe = base * length
    off_target = complement * length
    custom_target = base * (length + 25)

    output = run_filter(
        [("unseen_safe", safe), ("unseen_off_target", off_target)],
        custom_target,
        311 + secrets.randbelow(100),
        0.15,
    )
    assert output == [safe], "An unseen on-target primer must be accepted and an unseen off-target primer rejected"


def make_self_complementary(length):
    comp = str.maketrans("ACGT", "TGCA")
    half = "".join(secrets.choice("ACGT") for _ in range(length // 2))
    return half + half.translate(comp)[::-1]


def test_unseen_monte_carlo_dimer_filter_and_threshold():
    lengths = (16, 20, 24)
    dimers = [make_self_complementary(n) for n in lengths]
    records = [(f"hidden_dimer_{i}", seq) for i, seq in enumerate(dimers)]
    custom_target = "AAAAA".join(dimers)
    iterations = 1700 + secrets.randbelow(601)

    # For these reverse-complement palindromes every overlap is complementary.
    # The expected mean overlap fraction is (4+n)/(2n), comfortably above 0.5.
    low_threshold_output = run_filter(records, custom_target, iterations, 0.5)
    assert low_threshold_output == [], "Aligned primers with strong simulated self-binding must be rejected"

    # The same simulated means are comfortably below 0.9, so changing the CLI
    # threshold must change their classification.
    high_threshold_output = run_filter(records, custom_target, iterations, 0.9)
    assert high_threshold_output == dimers, "The supplied Monte Carlo threshold must control dimer rejection"


def test_threshold_comparison_is_greater_than_or_equal():
    base = secrets.choice("ACGT")
    primer = base * (8 + secrets.randbelow(5))
    output = run_filter([("zero_score", primer)], primer, 73, 0.0)
    assert output == [], "A mean binding fraction equal to the threshold must be rejected"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
