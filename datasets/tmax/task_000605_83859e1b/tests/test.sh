#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import random
import secrets
import stat
import subprocess


def parse_fasta(filepath):
    sequences = []
    with open(filepath, 'r') as f:
        current_id = None
        current_seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current_id is not None:
                    sequences.append((current_id, "".join(current_seq)))
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)
        if current_id is not None:
            sequences.append((current_id, "".join(current_seq)))
    return sequences


def sequence_to_signal(seq):
    mapping = {'A': 1.5, 'C': 0.5, 'G': -0.5, 'T': -1.5}
    return [mapping.get(char.upper(), 0.0) for char in seq]


def calculate_integrals(signal):
    n = len(signal)
    if n < 2:
        return 0.0, 0.0

    # Calculate I
    I = sum((signal[i] + signal[i+1]) / 2.0 for i in range(n - 1))

    # Calculate D
    D = [signal[i+1] - signal[i] for i in range(n - 1)]

    # Calculate DI
    if len(D) < 2:
        DI = 0.0
    else:
        DI = sum((abs(D[i]) + abs(D[i+1])) / 2.0 for i in range(len(D) - 1))

    return I, DI


def test_results_csv_exists():
    csv_path = "/home/user/results.csv"
    assert os.path.isfile(csv_path), f"The output CSV file {csv_path} does not exist."


def test_results_csv_content():
    fasta_path = "/home/user/sequences.fasta"
    csv_path = "/home/user/results.csv"

    assert os.path.isfile(fasta_path), f"Input FASTA file {fasta_path} is missing."
    assert os.path.isfile(csv_path), f"Output CSV file {csv_path} is missing."

    sequences = parse_fasta(fasta_path)
    expected_results = []
    for seq_id, seq in sequences:
        signal = sequence_to_signal(seq)
        I, DI = calculate_integrals(signal)
        expected_results.append({
            'ID': seq_id,
            'I': f"{I:.2f}",
            'DI': f"{DI:.2f}"
        })

    actual_results = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['ID', 'I', 'DI'], f"CSV header is incorrect. Expected ['ID', 'I', 'DI'], got {reader.fieldnames}"
        for row in reader:
            actual_results.append(row)

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} rows in CSV, but found {len(actual_results)}."

    for i, (expected, actual) in enumerate(zip(expected_results, actual_results)):
        assert actual['ID'] == expected['ID'], f"Row {i+1}: Expected ID '{expected['ID']}', got '{actual['ID']}'."
        assert actual['I'] == expected['I'], f"Row {i+1} ({expected['ID']}): Expected I={expected['I']}, got I={actual['I']}."
        assert actual['DI'] == expected['DI'], f"Row {i+1} ({expected['ID']}): Expected DI={expected['DI']}, got DI={actual['DI']}."


def check_csv_for_sequences(csv_path, sequences):
    expected_results = []
    for seq_id, seq in sequences:
        I, DI = calculate_integrals(sequence_to_signal(seq))
        expected_results.append({'ID': seq_id, 'I': f"{I:.2f}", 'DI': f"{DI:.2f}"})

    assert os.path.isfile(csv_path), "The compiled program did not create /home/user/results.csv."
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['ID', 'I', 'DI'], f"CSV header is incorrect after executing process.go: {reader.fieldnames}"
        actual_results = list(reader)

    assert len(actual_results) == len(expected_results), (
        f"Executed program produced {len(actual_results)} rows; expected {len(expected_results)}."
    )
    for i, (expected, actual) in enumerate(zip(expected_results, actual_results)):
        assert actual['ID'] == expected['ID'], f"Executed program row {i+1} has the wrong ID."
        assert actual['I'] == expected['I'], f"Executed program row {i+1} has the wrong I value."
        assert actual['DI'] == expected['DI'], f"Executed program row {i+1} has the wrong DI value."


def make_random_fasta(rng):
    alphabet = "ACGTNXYZ"
    sequences = []
    lines = []
    for index in range(7):
        seq_id = f"hidden_{index}_{secrets.token_hex(6)}"
        length = rng.randint(3, 30)
        seq = ''.join(rng.choice(alphabet) for _ in range(length))
        sequences.append((seq_id, seq))
        lines.append('>' + seq_id)
        position = 0
        while position < len(seq):
            width = rng.randint(1, 6)
            lines.append(seq[position:position + width])
            position += width
    return sequences, '\n'.join(lines) + '\n'


def test_process_go_compiles_and_generates_results_for_unseen_inputs():
    source_path = "/home/user/process.go"
    fasta_path = "/home/user/sequences.fasta"
    csv_path = "/home/user/results.csv"
    executable = f"/tmp/process_submission_{secrets.token_hex(8)}"

    assert os.path.exists(source_path), f"Required Go source file {source_path} does not exist."
    source_stat = os.stat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), f"{source_path} is not a regular file."
    assert source_stat.st_size > 0, f"{source_path} is empty."

    build = subprocess.run(
        ["go", "build", "-o", executable, source_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"process.go does not compile:\n{build.stderr}"
    assert os.path.isfile(executable), "Compiling process.go did not produce an executable."

    original_fasta = open(fasta_path, 'rb').read()
    original_csv = open(csv_path, 'rb').read() if os.path.exists(csv_path) else None
    rng = random.SystemRandom()

    try:
        for _ in range(2):
            sequences, fasta_contents = make_random_fasta(rng)
            with open(fasta_path, 'w') as f:
                f.write(fasta_contents)
            if os.path.exists(csv_path):
                os.remove(csv_path)

            run = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert run.returncode == 0, f"Compiled process.go failed when executed:\n{run.stderr}"
            check_csv_for_sequences(csv_path, sequences)
    finally:
        with open(fasta_path, 'wb') as f:
            f.write(original_fasta)
        if original_csv is None:
            if os.path.exists(csv_path):
                os.remove(csv_path)
        else:
            with open(csv_path, 'wb') as f:
                f.write(original_csv)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
