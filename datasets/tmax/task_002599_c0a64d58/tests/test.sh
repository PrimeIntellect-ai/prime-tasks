#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path

CPP = Path('/home/user/pcr_pipeline.cpp')
RESULTS = Path('/home/user/simulation_results.txt')
TARGET = Path('/home/user/target.fasta')
REFERENCE = Path('/home/user/reference.fasta')
BINARY = Path('/tmp/verifier_pcr_pipeline')


def read_fasta(path):
    parts = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('>'):
                parts.append(line)
    return ''.join(parts)


def occurrences(haystack, needle):
    count = 0
    start = 0
    while True:
        pos = haystack.find(needle, start)
        if pos < 0:
            return count
        count += 1
        start = pos + 1


def expected_specific_output(target_path=TARGET, reference_path=REFERENCE):
    target = read_fasta(target_path)
    reference = read_fasta(reference_path)
    assert len(target) >= 20

    forward = target[:20]
    reverse = target[-20:].translate(str.maketrans('ACGT', 'TGCA'))[::-1]
    assert occurrences(reference, forward) == 1
    assert occurrences(reference, reverse) == 1

    a = 10.0
    cq = None
    for step in range(1, 4001):
        a += 0.01 * 1.15 * a * (1.0 - a / 1.0e9)
        if a >= 1.0e7:
            cq = step * 0.01
            break
    assert cq is not None

    return f'Forward: {forward}\nReverse: {reverse}\nCq: {cq:.2f}'


def run_pipeline(expect_success=True):
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        [str(BINARY)], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    if expect_success:
        assert proc.returncode == 0, (
            f'Pipeline exited with {proc.returncode}.\n'
            f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
        )
    assert RESULTS.is_file(), 'Running the pipeline did not create simulation_results.txt'
    return RESULTS.read_text().strip()


def write_fasta(path, header, sequence, width=47):
    lines = [f'>{header}']
    lines.extend(sequence[i:i + width] for i in range(0, len(sequence), width))
    path.write_text('\n'.join(lines) + '\n')


def make_alternate_case():
    rng = random.Random(8291)
    alphabet = 'ACGT'
    while True:
        target = ''.join(rng.choice(alphabet) for _ in range(73))
        forward = target[:20]
        reverse = target[-20:].translate(str.maketrans('ACGT', 'TGCA'))[::-1]
        reference = ''.join(rng.choice(alphabet) for _ in range(260))
        reference = reference[:35] + forward + reference[55:]
        reference = reference[:171] + reverse + reference[191:]
        if (forward != reverse and occurrences(reference, forward) == 1
                and occurrences(reference, reverse) == 1):
            return target, reference, forward


def test_pipeline_artifact_and_results():
    # Preserve the original verifier's file-existence and exact-content checks.
    assert CPP.is_file(), f'Missing required file: {CPP}'
    assert RESULTS.is_file(), f'Missing required file: {RESULTS}'
    original_expected = expected_specific_output()
    assert RESULTS.read_text().strip() == original_expected, (
        f'Content of {RESULTS} does not match Euler integration output.\n'
        f'Expected:\n{original_expected}\n\nGot:\n{RESULTS.read_text().strip()}'
    )

    compile_proc = subprocess.run(
        ['g++', '-O2', '-std=c++17', '-o', str(BINARY), str(CPP)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_proc.returncode == 0, (
        f'Failed to compile {CPP}.\nstdout:\n{compile_proc.stdout}\n'
        f'stderr:\n{compile_proc.stderr}'
    )

    # Ensure the submitted source itself generates the required original result.
    assert run_pipeline() == original_expected

    original_target = TARGET.read_bytes()
    original_reference = REFERENCE.read_bytes()
    try:
        # Exercise FASTA parsing, primer derivation, and alignment on unseen data.
        alt_target, alt_reference, alt_forward = make_alternate_case()
        write_fasta(TARGET, 'alternate_target', alt_target)
        write_fasta(REFERENCE, 'alternate_reference', alt_reference)
        alternate_expected = expected_specific_output()
        assert run_pipeline() == alternate_expected

        # Exercise the required non-specific-primer termination path.
        write_fasta(REFERENCE, 'non_specific_reference', alt_reference + 'GGG' + alt_forward)
        assert occurrences(read_fasta(REFERENCE), alt_forward) > 1
        assert run_pipeline(expect_success=False) == 'ERROR: NON-SPECIFIC PRIMERS'
    finally:
        TARGET.write_bytes(original_target)
        REFERENCE.write_bytes(original_reference)
        restored = run_pipeline()

    assert restored == original_expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
