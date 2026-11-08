#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
from pathlib import Path

import cv2
import numpy as np
import pytest

RESULTS = Path('/home/user/results.csv')
VIDEO = Path('/app/spectroscopy_feed.mp4')
SIGNAL = Path('/tmp/verifier_signal.txt')


def extract_signal_and_counts():
    cap = cv2.VideoCapture(str(VIDEO))
    assert cap.isOpened(), f'Could not open {VIDEO}'
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(gray[24:40, 24:40])))
    cap.release()

    assert len(values) == 500, f'Expected 500 frames, found {len(values)}'
    SIGNAL.write_text(''.join(f'{v:.10f}\n' for v in values))

    states = [1 if value > 125.0 else 0 for value in values]
    n00 = n01 = n10 = n11 = 0
    for a, b in zip(states, states[1:]):
        if (a, b) == (0, 0): n00 += 1
        elif (a, b) == (0, 1): n01 += 1
        elif (a, b) == (1, 0): n10 += 1
        else: n11 += 1
    assert n00 + n01 > 0 and n10 + n11 > 0
    return values, (n00, n01, n10, n11)


def parse_results():
    assert RESULTS.exists(), f'File {RESULTS} does not exist.'
    assert RESULTS.is_file(), f'{RESULTS} is not a file.'
    try:
        with RESULTS.open(newline='') as f:
            rows = list(csv.reader(f))
        assert len(rows) == 3, 'results.csv must contain exactly three lines'
        assert [row[0].strip() if row else '' for row in rows] == ['P01', 'P10', 'LLR'], \
            'results.csv keys must be exactly P01, P10, LLR in that order'
        assert all(len(row) == 2 for row in rows), 'Each results.csv line must have exactly two fields'
        data = {row[0].strip(): float(row[1].strip()) for row in rows}
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f'Failed to read or parse {RESULTS}: {e}')

    assert 'P01' in data, 'P01 not found in results.csv'
    assert 'P10' in data, 'P10 not found in results.csv'
    assert 'LLR' in data, 'LLR not found in results.csv'
    assert all(math.isfinite(v) for v in data.values()), 'All reported values must be finite'
    return data


def validate_metrics(data, counts):
    p01, p10, llr = data['P01'], data['P10'], data['LLR']

    # Preserve the original generating-parameter assertion.
    error = abs(p01 - 0.15) + abs(p10 - 0.25)
    assert error < 0.06, \
        f'Metric error {error:.4f} is not < 0.06 (P01={p01}, P10={p10})'

    assert 0.0 < p01 < 1.0 and 0.0 < p10 < 1.0
    n00, n01, n10, n11 = counts
    empirical01 = n01 / (n00 + n01)
    empirical10 = n10 / (n10 + n11)
    empirical_error = abs(p01 - empirical01) + abs(p10 - empirical10)
    assert empirical_error < 0.06, \
        f'Parameters do not fit the transitions extracted from the video: error={empirical_error:.4f}'

    # With the well-separated emissions, the decoded-state transition likelihood
    # is the observed-data likelihood to numerical precision; emission terms cancel.
    expected_llr = (
        n01 * math.log(p01 / 0.5) + n00 * math.log((1.0 - p01) / 0.5) +
        n10 * math.log(p10 / 0.5) + n11 * math.log((1.0 - p10) / 0.5)
    )
    assert abs(llr - expected_llr) < 5.0, \
        f'LLR {llr} is inconsistent with the video and reported parameters (expected about {expected_llr:.4f})'
    assert llr > 0.0, 'The fitted model should outperform the null model'


def candidate_sources():
    found = []
    for root in (Path('/home/user'), Path('/app')):
        if root.exists():
            found.extend(p for p in root.rglob('*.cpp') if p.is_file())
            found.extend(p for p in root.rglob('*.cc') if p.is_file())
            found.extend(p for p in root.rglob('*.cxx') if p.is_file())
    return sorted(set(found))


def test_cpp_program_recomputes_video_derived_results():
    _, counts = extract_signal_and_counts()
    sources = candidate_sources()
    assert sources, 'No C++ source program was found under /home/user or /app'

    failures = []
    for index, source in enumerate(sources):
        try:
            text = source.read_text(errors='ignore')
        except Exception as e:
            failures.append(f'{source}: unreadable: {e}')
            continue

        # Require evidence of a data-reading Monte Carlo implementation, rather
        # than accepting a source file that only prints constants.
        has_input = re.search(r'ifstream|std::cin|\bcin\s*>>|fscanf\s*\(|getline\s*\(', text)
        has_rng = re.search(
            r'mt19937|default_random_engine|random_device|uniform_(?:real|int)_distribution|'
            r'normal_distribution|\brand\s*\(', text)
        has_iteration = re.search(r'\bfor\s*\(|\bwhile\s*\(', text)
        if not (has_input and has_rng and has_iteration):
            failures.append(f'{source}: lacks input-reading and Monte Carlo iteration logic')
            continue

        executable = Path(f'/tmp/verifier_candidate_{index}')
        compiled = subprocess.run(
            ['g++', '-O3', '-std=c++17', str(source), '-o', str(executable)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if compiled.returncode != 0:
            failures.append(f'{source}: compilation failed: {compiled.stderr[-500:]}')
            continue

        commands = [
            [str(executable)],
            [str(executable), str(SIGNAL)],
            [str(executable), str(SIGNAL), str(RESULTS)],
        ]
        for command in commands:
            try:
                if RESULTS.exists():
                    RESULTS.unlink()
                run = subprocess.run(
                    command,
                    cwd='/home/user',
                    input=SIGNAL.read_text(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=45)
                if run.returncode != 0:
                    continue
                data = parse_results()
                validate_metrics(data, counts)
                return
            except (AssertionError, subprocess.TimeoutExpired, OSError, ValueError) as e:
                failures.append(f'{source} with {command[1:]}: {e}')

    pytest.fail('No submitted C++ Monte Carlo program compiled, ran, and regenerated valid results. '
                + ' | '.join(failures[-8:]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
