#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

LIBDIR = Path('/app/libkmer-svd-1.2.0')
SO = LIBDIR / 'libkmer-svd.so'
BIN = Path('/home/user/seq_filter')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def filter_output(path, timeout=5):
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(LIBDIR) + ':' + env.get('LD_LIBRARY_PATH', '')
    result = subprocess.run([str(BIN), str(path)], env=env, text=True,
                            capture_output=True, timeout=timeout)
    assert result.returncode == 0, f'{BIN} failed for {path}: {result.stderr}'
    value = result.stdout.strip()
    assert value in ('ACCEPT', 'REJECT'), f'Invalid output for {path}: {result.stdout!r}'
    return value


def dft_ratio(seq):
    signal = [1.0 if c in 'GC' else 0.0 for c in seq]
    n = len(signal)
    total = 0.0
    high = 0.0
    for k in range(n):
        real = 0.0
        imag = 0.0
        for j, x in enumerate(signal):
            angle = -2.0 * math.pi * k * j / n
            real += x * math.cos(angle)
            imag += x * math.sin(angle)
        magnitude = math.hypot(real, imag)
        total += magnitude
        if k > n / 4.0:
            high += magnitude
    return high / total if total > 0.0 else 0.0


def transition_matrix(seq):
    order = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
    matrix = [[0.0] * 4 for _ in range(4)]
    for a, b in zip(seq, seq[1:]):
        matrix[order[a]][order[b]] += 1.0
    for row in matrix:
        s = sum(row)
        if s:
            for j in range(4):
                row[j] /= s
    return matrix


def symmetric_eigenvalues(a):
    a = [row[:] for row in a]
    n = len(a)
    for _ in range(200):
        p, q = 0, 1
        largest = 0.0
        for i in range(n):
            for j in range(i + 1, n):
                if abs(a[i][j]) > largest:
                    largest = abs(a[i][j])
                    p, q = i, j
        if largest < 1e-13:
            break
        phi = 0.5 * math.atan2(2.0 * a[p][q], a[q][q] - a[p][p])
        c, s = math.cos(phi), math.sin(phi)
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        for i in range(n):
            if i not in (p, q):
                aip, aiq = a[i][p], a[i][q]
                a[i][p] = a[p][i] = c * aip - s * aiq
                a[i][q] = a[q][i] = s * aip + c * aiq
        a[p][p] = c*c*app - 2*c*s*apq + s*s*aqq
        a[q][q] = s*s*app + 2*c*s*apq + c*c*aqq
        a[p][q] = a[q][p] = 0.0
    return [a[i][i] for i in range(n)]


def reference_condition(seq):
    m = transition_matrix(seq)
    ata = [[sum(m[k][i] * m[k][j] for k in range(4))
            for j in range(4)] for i in range(4)]
    vals = [max(0.0, x) for x in symmetric_eigenvalues(ata)]
    largest = max(vals)
    smallest = min(vals)
    if largest == 0.0 or smallest <= largest * 1e-12:
        return math.inf
    return math.sqrt(largest / smallest)


def reference_label(seq):
    return 'REJECT' if dft_ratio(seq) < 0.10 or reference_condition(seq) > 1000.0 else 'ACCEPT'


def write_fasta(path, seq, rng, add_decoy=True):
    widths = []
    left = len(seq)
    while left:
        width = min(left, rng.randint(7, 19))
        widths.append(width)
        left -= width
    lines = ['>random_' + secrets.token_hex(8)]
    pos = 0
    for width in widths:
        lines.append(seq[pos:pos + width])
        pos += width
    if add_decoy:
        lines.extend(['>ignored_second_sequence', 'A' * 53])
    path.write_text('\n'.join(lines) + '\n')


def random_high_frequency_sequence(rng):
    for _ in range(1000):
        n = rng.randint(43, 79)
        seq = ''.join(rng.choice('ACGT') for _ in range(n))
        if dft_ratio(seq) > 0.20 and reference_condition(seq) < 100.0:
            return seq
    raise AssertionError('Could not generate a suitable randomized sequence')


def compile_stub(destination, value, workdir):
    source = Path(workdir) / ('stub_' + secrets.token_hex(6) + '.c')
    source.write_text(
        'double kmer_matrix_condition_number(double *m, int n) '
        '{ (void)m; (void)n; return ' + repr(float(value)) + '; }\n'
    )
    subprocess.run(['gcc', '-shared', '-fPIC', str(source), '-o', str(destination)], check=True)


def test_makefile_fixed():
    makefile_path = LIBDIR / 'Makefile'
    assert makefile_path.is_file(), f'Makefile {makefile_path} is missing.'
    content = makefile_path.read_text()
    assert '-fPIC' in content, 'Makefile is still missing the -fPIC flag.'
    assert '-lm' in content, 'Makefile is still missing the -lm flag for math library linking.'


def test_library_compiled():
    assert SO.is_file(), f'Shared library {SO} was not compiled or is missing.'


def test_seq_filter_exists():
    assert Path('/home/user/seq_filter.c').is_file(), 'Source /home/user/seq_filter.c is missing.'
    assert BIN.is_file(), f'Executable {BIN} is missing.'
    assert os.access(BIN, os.X_OK), f'File {BIN} is not executable.'


def test_makefile_really_builds_and_library_api_works(tmp_path):
    subprocess.run(['make', 'clean'], cwd=LIBDIR, check=True, capture_output=True, text=True)
    subprocess.run(['make'], cwd=LIBDIR, check=True, capture_output=True, text=True)
    assert SO.is_file()
    elf = run(['readelf', '-h', str(SO)]).stdout
    assert 'DYN (Shared object file)' in elf, 'libkmer-svd.so is not a shared ELF library'

    harness = tmp_path / 'api_test.c'
    harness.write_text(r'''#include <stdio.h>
extern double kmer_matrix_condition_number(double *, int);
int main(void) {
    double identity[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
    double diagonal[16] = {1,0,0,0, 0,2,0,0, 0,0,4,0, 0,0,0,8};
    double ill[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,0.000001};
    printf("%.17g %.17g %.17g\n",
      kmer_matrix_condition_number(identity, 4),
      kmer_matrix_condition_number(diagonal, 4),
      kmer_matrix_condition_number(ill, 4));
    return 0;
}
''')
    exe = tmp_path / 'api_test'
    subprocess.run(['gcc', str(harness), '-L' + str(LIBDIR), '-Wl,-rpath,' + str(LIBDIR),
                    '-l:libkmer-svd.so', '-lm', '-o', str(exe)], check=True)
    vals = [float(x) for x in run([str(exe)]).stdout.split()]
    assert len(vals) == 3
    assert abs(vals[0] - 1.0) < 1e-6, f'identity condition number was {vals[0]}'
    assert abs(vals[1] - 8.0) < 1e-4, f'diagonal condition number was {vals[1]}'
    assert vals[2] > 1000.0, f'near-singular matrix condition number was {vals[2]}'


def test_filter_is_dynamically_linked_to_required_api():
    dynamic = run(['readelf', '-d', str(BIN)]).stdout
    assert 'libkmer-svd.so' in dynamic, 'seq_filter is not dynamically linked to libkmer-svd.so'
    symbols = run(['nm', '-D', str(BIN)]).stdout
    assert re.search(r'\bU\s+kmer_matrix_condition_number(?:@|\s|$)', symbols), \
        'seq_filter does not import kmer_matrix_condition_number from the shared library'


def test_randomized_filter_behavior_and_library_use(tmp_path):
    rng = random.Random(secrets.randbits(128))
    cases_dir = tmp_path / ('evil_clean_misleading_' + secrets.token_hex(8))
    cases_dir.mkdir()

    # Inputs and paths are generated only after the submission is complete.
    actual_cases = []
    for i in range(6):
        seq = random_high_frequency_sequence(rng)
        path = cases_dir / ('evil_should_reject_' + secrets.token_hex(6) + '.fasta')
        write_fasta(path, seq, rng)
        actual_cases.append((path, 'ACCEPT'))
    for i in range(6):
        for _ in range(1000):
            n = rng.randint(45, 83)
            seq = ''.join(rng.choice('AG') for _ in range(n))
            if dft_ratio(seq) > 0.20:
                break
        assert reference_label(seq) == 'REJECT'
        path = cases_dir / ('clean_should_accept_' + secrets.token_hex(6) + '.fasta')
        write_fasta(path, seq, rng)
        actual_cases.append((path, 'REJECT'))

    for path, expected in actual_cases:
        assert filter_output(path) == expected, \
            f'Wrong result for randomized content {path.name}; expected {expected}'

    # Swap in ABI-compatible libraries to isolate the DFT decision and verify
    # that the executable uses the library's returned condition number.
    original = SO.read_bytes()
    original_mode = SO.stat().st_mode
    try:
        high = random_high_frequency_sequence(rng)
        high_path = cases_dir / ('low_complexity_name_' + secrets.token_hex(6) + '.fasta')
        write_fasta(high_path, high, rng)

        low = ''.join(rng.choice('CG') for _ in range(rng.randint(51, 91)))
        assert dft_ratio(low) < 1e-9
        low_path = cases_dir / ('clean_random_name_' + secrets.token_hex(6) + '.fasta')
        write_fasta(low_path, low, rng)

        stub = tmp_path / 'stub.so'
        compile_stub(stub, 1.0, tmp_path)
        shutil.copyfile(stub, SO)
        assert filter_output(high_path) == 'ACCEPT'
        assert filter_output(low_path) == 'REJECT', 'Low-frequency signal was not rejected'

        compile_stub(stub, 1000.0, tmp_path)
        shutil.copyfile(stub, SO)
        assert filter_output(high_path) == 'ACCEPT', 'Condition number exactly 1000 must be accepted'

        compile_stub(stub, 1001.0, tmp_path)
        shutil.copyfile(stub, SO)
        assert filter_output(high_path) == 'REJECT', 'Condition number above 1000 was not rejected'
    finally:
        SO.write_bytes(original)
        os.chmod(SO, original_mode)


def test_evil_corpus_rejected():
    evil_dir = '/home/user/data/evil'
    evil_files = glob.glob(os.path.join(evil_dir, '*.fasta'))
    assert len(evil_files) > 0, f'No evil files found in {evil_dir}.'
    bypassed = []
    for path in evil_files:
        try:
            out = filter_output(path)
            if out != 'REJECT':
                bypassed.append((os.path.basename(path), out))
        except Exception as exc:
            bypassed.append((os.path.basename(path), str(exc)))
    if bypassed:
        details = ', '.join(f"'{name}' (output: {out})" for name, out in bypassed)
        pytest.fail(f'{len(bypassed)} of {len(evil_files)} evil bypassed: {details}')


def test_clean_corpus_accepted():
    clean_dir = '/home/user/data/clean'
    clean_files = glob.glob(os.path.join(clean_dir, '*.fasta'))
    assert len(clean_files) > 0, f'No clean files found in {clean_dir}.'
    modified = []
    for path in clean_files:
        try:
            out = filter_output(path)
            if out != 'ACCEPT':
                modified.append((os.path.basename(path), out))
        except Exception as exc:
            modified.append((os.path.basename(path), str(exc)))
    if modified:
        details = ', '.join(f"'{name}' (output: {out})" for name, out in modified)
        pytest.fail(f'{len(modified)} of {len(clean_files)} clean modified/rejected: {details}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
