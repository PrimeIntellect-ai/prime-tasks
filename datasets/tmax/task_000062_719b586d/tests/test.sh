#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import json
import os
from pathlib import Path
import random
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY = Path('/home/user/motif_filter/target/release/motif_filter')
PROJECT_MANIFEST = Path('/home/user/motif_filter/Cargo.toml')
VENDORED_MANIFEST = Path('/app/vendored/bio-spectrum-0.1.0/Cargo.toml')
VENDORED_DIR = Path('/app/vendored/bio-spectrum-0.1.0').resolve()


def read_sequence(path):
    parts = []
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith('>'):
                parts.append(line.upper())
    return ''.join(parts)


def spectral_peak(sequence):
    values = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    signal = [values.get(base, 0.0) for base in sequence]
    n = len(signal)
    assert n > 1
    magnitudes = []
    for k in range(1, n):
        total = sum(
            value * cmath.exp(-2j * cmath.pi * k * index / n)
            for index, value in enumerate(signal)
        )
        magnitudes.append(abs(total))
    return max(magnitudes)


def cargo_metadata(manifest):
    result = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
         '--manifest-path', str(manifest)],
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_binary_exists():
    assert BINARY.exists(), f'Binary not found at {BINARY}'
    assert os.access(BINARY, os.X_OK), f'Binary at {BINARY} is not executable'


def test_vendored_library_and_project_dependency():
    assert PROJECT_MANIFEST.is_file(), f'Project manifest not found: {PROJECT_MANIFEST}'
    assert VENDORED_MANIFEST.is_file(), f'Vendored manifest not found: {VENDORED_MANIFEST}'

    vendored = cargo_metadata(VENDORED_MANIFEST)
    vendored_package = next(
        package for package in vendored['packages']
        if Path(package['manifest_path']).resolve() == VENDORED_MANIFEST.resolve()
    )
    assert any(dep['name'] == 'rustfft' for dep in vendored_package['dependencies']), \
        'The vendored bio-spectrum manifest does not declare rustfft'

    check = subprocess.run(
        ['cargo', 'check', '--offline', '--manifest-path', str(VENDORED_MANIFEST)],
        capture_output=True, text=True, timeout=180
    )
    assert check.returncode == 0, f'Vendored library does not compile:\n{check.stderr}'

    project = cargo_metadata(PROJECT_MANIFEST)
    project_package = next(
        package for package in project['packages']
        if Path(package['manifest_path']).resolve() == PROJECT_MANIFEST.resolve()
    )
    local_dependencies = [
        dep for dep in project_package['dependencies']
        if dep['name'] == 'bio-spectrum' and dep.get('path')
    ]
    assert local_dependencies, 'motif_filter does not have a local bio-spectrum dependency'
    assert any(Path(dep['path']).resolve() == VENDORED_DIR for dep in local_dependencies), \
        'motif_filter does not depend on the required vendored bio-spectrum package'

    source = '\n'.join(
        path.read_text(encoding='utf-8', errors='replace')
        for path in Path('/home/user/motif_filter/src').rglob('*.rs')
    )
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    source = re.sub(r'//.*', '', source)
    assert re.search(r'\bbio_spectrum\b', source), 'Rust source does not reference bio_spectrum'
    assert re.search(r'\bpower_spectrum\s*\(', source), \
        'Rust source does not call power_spectrum'


def test_adversarial_corpus_with_unpredictable_cases():
    clean_dir = Path('/home/user/data/clean')
    evil_dir = Path('/home/user/data/evil')
    assert clean_dir.is_dir(), f'Clean corpus path not found: {clean_dir}'
    assert evil_dir.is_dir(), f'Evil corpus path not found: {evil_dir}'

    clean_files = sorted(clean_dir.glob('*.fasta'))
    evil_files = sorted(evil_dir.glob('*.fasta'))
    assert clean_files, 'No clean files found.'
    assert evil_files, 'No evil files found.'

    clean_sequences = [read_sequence(path) for path in clean_files]
    evil_sequences = [read_sequence(path) for path in evil_files]
    clean_peaks = [spectral_peak(seq) for seq in clean_sequences]
    evil_peaks = [spectral_peak(seq) for seq in evil_sequences]
    assert max(clean_peaks) < min(evil_peaks), 'Reference corpora do not have a clean spectral boundary'
    threshold = (max(clean_peaks) + min(evil_peaks)) / 2.0

    rng = random.SystemRandom()
    bases = 'ACGT'
    generated_clean = []
    generated_evil = []

    while len(generated_clean) < 16:
        sequence = ''.join(rng.choice(bases) for _ in range(120))
        if spectral_peak(sequence) < threshold:
            generated_clean.append(sequence)

    while len(generated_evil) < 16:
        motif = ''.join(rng.choice(bases) for _ in range(6))
        if len(set(motif)) < 3:
            continue
        sequence = motif * 20
        if spectral_peak(sequence) > threshold:
            generated_evil.append(sequence)

    cases = []
    cases.extend((sequence, True) for sequence in clean_sequences)
    cases.extend((sequence, False) for sequence in evil_sequences)
    cases.extend((sequence, spectral_peak(sequence) < threshold) for sequence in generated_clean)
    cases.extend((sequence, spectral_peak(sequence) < threshold) for sequence in generated_evil)
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory() as temp_input, tempfile.TemporaryDirectory() as temp_output:
        input_dir = Path(temp_input)
        output_dir = Path(temp_output)
        expected_clean = {}
        expected_evil = set()

        for sequence, is_clean in cases:
            filename = f'{secrets.token_hex(16)}.fasta'
            content = f'>sample_{secrets.token_hex(12)}\n{sequence}\n'
            (input_dir / filename).write_text(content, encoding='utf-8')
            if is_clean:
                expected_clean[filename] = content
            else:
                expected_evil.add(filename)

        result = subprocess.run(
            [str(BINARY), str(input_dir), str(output_dir)],
            capture_output=True, text=True, timeout=120
        )
        assert result.returncode == 0, (
            f'Binary execution failed with return code {result.returncode}\n'
            f'Stdout:\n{result.stdout}\nStderr:\n{result.stderr}'
        )

        output_files = set(os.listdir(output_dir))
        clean_missing = sorted(set(expected_clean) - output_files)
        evil_bypassed = sorted(expected_evil & output_files)

        errors = []
        if evil_bypassed:
            errors.append(f'{len(evil_bypassed)} evil files bypassed')
        if clean_missing:
            errors.append(f'{len(clean_missing)} clean files rejected')
        if errors:
            pytest.fail(' | '.join(errors))

        for filename, expected_content in expected_clean.items():
            actual = (output_dir / filename).read_text(encoding='utf-8')
            assert actual == expected_content, f'Clean file was not copied unchanged: {filename}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
