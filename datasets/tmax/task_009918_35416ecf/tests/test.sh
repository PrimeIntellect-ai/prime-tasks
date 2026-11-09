#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

HOME = Path('/home/user')
SOURCE = HOME / 'analyze_logs.cpp'
PROGRAM = HOME / 'analyze_logs'
INPUT = HOME / 'etl_logs.tsv'
OUTPUT = HOME / 'summary.csv'
VERIFIED_PROGRAM = Path('/tmp/analyze_logs_verified')

ORIGINAL_INPUT = '''2023-10-01T10:00:00Z\tTX1001\ten\tHello World\t150\t512\t1024
2023-10-01T10:01:00Z\tTX1002\tfr\tBonjour le monde\t200\t1024\t2048
2023-10-01T10:02:00Z\tTX1001\ten\tHello World\t999\t999\t999
2023-10-01T10:03:00Z\tTX1003\ten\tHow are you?\t100\t256\t512
2023-10-01T10:04:00Z\tTX1004\tzh\t你好，世界\t300\t2048\t4096
2023-10-01T10:05:00Z\tTX1002\tfr\tBonjour le monde\t888\t888\t888
2023-10-01T10:06:00Z\tTX1005\tes\tHola Mundo\t120\t512\t1024
2023-10-01T10:07:00Z\tTX1006\tzh\t欢迎\t200\t1024\t2048
2023-10-01T10:08:00Z\tTX1005\tes\tHola Mundo\t777\t777\t777
'''

ORIGINAL_EXPECTED = [
    ['lang', 'resource', 'avg_value'],
    ['en', 'cpu_ms', '125.00'],
    ['en', 'mem_mb', '384.00'],
    ['en', 'net_kb', '768.00'],
    ['es', 'cpu_ms', '120.00'],
    ['es', 'mem_mb', '512.00'],
    ['es', 'net_kb', '1024.00'],
    ['fr', 'cpu_ms', '200.00'],
    ['fr', 'mem_mb', '1024.00'],
    ['fr', 'net_kb', '2048.00'],
    ['zh', 'cpu_ms', '250.00'],
    ['zh', 'mem_mb', '1536.00'],
    ['zh', 'net_kb', '3072.00'],
]


def read_summary():
    assert OUTPUT.exists(), f'Output file {OUTPUT} does not exist.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'
    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        actual = list(csv.reader(f))
    assert len(actual) > 0, f'The file {OUTPUT} is empty.'
    return actual


def assert_original_result():
    actual_data = read_summary()
    assert actual_data[0] == ORIGINAL_EXPECTED[0], (
        f'Header row in {OUTPUT} is incorrect. Expected {ORIGINAL_EXPECTED[0]}, got {actual_data[0]}'
    )
    assert len(actual_data) == len(ORIGINAL_EXPECTED), (
        f'Expected {len(ORIGINAL_EXPECTED)} rows (including header), got {len(actual_data)}.'
    )
    for i in range(1, len(ORIGINAL_EXPECTED)):
        assert actual_data[i] == ORIGINAL_EXPECTED[i], (
            f'Row {i} in {OUTPUT} is incorrect. Expected {ORIGINAL_EXPECTED[i]}, got {actual_data[i]}'
        )


def expected_for(lines):
    seen = set()
    groups = {}
    for line in lines:
        fields = line.split('\t')
        assert len(fields) == 7
        txid, lang = fields[1], fields[2]
        if txid in seen:
            continue
        seen.add(txid)
        values = [int(fields[4]), int(fields[5]), int(fields[6])]
        if lang not in groups:
            groups[lang] = [[0, 0], [0, 0], [0, 0]]
        for i, value in enumerate(values):
            groups[lang][i][0] += value
            groups[lang][i][1] += 1

    rows = [['lang', 'resource', 'avg_value']]
    resources = ['cpu_ms', 'mem_mb', 'net_kb']
    for lang in sorted(groups):
        for i, resource in enumerate(resources):
            total, count = groups[lang][i]
            average = (Decimal(total) / Decimal(count)).quantize(
                Decimal('0.01'), rounding=ROUND_HALF_UP
            )
            rows.append([lang, resource, format(average, '.2f')])
    return rows


def run_case(executable, lines):
    INPUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run(
        [str(executable)], cwd=str(HOME), check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    actual = read_summary()
    expected = expected_for(lines)
    assert actual == expected, f'Incorrect result for altered input. Expected {expected}, got {actual}'


def make_random_case():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    langs = ['de', 'en', 'es', 'fr', 'pt', 'zh']
    originals = []
    duplicates = []
    sequence = 0

    # Three first-occurrence records per language make non-integral averages
    # unambiguous while exercising grouping and all resource columns.
    for lang_index, lang in enumerate(langs):
        for item in range(3):
            sequence += 1
            txid = f'{token}-{lang_index}-{item}'
            cpu = rng.randrange(20, 900)
            mem = rng.randrange(100, 5000)
            net = rng.randrange(50, 9000)
            originals.append(
                f'2026-01-01T00:{sequence:02d}:00Z\t{txid}\t{lang}\t消息 café {sequence}\t{cpu}\t{mem}\t{net}'
            )
            # A retry deliberately changes language and values; it must be ignored.
            retry_lang = langs[(lang_index + 1) % len(langs)]
            duplicates.append(
                f'2026-01-02T00:{sequence:02d}:00Z\t{txid}\t{retry_lang}\tretry {sequence}\t{cpu + 10000}\t{mem + 10000}\t{net + 10000}'
            )

    rng.shuffle(originals)
    rng.shuffle(duplicates)
    lines = []
    # Interleave some retries after their first occurrences, then append the rest.
    pending = {line.split('\t')[1]: line for line in duplicates}
    for index, line in enumerate(originals):
        lines.append(line)
        if index % 2 == 0:
            txid = line.split('\t')[1]
            lines.append(pending.pop(txid))
    remaining = list(pending.values())
    rng.shuffle(remaining)
    lines.extend(remaining)
    return lines


def main():
    assert SOURCE.exists() and SOURCE.is_file(), f'Missing C++ source file: {SOURCE}'
    assert SOURCE.stat().st_size > 0, f'C++ source file is empty: {SOURCE}'
    assert PROGRAM.exists() and PROGRAM.is_file(), f'Missing compiled program: {PROGRAM}'
    mode = PROGRAM.stat().st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f'Program is not executable: {PROGRAM}'
    with PROGRAM.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'Compiled program is not an ELF executable: {PROGRAM}'

    # Independently compile the submitted source so behavioral checks also cover
    # the implementation in analyze_logs.cpp rather than only an unrelated binary.
    subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(VERIFIED_PROGRAM)],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )

    # Execute the artifact demanded by the instruction on the original input and
    # retain all exact assertions from the original verifier.
    INPUT.write_text(ORIGINAL_INPUT, encoding='utf-8')
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run(
        [str(PROGRAM)], cwd=str(HOME), check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert_original_result()

    # Exercise both the submitted executable and an independent build of its source
    # on unpredictable altered inputs, deriving expected answers from those inputs.
    run_case(PROGRAM, make_random_case())
    run_case(VERIFIED_PROGRAM, make_random_case())

    # Leave the required output corresponding to the task's original input.
    INPUT.write_text(ORIGINAL_INPUT, encoding='utf-8')
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run(
        [str(PROGRAM)], cwd=str(HOME), check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert_original_result()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
