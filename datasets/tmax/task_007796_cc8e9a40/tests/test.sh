#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def get_expected_output(fasta_path):
    with open(fasta_path, 'r') as f:
        lines = f.readlines()

    seqs = []
    current_seq = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith('>'):
            if current_seq:
                seqs.append("".join(current_seq))
                current_seq = []
        else:
            current_seq.append(line)
    if current_seq:
        seqs.append("".join(current_seq))

    gc_contents = []
    for seq in seqs:
        gc = sum(1 for c in seq if c in 'GCgc')
        gc_contents.append(gc / len(seq) if len(seq) > 0 else 0)

    n = len(gc_contents)
    if n == 0:
        return ""

    sample_mean = sum(gc_contents) / n

    r = 42
    means = []
    for _ in range(1000):
        s = 0
        for _ in range(n):
            r = (r * 1103515245 + 12345) & 0x7FFFFFFF
            idx = r % n
            s += gc_contents[idx]
        means.append(s / n)
    means.sort()

    return f"Sample Mean: {sample_mean:.4f}\n95% CI: {means[25]:.4f} to {means[975]:.4f}"


def get_dynamic_expected(fasta_path):
    seqs = []
    current = None
    with open(fasta_path, 'r') as f:
        for raw in f:
            stripped = raw.strip()
            if not stripped:
                continue
            if stripped.startswith('>'):
                if current is not None:
                    seqs.append(''.join(current))
                current = []
            else:
                if current is not None:
                    current.extend(c for c in raw if not c.isspace())
    if current is not None:
        seqs.append(''.join(current))

    values = []
    for seq in seqs:
        values.append(sum(c in 'GCgc' for c in seq) / len(seq) if seq else 0.0)

    n = len(values)
    assert n > 0
    mean = sum(values) / n
    r = 42
    boot = []
    for _ in range(1000):
        total = 0.0
        for _ in range(n):
            r = (r * 1103515245 + 12345) & 0x7FFFFFFF
            total += values[r % n]
        boot.append(total / n)
    boot.sort()
    return f"Sample Mean: {mean:.4f}\n95% CI: {boot[25]:.4f} to {boot[975]:.4f}"


def test_cpp_source_exists():
    assert os.path.isfile('/home/user/process_fasta.cpp'), '/home/user/process_fasta.cpp does not exist.'


def test_cpp_executable_exists():
    assert os.path.isfile('/home/user/process_fasta'), '/home/user/process_fasta executable does not exist.'
    assert os.access('/home/user/process_fasta', os.X_OK), '/home/user/process_fasta is not executable.'


def test_gc_summary_output():
    fasta_path = '/home/user/data/input.fasta'
    summary_path = '/home/user/gc_summary.txt'
    assert os.path.isfile(summary_path), f'{summary_path} does not exist.'
    expected_text = get_expected_output(fasta_path)
    with open(summary_path, 'r') as f:
        actual_text = f.read().strip()
    assert actual_text == expected_text, f'The contents of {summary_path} do not match the expected output.\nExpected:\n{expected_text}\nActual:\n{actual_text}'


def make_case(n, add_whitespace):
    alphabet = 'ACGT'
    lines = []
    for i in range(n):
        length = 5 + secrets.randbelow(31)
        seq = ''.join(alphabet[secrets.randbelow(4)] for _ in range(length))
        # Ensure the test set contains varied GC proportions regardless of random draws.
        if i == 0:
            seq = 'G' * length
        elif i == 1:
            seq = 'A' * length
        lines.append(f'>hidden_{i}_{secrets.token_hex(4)}')
        pos = 0
        while pos < len(seq):
            width = 1 + secrets.randbelow(min(9, len(seq) - pos))
            chunk = seq[pos:pos + width]
            if add_whitespace and len(chunk) > 2 and secrets.randbelow(2) == 0:
                chunk = chunk[:1] + ' \t' + chunk[1:]
            lines.append(chunk)
            if secrets.randbelow(5) == 0:
                lines.append('')
            pos += width
    return '\n'.join(lines) + '\n'


def run_and_check(binary, expected):
    summary = '/home/user/gc_summary.txt'
    if os.path.exists(summary):
        os.unlink(summary)
    proc = subprocess.run(
        [binary], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert proc.returncode == 0, f'{binary} failed with code {proc.returncode}: {proc.stderr}'
    if os.path.isfile(summary):
        with open(summary, 'r') as f:
            actual = f.read().strip()
    else:
        actual = proc.stdout.strip()
    assert actual == expected, f'{binary} produced incorrect output.\nExpected:\n{expected}\nActual:\n{actual}'


def test_program_on_unseen_inputs_and_rebuild_source():
    rebuilt = '/tmp/process_fasta_rebuilt'
    compile_proc = subprocess.run(
        ['g++', '-O2', '/home/user/process_fasta.cpp', '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_proc.returncode == 0, f'C++ source did not compile: {compile_proc.stderr}'

    fasta = '/home/user/data/input.fasta'
    summary = '/home/user/gc_summary.txt'
    with open(fasta, 'rb') as f:
        original_fasta = f.read()
    original_summary = None
    if os.path.isfile(summary):
        with open(summary, 'rb') as f:
            original_summary = f.read()

    try:
        cases = [make_case(3, False), make_case(7, True), make_case(11, True)]
        for content in cases:
            with open(fasta, 'w') as f:
                f.write(content)
            expected = get_dynamic_expected(fasta)
            run_and_check('/home/user/process_fasta', expected)
            run_and_check(rebuilt, expected)
    finally:
        with open(fasta, 'wb') as f:
            f.write(original_fasta)
        if original_summary is not None:
            with open(summary, 'wb') as f:
                f.write(original_summary)
        elif os.path.exists(summary):
            os.unlink(summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
