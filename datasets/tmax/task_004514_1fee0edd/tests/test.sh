#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import statistics
import subprocess
import tempfile
from pathlib import Path

EXECUTABLE = Path('/home/user/bin/seq_density')
SOURCE_PATH = Path('/home/user/src/seq_density.c')
REPORT_PATH = Path('/home/user/analysis_report.txt')
FASTA_PATH = Path('/home/user/data/input.fasta')
REFERENCE_PATH = Path('/home/user/data/reference.tsv')

EXPECTED_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int w = atoi(argv[1]);
    if (w <= 0) return 1;

    char *buf = NULL;
    size_t size = 0;
    ssize_t len = getline(&buf, &size, stdin);
    if (len <= 0) {
        free(buf);
        return 0;
    }
    if (buf[len-1] == '\n') buf[--len] = 0;

    for (int i = 0; i <= len - w; i++) {
        int gc = 0;
        for (int j = 0; j < w; j++) {
            if (buf[i+j] == 'G' || buf[i+j] == 'C') gc++;
        }
        double p = (double)gc / w;
        double ent = 0;
        if (p > 0) ent -= p * log2(p);
        if (1-p > 0) ent -= (1-p) * log2(1-p);
        printf("%f\n", ent);
    }
    free(buf);
    return 0;
}
'''


def run_tool(path, sequence, window):
    result = subprocess.run(
        [str(path), str(window)],
        input=(sequence + '\n').encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f'{path} failed for window {window}: return code {result.returncode}, '
        f'stderr={result.stderr.decode(errors="replace")!r}'
    )
    return result.stdout.decode().splitlines()


def expected_density_lines(sequence, window):
    values = []
    for start in range(len(sequence) - window + 1):
        chunk = sequence[start:start + window]
        p = sum(base in 'GC' for base in chunk) / window
        entropy = 0.0
        if p > 0:
            entropy -= p * math.log2(p)
        if 1 - p > 0:
            entropy -= (1 - p) * math.log2(1 - p)
        values.append(f'{entropy:.6f}')
    return values


def parse_fasta(path):
    records = []
    seq_id = None
    chunks = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if line.startswith('>'):
            if seq_id is not None:
                records.append((seq_id, ''.join(chunks)))
            seq_id = line[1:].split()[0]
            chunks = []
        elif line:
            chunks.append(line)
    if seq_id is not None:
        records.append((seq_id, ''.join(chunks)))
    return records


def independently_derive_report():
    records = parse_fasta(FASTA_PATH)
    assert records, 'Input FASTA contains no sequences'

    first_sequence = records[0][1]
    optimal_w = None
    for window in (5, 10, 20, 50):
        values = [float(x) for x in expected_density_lines(first_sequence, window)]
        variance = statistics.pvariance(values)
        if variance < 0.05:
            optimal_w = window
            break
    assert optimal_w is not None, 'No qualifying window size was found'

    references = {}
    for line in REFERENCE_PATH.read_text().splitlines():
        if line.strip():
            seq_id, expected = line.split('\t')
            references[seq_id] = float(expected)

    differences = []
    for seq_id, sequence in records:
        values = [float(x) for x in expected_density_lines(sequence, optimal_w)]
        assert values, f'No density values for {seq_id}'
        mean = sum(values) / len(values)
        differences.append((abs(mean - references[seq_id]), seq_id))

    most_divergent = max(differences, key=lambda item: item[0])[1]
    return optimal_w, most_divergent


def test_executable_exists():
    executable = '/home/user/bin/seq_density'
    assert os.path.isfile(executable), f'Executable missing: {executable}'
    assert os.access(executable, os.X_OK), f'File is not executable: {executable}'


def test_executable_is_compiled_from_supplied_source_and_works():
    assert SOURCE_PATH.read_text() == EXPECTED_SOURCE, 'The supplied C source was modified'
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'seq_density must be a compiled ELF executable'

    with tempfile.TemporaryDirectory() as tmpdir:
        reference_executable = Path(tmpdir) / 'seq_density_reference'
        compile_result = subprocess.run(
            ['gcc', str(SOURCE_PATH), '-o', str(reference_executable), '-lm'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compile_result.returncode == 0, compile_result.stderr.decode(errors='replace')

        rng = random.SystemRandom()
        cases = [
            ('ATGCATGCATGC', 5),
            ('G' * 31 + 'A' * 29, 20),
            (''.join(rng.choice('ACGT') for _ in range(97)), 7),
            (''.join(rng.choice('ACGT') for _ in range(143)), 50),
        ]
        for sequence, window in cases:
            actual = run_tool(EXECUTABLE, sequence, window)
            reference = run_tool(reference_executable, sequence, window)
            expected = expected_density_lines(sequence, window)
            assert actual == reference, f'Output differs from compiled supplied source for window {window}'
            assert actual == expected, f'Incorrect density output for window {window}'

    no_arg = subprocess.run(
        [str(EXECUTABLE)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, check=False
    )
    assert no_arg.returncode != 0, 'The tool must reject a missing window argument'


def test_report_exists_and_content():
    report_file = '/home/user/analysis_report.txt'
    assert os.path.isfile(report_file), f'Report file missing: {report_file}'

    with open(report_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f'Report file should have exactly 2 non-empty lines, found {len(lines)}'

    assert lines[0] == 'Optimal_W: 20', f"First line incorrect. Expected 'Optimal_W: 20', got '{lines[0]}'"
    assert lines[1] == 'Most_Divergent_Seq: Seq2', f"Second line incorrect. Expected 'Most_Divergent_Seq: Seq2', got '{lines[1]}'"

    optimal_w, most_divergent = independently_derive_report()
    expected_lines = [
        f'Optimal_W: {optimal_w}',
        f'Most_Divergent_Seq: {most_divergent}',
    ]
    assert REPORT_PATH.read_text().splitlines() == expected_lines, (
        f'Report must contain exactly the independently derived lines: {expected_lines!r}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
