#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import pytest

SOURCE = Path('/home/user/processor.c')
EXECUTABLE = Path('/home/user/processor')
QUOTES = Path('/home/user/quotes.csv')
TRADES = Path('/home/user/trades.csv')
REPORT = Path('/home/user/vwas_report.csv')


def test_c_source_code_exists():
    source_file = '/home/user/processor.c'
    assert os.path.isfile(source_file), f'C source file {source_file} does not exist.'


def test_executable_exists_and_is_executable():
    executable_file = '/home/user/processor'
    assert os.path.isfile(executable_file), f'Executable {executable_file} does not exist.'

    st = os.stat(executable_file)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f'File {executable_file} is not executable.'
    with open(executable_file, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'File {executable_file} is not a compiled ELF executable.'


def test_vwas_report_correctness():
    report_file = '/home/user/vwas_report.csv'
    assert os.path.isfile(report_file), f'Output report {report_file} does not exist.'

    with open(report_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        'symbol,vwas',
        'AAPL,0.0800',
        'MSFT,0.1250',
        'TSLA,0.5000'
    ]

    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in {report_file}, but found {len(lines)}.'

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def parse_time(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


def derive_expected(quote_rows, trade_rows):
    quotes_by_symbol = {}
    for timestamp, symbol, bid, ask in quote_rows:
        quotes_by_symbol.setdefault(symbol, []).append(
            (parse_time(timestamp), Decimal(bid), Decimal(ask))
        )

    totals = {}
    for timestamp, symbol, _price, volume_text in trade_rows:
        trade_time = parse_time(timestamp)
        latest = None
        for quote in quotes_by_symbol.get(symbol, []):
            if quote[0] <= trade_time:
                latest = quote
            else:
                break
        if latest is None:
            continue
        volume = Decimal(volume_text)
        spread = latest[2] - latest[1]
        weighted, total_volume = totals.get(symbol, (Decimal('0'), Decimal('0')))
        totals[symbol] = (weighted + spread * volume, total_volume + volume)

    lines = ['symbol,vwas']
    for symbol in sorted(totals):
        weighted, total_volume = totals[symbol]
        lines.append(f'{symbol},{weighted / total_volume:.4f}')
    return lines


def write_inputs(quote_rows, trade_rows):
    with QUOTES.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['timestamp', 'symbol', 'bid', 'ask'])
        writer.writerows(quote_rows)
    with TRADES.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['timestamp', 'symbol', 'price', 'volume'])
        writer.writerows(trade_rows)


def run_and_check(binary, quote_rows, trade_rows):
    write_inputs(quote_rows, trade_rows)
    if REPORT.exists():
        REPORT.unlink()

    result = subprocess.run(
        [str(binary)], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'{binary} exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert REPORT.is_file(), f'{binary} did not create {REPORT}'
    with REPORT.open('r', newline='') as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = derive_expected(quote_rows, trade_rows)
    assert actual == expected, f'For changed inputs, expected {expected}, got {actual}'


def test_processor_executes_and_handles_changed_inputs(tmp_path):
    original_quotes = QUOTES.read_bytes()
    original_trades = TRADES.read_bytes()
    original_report = REPORT.read_bytes() if REPORT.exists() else None

    compiled = tmp_path / 'processor_from_source'
    build = subprocess.run(
        ['gcc', '-O2', '-std=c11', str(SOURCE), '-o', str(compiled), '-lm'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f'processor.c does not compile with gcc: {build.stderr}'

    scenarios = [
        (
            [
                ('2024-02-01T10:00:00Z', 'AAA', '10.00', '10.20'),
                ('2024-02-01T10:00:00Z', 'BBB', '20.00', '20.40'),
                ('2024-02-01T10:02:00Z', 'AAA', '10.10', '10.15'),
                ('2024-02-01T10:03:00Z', 'ZZZ', '5.00', '5.80'),
            ],
            [
                ('2024-02-01T09:59:00Z', 'AAA', '10.00', '9'),
                ('2024-02-01T10:01:00Z', 'AAA', '10.10', '3'),
                ('2024-02-01T10:01:30Z', 'BBB', '20.20', '2'),
                ('2024-02-01T10:02:00Z', 'AAA', '10.12', '1'),
                ('2024-02-01T10:03:00Z', 'ZZZ', '5.40', '5'),
                ('2024-02-01T10:04:00Z', 'CCC', '1.00', '7'),
            ],
        ),
        (
            [
                ('2025-06-10T08:00:00Z', 'ALPHA', '1.00', '1.01'),
                ('2025-06-10T08:00:00Z', 'OMEGA', '50.00', '50.25'),
                ('2025-06-10T08:01:00Z', 'ALPHA', '1.00', '1.03'),
                ('2025-06-10T08:01:30Z', 'MID', '7.00', '7.10'),
            ],
            [
                ('2025-06-10T07:59:00Z', 'OMEGA', '50.00', '8'),
                ('2025-06-10T08:00:00Z', 'OMEGA', '50.10', '4'),
                ('2025-06-10T08:00:30Z', 'ALPHA', '1.00', '10'),
                ('2025-06-10T08:01:00Z', 'ALPHA', '1.02', '30'),
                ('2025-06-10T08:01:30Z', 'MID', '7.05', '2'),
                ('2025-06-10T08:02:00Z', 'OMEGA', '50.20', '6'),
            ],
        ),
    ]

    try:
        for binary in (EXECUTABLE, compiled):
            for quote_rows, trade_rows in scenarios:
                run_and_check(binary, quote_rows, trade_rows)
    finally:
        QUOTES.write_bytes(original_quotes)
        TRADES.write_bytes(original_trades)
        if original_report is None:
            if REPORT.exists():
                REPORT.unlink()
        else:
            REPORT.write_bytes(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
