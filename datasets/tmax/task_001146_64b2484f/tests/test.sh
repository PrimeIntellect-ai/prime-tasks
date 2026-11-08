#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
SURVEY = HOME / 'survey.csv'
SUMMARY = HOME / 'summary.txt'
EXECUTABLE = Path('/tmp/submitted_analyzer')

ORIGINAL_SURVEY = '''id,group,text
1,A,hello world
2,A,this is a test
3,,missing group text
4,B,one two three
5,B,just one
6,A,outlier text that goes on and on and on and on and on and on and on and on and on and on and on
7,B,another valid text for b
8,A,valid a
9,B,singleword
10,C,wrong group
11,A,one more valid a text
'''

ORIGINAL_EXPECTED = (
    'Group A: Mean=3.25, CI=[1.78, 4.72]\n'
    'Group B: Mean=2.75, CI=[1.08, 4.42]'
)


def find_source():
    sources = []
    for extension in ('*.cpp', '*.cc', '*.cxx'):
        sources.extend(HOME.rglob(extension))
    sources = sorted(set(sources))
    assert sources, 'No C++ source file was found under /home/user'

    preferred_names = ('analyze.cpp', 'analyzer.cpp', 'main.cpp')
    for name in preferred_names:
        for source in sources:
            if source.name == name:
                return source

    main_pattern = re.compile(r'\bmain\s*\(')
    for source in sources:
        try:
            if main_pattern.search(source.read_text(encoding='utf-8', errors='ignore')):
                return source
        except OSError:
            pass
    return sources[0]


def compile_program(source):
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(source), '-o', str(EXECUTABLE)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f'Failed to compile {source}:\n{result.stdout}'
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)


def expected_from_csv(csv_text):
    values = {'A': [], 'B': []}
    for row in csv.DictReader(csv_text.splitlines()):
        group = row.get('group', '')
        if group not in values:
            continue
        text = row.get('text', '')
        token_count = len(text.split(' '))
        if token_count <= 20:
            values[group].append(token_count)

    lines = []
    for group in ('A', 'B'):
        nums = values[group]
        assert len(nums) >= 2
        mean = sum(nums) / len(nums)
        variance = sum((x - mean) ** 2 for x in nums) / (len(nums) - 1)
        standard_deviation = math.sqrt(variance)
        margin = 1.96 * standard_deviation / math.sqrt(len(nums))
        lines.append(
            f'Group {group}: Mean={mean:.2f}, CI=[{mean-margin:.2f}, {mean+margin:.2f}]'
        )
    return '\n'.join(lines)


def run_program(csv_text):
    SURVEY.write_text(csv_text, encoding='utf-8')
    if SUMMARY.exists():
        SUMMARY.unlink()

    result = subprocess.run(
        [str(EXECUTABLE)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert result.returncode == 0, f'Analyzer exited with status {result.returncode}:\n{result.stdout}'
    assert SUMMARY.is_file(), f'Output file {SUMMARY} is missing. Did the program create it?'
    actual = SUMMARY.read_text(encoding='utf-8').strip()
    assert re.fullmatch(
        r'Group A: Mean=-?\d+\.\d{2}, CI=\[-?\d+\.\d{2}, -?\d+\.\d{2}\]\n'
        r'Group B: Mean=-?\d+\.\d{2}, CI=\[-?\d+\.\d{2}, -?\d+\.\d{2}\]',
        actual,
    ), f'Output does not strictly match the requested format:\n{actual}'
    return actual


def make_case(rng):
    rows = [['id', 'group', 'text']]
    row_id = 1
    counts = {
        'A': [rng.randint(1, 15) for _ in range(4)],
        'B': [rng.randint(1, 15) for _ in range(5)],
    }
    for group in ('A', 'B'):
        for count in counts[group]:
            rows.append([str(row_id), group, ' '.join(f'w{i}' for i in range(count))])
            row_id += 1

    rows.extend([
        [str(row_id), '', 'ignored empty group'],
        [str(row_id + 1), 'C', 'ignored invalid group'],
        [str(row_id + 2), 'A', ' '.join(f'out{i}' for i in range(21))],
        [str(row_id + 3), 'B', ' '.join(f'out{i}' for i in range(24))],
    ])

    from io import StringIO
    buffer = StringIO()
    writer = csv.writer(buffer, lineterminator='\n')
    writer.writerows(rows)
    return buffer.getvalue()


def test_compiled_program_processes_survey():
    source = find_source()
    compile_program(source)

    prior_survey = SURVEY.read_bytes() if SURVEY.exists() else None
    try:
        # Preserve the verifier's original exact-content assertion, but require
        # that the compiled submission freshly generate the file.
        actual = run_program(ORIGINAL_SURVEY)
        assert actual == ORIGINAL_EXPECTED, (
            f'Content of {SUMMARY} does not match expected output.\n'
            f'Expected:\n{ORIGINAL_EXPECTED}\n\nActual:\n{actual}'
        )

        rng = random.SystemRandom()
        hidden_cases = []
        while len(hidden_cases) < 2:
            case = make_case(rng)
            expected = expected_from_csv(case)
            if expected != ORIGINAL_EXPECTED and all(expected != expected_from_csv(c) for c in hidden_cases):
                hidden_cases.append(case)

        for case in hidden_cases:
            expected = expected_from_csv(case)
            actual = run_program(case)
            assert actual == expected, (
                'The compiled program produced incorrect results for a changed survey.\n'
                f'Expected:\n{expected}\n\nActual:\n{actual}'
            )

        # Leave the required output corresponding to the original dataset.
        actual = run_program(ORIGINAL_SURVEY)
        assert actual == ORIGINAL_EXPECTED
    finally:
        if prior_survey is None:
            if SURVEY.exists():
                SURVEY.unlink()
        else:
            SURVEY.write_bytes(prior_survey)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
