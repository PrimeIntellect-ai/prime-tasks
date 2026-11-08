#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
from pathlib import Path

DATA_DIR = Path('/home/user/data')
RAW_PATH = DATA_DIR / 'raw_embeddings.jsonl'
MATRIX_PATH = DATA_DIR / 'projection_matrix.csv'
OUTPUT_PATH = Path('/home/user/experiment_log.tsv')


def find_go_candidates():
    roots = [Path('/home/user'), Path('/tmp')]
    if Path('/workspace').is_dir():
        roots.append(Path('/workspace'))

    ignored_parts = {'.cache', '.git', 'pkg', 'go-build'}
    candidates = []
    seen_dirs = set()

    for root in roots:
        for source in root.rglob('*.go'):
            if any(part in ignored_parts or part.startswith('go-build') for part in source.parts):
                continue
            try:
                text = source.read_text(errors='ignore')
            except OSError:
                continue
            if not re.search(r'^\s*package\s+main\b', text, re.MULTILINE):
                continue

            directory = source.parent.resolve()
            if directory in seen_dirs:
                continue
            seen_dirs.add(directory)

            files = sorted(
                p for p in directory.glob('*.go')
                if not p.name.endswith('_test.go')
            )
            if (directory / 'go.mod').is_file():
                command = ['go', 'run', '.']
            else:
                command = ['go', 'run'] + [str(p) for p in files]
            candidates.append((directory, command))

    return candidates


def expected_lines(records, matrix):
    lines = ['id\tv1\tv2\tvalid']
    for record in records:
        vector = record['vector']
        projected = [
            sum(vector[row] * matrix[row][column] for row in range(4))
            for column in range(2)
        ]
        valid = math.hypot(projected[0], projected[1]) <= 4.0
        lines.append(
            f"{record['id']}\t{projected[0]:.2f}\t{projected[1]:.2f}\t"
            f"{'true' if valid else 'false'}"
        )
    return lines


def install_fixture(records, matrix):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    RAW_PATH.write_text(''.join(json.dumps(record) + '\n' for record in records))
    with MATRIX_PATH.open('w', newline='') as handle:
        writer = csv.writer(handle, lineterminator='\n')
        writer.writerows(matrix)


def run_candidate(candidate):
    directory, command = candidate
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    return subprocess.run(
        command,
        cwd=str(directory),
        env={**os.environ, 'GO111MODULE': 'off'},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def output_matches(records, matrix):
    if not OUTPUT_PATH.is_file():
        return False
    actual = OUTPUT_PATH.read_text().strip().split('\n')
    return actual == expected_lines(records, matrix)


def test_go_pipeline_on_derived_inputs():
    original_raw = RAW_PATH.read_bytes()
    original_matrix = MATRIX_PATH.read_bytes()

    fixtures = [
        (
            [
                {'id': 'edge_exact', 'vector': [4.0, 0.0, 9.0, -2.0]},
                {'id': 'edge_over', 'vector': [4.01, 0.0, 0.0, 0.0]},
                {'id': 'negative', 'vector': [-1.25, 2.5, 3.0, 1.0]},
            ],
            [
                [1.0, 0.0],
                [0.0, 1.0],
                [0.0, 0.0],
                [0.0, 0.0],
            ],
        ),
        (
            [
                {'id': 'alpha', 'vector': [1.2, -2.0, 0.5, 3.0]},
                {'id': 'beta', 'vector': [-3.0, 1.0, 2.0, -0.5]},
            ],
            [
                [0.25, -0.75],
                [1.5, 0.2],
                [-0.4, 1.1],
                [0.3, -0.6],
            ],
        ),
    ]

    selected = None
    diagnostics = []
    try:
        candidates = find_go_candidates()
        assert candidates, 'No runnable Go source using package main was found.'

        for candidate in candidates:
            passed = True
            for records, matrix in fixtures:
                install_fixture(records, matrix)
                try:
                    result = run_candidate(candidate)
                except (subprocess.SubprocessError, OSError) as exc:
                    diagnostics.append(f'{candidate[0]}: {exc}')
                    passed = False
                    break
                if result.returncode != 0 or not output_matches(records, matrix):
                    diagnostics.append(
                        f"{candidate[0]}: exit={result.returncode}, stderr={result.stderr[-500:]}"
                    )
                    passed = False
                    break
            if passed:
                selected = candidate
                break
    finally:
        RAW_PATH.write_bytes(original_raw)
        MATRIX_PATH.write_bytes(original_matrix)

    assert selected is not None, (
        'No Go implementation correctly processed the derived input fixtures. '
        + ' | '.join(diagnostics)
    )

    result = run_candidate(selected)
    assert result.returncode == 0, (
        f'Go pipeline failed on the original inputs: {result.stderr}'
    )
    assert OUTPUT_PATH.is_file(), 'Go pipeline did not recreate the experiment log.'


def test_experiment_log_exists():
    filepath = "/home/user/experiment_log.tsv"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing. Did the script run and create it?"


def test_experiment_log_content():
    filepath = "/home/user/experiment_log.tsv"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing."

    expected_lines = [
        "id\tv1\tv2\tvalid",
        "doc1\t0.00\t1.00\ttrue",
        "doc2\t0.00\t0.00\ttrue",
        "doc3\t5.00\t-5.00\tfalse",
        "doc4\t0.00\t0.00\ttrue",
        "doc5\t0.00\t0.00\ttrue"
    ]

    with open(filepath, "r") as f:
        actual_lines = f.read().strip().split("\n")

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {filepath}, but found {len(actual_lines)}"
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} in {filepath} does not match expected output.\n"
            f"Expected: {repr(expected)}\n"
            f"Actual:   {repr(actual)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
