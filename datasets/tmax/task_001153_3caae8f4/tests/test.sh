#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import secrets
import subprocess

AAS = ['A', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'V', 'W', 'Y']
N_VALUES = [100, 500, 1000, 2000]

def expected_from_records(records, n):
    counts = {aa: 0 for aa in AAS}
    total = 0
    for sequence in records[:n]:
        for char in sequence:
            if char in counts:
                counts[char] += 1
                total += 1
    kl = 0.0
    for aa in AAS:
        if total:
            p = counts[aa] / total
            if p > 0:
                kl += p * math.log(p / 0.05)
    return kl

def records_from_fasta(path):
    records = []
    current = None
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if line.startswith('>'):
                if current is not None:
                    records.append(current)
                current = ''
            elif line:
                if current is None:
                    current = ''
                current += line
    if current is not None:
        records.append(current)
    return records

def test_source_code_exists():
    assert os.path.exists('/home/user/analyze_dist.cpp'), 'Source code /home/user/analyze_dist.cpp is missing'

def test_executable_exists():
    path = '/home/user/analyze_dist'
    assert os.path.exists(path), 'Executable /home/user/analyze_dist is missing'
    assert os.access(path, os.X_OK), 'Executable /home/user/analyze_dist is not executable'
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Executable is not a compiled ELF program'

def test_convergence_results():
    fasta_path = '/home/user/sequences.fasta'
    assert os.path.exists(fasta_path), f'{fasta_path} is missing'
    records = records_from_fasta(fasta_path)
    expected_kls = {n: expected_from_records(records, n) for n in N_VALUES}

    csv_path = '/home/user/convergence_results.csv'
    assert os.path.exists(csv_path), f'{csv_path} is missing'
    with open(csv_path) as f:
        csv_lines = [line.strip() for line in f if line.strip()]

    assert len(csv_lines) == 5, f'Expected 5 lines in CSV (header + 4 rows), got {len(csv_lines)}'
    assert csv_lines[0] == 'N,KL_Divergence', f"Expected header 'N,KL_Divergence', got '{csv_lines[0]}'"
    for i, n in enumerate(N_VALUES):
        parts = csv_lines[i + 1].split(',')
        assert len(parts) == 2, f'Expected 2 columns in row {i + 1}, got {len(parts)}'
        assert parts[0] == str(n), f'Expected N={n} in row {i + 1}, got {parts[0]}'
        try:
            actual_kl = float(parts[1])
        except ValueError:
            assert False, f"Could not parse KL_Divergence value '{parts[1]}' as float"
        expected_kl = expected_kls[n]
        assert abs(actual_kl - expected_kl) < 1e-5, f'Expected KL divergence for N={n} to be ~{expected_kl:.6f}, got {actual_kl}'

def test_hypothesis_file():
    hyp_path = '/home/user/hypothesis.txt'
    assert os.path.exists(hyp_path), f'{hyp_path} is missing'
    with open(hyp_path) as f:
        content = f.read().strip()
    records = records_from_fasta('/home/user/sequences.fasta')
    expected = 'H1' if expected_from_records(records, 2000) > 0.005 else 'H0'
    assert content == expected, f"Expected hypothesis.txt to contain '{expected}', got '{content}'"

def make_fixture(biased):
    records = []
    for i in range(2000):
        length = 18 + secrets.randbelow(20)
        sequence = []
        for _ in range(length):
            if biased and secrets.randbelow(100) < 22:
                sequence.append('A')
            else:
                sequence.append(secrets.choice(AAS))
        if i % 13 == 0:
            sequence.insert(secrets.randbelow(len(sequence) + 1), 'X')
        records.append(''.join(sequence))
    return records

def write_fixture(records):
    with open('/home/user/sequences.fasta', 'w') as f:
        for i, sequence in enumerate(records):
            f.write(f'>verification_{i}\n{sequence}\n')

def check_generated_outputs(records):
    with open('/home/user/convergence_results.csv') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 5
    assert lines[0] == 'N,KL_Divergence'
    for i, n in enumerate(N_VALUES):
        parts = lines[i + 1].split(',')
        assert parts[0] == str(n)
        assert len(parts) == 2
        expected = expected_from_records(records, n)
        assert parts[1] == f'{expected:.6f}', f'Incorrect generated KL for N={n}: {parts[1]}'
    with open('/home/user/hypothesis.txt') as f:
        hypothesis = f.read().strip()
    final_kl = expected_from_records(records, 2000)
    assert hypothesis == ('H1' if final_kl > 0.005 else 'H0')

def test_tools_execute_and_recompute_outputs():
    built = '/tmp/analyze_dist_from_source'
    result = subprocess.run(
        ['g++', '-std=c++17', '-o', built, '/home/user/analyze_dist.cpp'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, f'Source failed to compile: {result.stderr}'

    paths = ['/home/user/sequences.fasta', '/home/user/convergence_results.csv', '/home/user/hypothesis.txt']
    backups = {}
    for path in paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    try:
        for program, biased in [('/home/user/analyze_dist', False), (built, True)]:
            records = make_fixture(biased)
            write_fixture(records)
            for output in paths[1:]:
                if os.path.exists(output):
                    os.remove(output)
            run = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            assert run.returncode == 0, f'{program} failed when executed: {run.stderr}'
            assert os.path.exists(paths[1]), f'{program} did not generate convergence_results.csv'
            assert os.path.exists(paths[2]), f'{program} did not generate hypothesis.txt'
            check_generated_outputs(records)
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
