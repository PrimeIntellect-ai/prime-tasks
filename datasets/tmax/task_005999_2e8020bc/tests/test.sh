#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

LIB_PATH = Path('/home/user/libseq.so')
SCRIPT_PATH = Path('/home/user/run_pipeline.py')
REPORT_PATH = Path('/home/user/report.json')
SEQ_PATH = Path('/home/user/data/sequences.txt')


def solve_linear_system(A, b):
    n = len(A)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]

    for i in range(n):
        max_el = abs(M[i][i])
        max_row = i
        for k in range(i + 1, n):
            if abs(M[k][i]) > max_el:
                max_el = abs(M[k][i])
                max_row = k
        M[i], M[max_row] = M[max_row], M[i]

        for k in range(i + 1, n):
            if M[i][i] == 0:
                continue
            c = -M[k][i] / M[i][i]
            for j in range(i, n + 1):
                if i == j:
                    M[k][j] = 0
                else:
                    M[k][j] += c * M[i][j]

    x = [0.0 for _ in range(n)]
    for i in range(n - 1, -1, -1):
        x[i] = M[i][n] / M[i][i]
        for k in range(i - 1, -1, -1):
            M[k][n] -= M[k][i] * x[i]

    return x


def expected_values(sequences):
    n = len(sequences)
    length = len(sequences[0])
    adjacency = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            dist = sum(a != b for a, b in zip(sequences[i], sequences[j]))
            adjacency[i][j] = length - dist

    matrix = [[0.05 * adjacency[i][j] for j in range(n)] for i in range(n)]
    for i in range(n):
        matrix[i][i] += 1.0
    scores = [round(value, 4) for value in solve_linear_system(matrix, [1.0] * n)]
    return adjacency, scores


def assert_report(report_path, sequences):
    assert report_path.is_file(), f'Report file {report_path} was not created.'
    try:
        with report_path.open('r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {report_path} is not valid JSON.')

    assert 'adjacency_matrix' in report, "Key 'adjacency_matrix' missing from report.json"
    assert 'consensus_scores' in report, "Key 'consensus_scores' missing from report.json"

    expected_A, expected_x = expected_values(sequences)
    assert report['adjacency_matrix'] == expected_A, 'Adjacency matrix in report.json is incorrect.'

    reported_x = report['consensus_scores']
    assert len(reported_x) == len(sequences), 'Length of consensus_scores does not match number of sequences.'
    for i, expected_val in enumerate(expected_x):
        assert abs(reported_x[i] - expected_val) <= 1e-4, (
            f'Consensus score at index {i} is incorrect. '
            f'Expected {expected_val}, got {reported_x[i]}.'
        )


def test_libseq_so_exists_and_works():
    assert LIB_PATH.is_file(), f'Shared library {LIB_PATH} was not created.'
    with LIB_PATH.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{LIB_PATH} is not an ELF shared library.'

    try:
        library = ctypes.CDLL(str(LIB_PATH))
        distance = library.sequence_distance
    except (OSError, AttributeError) as exc:
        pytest.fail(f'Could not load sequence_distance from {LIB_PATH}: {exc}')

    distance.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    distance.restype = ctypes.c_int
    for left, right in [
        (b'ACGTACGT', b'ACGTACGT'),
        (b'AAAAAAAA', b'TTTTTTTT'),
        (b'GATTACA', b'GACTATA'),
        (b'CCGTAAGTC', b'CTGTCAGTA'),
    ]:
        expected = sum(a != b for a, b in zip(left, right))
        assert distance(left, right, len(left)) == expected, (
            'sequence_distance returned an incorrect Hamming distance.'
        )


def test_run_pipeline_exists():
    assert SCRIPT_PATH.is_file(), f'Python script {SCRIPT_PATH} was not created.'


def test_report_json():
    with SEQ_PATH.open('r') as f:
        sequences = f.read().splitlines()
    assert_report(REPORT_PATH, sequences)


def test_pipeline_executes_and_uses_ctypes_library(tmp_path):
    # Use unpredictable data so a precomputed report cannot satisfy this test.
    alphabet = 'ACGT'
    sequences = []
    while len(sequences) < 6:
        sequence = ''.join(secrets.choice(alphabet) for _ in range(9))
        if sequence not in sequences:
            sequences.append(sequence)

    spy_source = tmp_path / 'seq_spy.c'
    spy_library = tmp_path / 'libseq_spy.so'
    call_log = tmp_path / 'sequence_calls.tsv'
    ctypes_log = tmp_path / 'ctypes_loads.txt'
    site_dir = tmp_path / 'site'
    site_dir.mkdir()

    spy_source.write_text(r'''#include <stdio.h>
#include <stdlib.h>

int sequence_distance(const char* s1, const char* s2, int len) {
    int dist = 0;
    for (int i = 0; i < len; i++) {
        if (s1[i] != s2[i]) dist++;
    }
    const char* path = getenv("SEQ_SPY_LOG");
    if (path) {
        FILE* f = fopen(path, "a");
        if (f) {
            fprintf(f, "%.*s\t%.*s\t%d\n", len, s1, len, s2, len);
            fclose(f);
        }
    }
    return dist;
}
''')
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(spy_library), str(spy_source)],
        check=True,
        capture_output=True,
        text=True,
    )

    # sitecustomize records loading performed through ctypes.CDLL or
    # ctypes.cdll.LoadLibrary while leaving their normal behavior intact.
    (site_dir / 'sitecustomize.py').write_text(r'''import ctypes
import os

_log_path = os.environ.get("CTYPES_LOAD_LOG")
_orig_cdll = ctypes.CDLL
_orig_load_library = ctypes.LibraryLoader.LoadLibrary

def _record(name):
    if _log_path:
        with open(_log_path, "a") as f:
            f.write(str(name) + "\n")

def tracked_cdll(name, *args, **kwargs):
    _record(name)
    return _orig_cdll(name, *args, **kwargs)

def tracked_load_library(self, name):
    _record(name)
    return _orig_load_library(self, name)

ctypes.CDLL = tracked_cdll
ctypes.LibraryLoader.LoadLibrary = tracked_load_library
''')

    original_lib = LIB_PATH.read_bytes()
    original_lib_mode = stat.S_IMODE(LIB_PATH.stat().st_mode)
    original_sequences = SEQ_PATH.read_bytes()
    original_report = REPORT_PATH.read_bytes() if REPORT_PATH.exists() else None

    try:
        shutil.copyfile(spy_library, LIB_PATH)
        os.chmod(LIB_PATH, 0o755)
        SEQ_PATH.write_text('\n'.join(sequences) + '\n')
        if REPORT_PATH.exists():
            REPORT_PATH.unlink()

        env = os.environ.copy()
        env['SEQ_SPY_LOG'] = str(call_log)
        env['CTYPES_LOAD_LOG'] = str(ctypes_log)
        env['PYTHONPATH'] = str(site_dir) + os.pathsep + env.get('PYTHONPATH', '')
        result = subprocess.run(
            ['python3', str(SCRIPT_PATH)],
            cwd='/home/user',
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f'run_pipeline.py failed when executed.\nstdout:\n{result.stdout}\n'
            f'stderr:\n{result.stderr}'
        )

        assert ctypes_log.is_file(), 'run_pipeline.py did not load the library using ctypes.'
        loads = ctypes_log.read_text().splitlines()
        assert any(os.path.abspath(item) == str(LIB_PATH) for item in loads), (
            'run_pipeline.py did not load /home/user/libseq.so through ctypes.'
        )

        assert call_log.is_file(), 'run_pipeline.py never called sequence_distance.'
        calls = []
        for line in call_log.read_text().splitlines():
            parts = line.split('\t')
            assert len(parts) == 3, 'Malformed sequence_distance call log.'
            calls.append((parts[0], parts[1], int(parts[2])))

        # Symmetry-aware implementations may compute each unordered pair once.
        for i in range(len(sequences)):
            for j in range(i + 1, len(sequences)):
                assert any(
                    length == len(sequences[i]) and
                    ((left == sequences[i] and right == sequences[j]) or
                     (left == sequences[j] and right == sequences[i]))
                    for left, right, length in calls
                ), f'sequence_distance was not used for sequence pair ({i}, {j}).'

        assert_report(REPORT_PATH, sequences)
    finally:
        LIB_PATH.write_bytes(original_lib)
        os.chmod(LIB_PATH, original_lib_mode)
        SEQ_PATH.write_bytes(original_sequences)
        if original_report is None:
            if REPORT_PATH.exists():
                REPORT_PATH.unlink()
        else:
            REPORT_PATH.write_bytes(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
