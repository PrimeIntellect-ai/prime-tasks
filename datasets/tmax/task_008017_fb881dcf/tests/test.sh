#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

AA_LIST = "A C D E F G H I K L M N P Q R S T V W Y".split()
SCORE_RE = re.compile(r"-?\d+\.\d{3}")


def parse_fasta(filepath):
    sequences = []
    current_seq = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_seq:
                    sequences.append("".join(current_seq))
                    current_seq = []
            else:
                current_seq.append(line)
        if current_seq:
            sequences.append("".join(current_seq))
    return sequences


def expected_pwm(sequences):
    assert sequences
    seq_len = len(sequences[0])
    assert all(len(seq) == seq_len for seq in sequences)
    n = len(sequences)
    result = []
    for i in range(seq_len):
        counts = {aa: 0 for aa in AA_LIST}
        for seq in sequences:
            if i < len(seq) and seq[i] in counts:
                counts[seq[i]] += 1
        result.append([
            math.log2((((counts[aa] + 1) / (n + 20))) / 0.05)
            for aa in AA_LIST
        ])
    return result


def assert_pwm_text(text, expected):
    lines = [line for line in text.splitlines() if line.strip()]
    assert len(lines) == len(expected), f"Expected {len(expected)} rows, got {len(lines)}"
    for i, line in enumerate(lines):
        parts = line.split('\t')
        assert len(parts) == 21, f"Expected 21 columns in row {i+1}, got {len(parts)}"
        assert parts[0] == str(i + 1), f"Expected row index {i+1}, got {parts[0]}"
        for j, expected_score in enumerate(expected[i]):
            token = parts[j + 1]
            assert SCORE_RE.fullmatch(token), \
                f"Row {i+1}, AA {AA_LIST[j]} is not formatted to exactly 3 decimal places: {token!r}"
            actual_score = float(token)
            assert abs(actual_score - expected_score) < 0.005, \
                f"Row {i+1}, AA {AA_LIST[j]}: expected {expected_score:.3f}, got {actual_score}"


def test_smoothed_pwm_format_and_values():
    alignment_path = "/home/user/alignment.fasta"
    pwm_path = "/home/user/smoothed_pwm.txt"

    assert os.path.isfile(alignment_path), f"Missing {alignment_path}"
    assert os.path.isfile(pwm_path), f"Missing {pwm_path}"

    sequences = parse_fasta(alignment_path)
    assert len(sequences) > 0, "No sequences found in alignment.fasta"

    seq_len = len(sequences[0])
    N = len(sequences)

    expected = []
    for i in range(seq_len):
        counts = {aa: 0 for aa in AA_LIST}
        for seq in sequences:
            if i < len(seq):
                aa = seq[i]
                if aa in counts:
                    counts[aa] += 1

        row_scores = []
        for aa in AA_LIST:
            p = (counts[aa] + 1) / (N + 20)
            score = math.log2(p / 0.05)
            row_scores.append(score)
        expected.append(row_scores)

    with open(pwm_path, 'r') as f:
        text = f.read()

    assert_pwm_text(text, expected)


def test_target_score():
    alignment_path = "/home/user/alignment.fasta"
    target_path = "/home/user/target.fasta"
    score_path = "/home/user/target_score.txt"

    assert os.path.isfile(alignment_path), f"Missing {alignment_path}"
    assert os.path.isfile(target_path), f"Missing {target_path}"
    assert os.path.isfile(score_path), f"Missing {score_path}"

    sequences = parse_fasta(alignment_path)
    target_seqs = parse_fasta(target_path)

    assert len(target_seqs) > 0, "No sequences found in target.fasta"
    target_seq = target_seqs[0]

    N = len(sequences)
    expected_total_score = 0.0
    for i, aa in enumerate(target_seq):
        count = 0
        for seq in sequences:
            if i < len(seq) and seq[i] == aa:
                count += 1
        p = (count + 1) / (N + 20)
        expected_total_score += math.log2(p / 0.05)

    with open(score_path, 'r') as f:
        content = f.read().strip()

    assert re.fullmatch(r"[+-]?\d+\.\d{3}", content), \
        f"Target score is not formatted to exactly 3 decimal places: {content!r}"
    try:
        actual_score = float(content)
    except ValueError:
        assert False, f"Could not parse target score as float: {content}"

    assert abs(actual_score - expected_total_score) < 0.005, \
        f"Expected target score {expected_total_score:.3f}, got {actual_score}"


def run_model(script_path, alignment_path):
    proc = subprocess.run(
        [script_path, alignment_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, \
        f"calc_pwm.sh failed with status {proc.returncode}: {proc.stderr}"
    return proc.stdout


def test_calc_pwm_script_is_fixed_and_executable():
    script_path = "/home/user/calc_pwm.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"
    with open(script_path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), \
        "calc_pwm.sh must be a Bash script"

    reference_output = run_model(script_path, "/home/user/alignment.fasta")
    with open("/home/user/smoothed_pwm.txt", "r") as f:
        submitted_output = f.read()
    assert reference_output.strip() == submitted_output.strip(), \
        "Running calc_pwm.sh on alignment.fasta does not reproduce smoothed_pwm.txt"
    assert_pwm_text(reference_output, expected_pwm(parse_fasta("/home/user/alignment.fasta")))

    # Exercise the submitted script on fresh, unpredictable alignments so a
    # precomputed reference output cannot stand in for the required pipeline.
    for case in range(2):
        n = 4 + secrets.randbelow(4)
        length = 4 + secrets.randbelow(5)
        sequences = []
        for row in range(n):
            seq = ["A"]  # Include a fully conserved position.
            for pos in range(1, length):
                seq.append(secrets.choice(AA_LIST))
            sequences.append("".join(seq))

        with tempfile.TemporaryDirectory() as tempdir:
            path = os.path.join(tempdir, f"alignment_{case}.fasta")
            with open(path, "w") as f:
                for i, seq in enumerate(sequences):
                    f.write(f">random_{case}_{i}\n{seq}\n")
            output = run_model(script_path, path)
            assert_pwm_text(output, expected_pwm(sequences))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
