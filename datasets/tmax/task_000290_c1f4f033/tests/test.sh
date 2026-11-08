#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import csv
import pytest
import tempfile
import secrets
from collections import defaultdict

EXECUTABLE = "/home/user/etl_processor"
SOURCE = "/home/user/etl_processor.cpp"
HEADER = "/app/vendor/csv_lib/csv.h"
LOG_FILE = "/home/user/pipeline.log"
EVIL_CORPUS = "/app/corpus/evil/"
CLEAN_CORPUS = "/app/corpus/clean/"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    assert os.path.isfile(SOURCE), f"Source not found at {SOURCE}"


def test_vendored_header_is_fixed_and_self_contained(tmp_path):
    probe = tmp_path / "header_probe.cpp"
    output = tmp_path / "header_probe"
    probe.write_text(
        '#include "/app/vendor/csv_lib/csv.h"\n'
        'int main() { std::string s = "x"; std::vector<std::string> v{s}; csv::Parser p; return v.size() != 1; }\n',
        encoding="utf-8",
    )
    result = subprocess.run(
        ["g++", "-std=c++17", str(probe), "-o", str(output)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Vendored header is not fixed/self-contained: {result.stderr}"


def compute_expected_output(filepath):
    expected = []
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader)

        symbols = []
        for i in range(1, len(headers), 2):
            sym = headers[i].replace('_price', '')
            symbols.append(sym)

        history = defaultdict(list)

        for row in reader:
            if not row:
                continue
            ts = row[0]
            for i, sym in enumerate(symbols):
                price_str = row[1 + i*2]
                vol_str = row[2 + i*2]
                if not price_str:
                    continue
                price = float(price_str)
                vol = vol_str

                history[sym].append(price)
                if len(history[sym]) > 3:
                    history[sym].pop(0)

                avg = sum(history[sym]) / len(history[sym])
                expected.append((ts, sym, price, vol, avg))

    return expected


def assert_clean_result(filepath):
    result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
    assert result.returncode == 0, f"Exit code {result.returncode} for {filepath}: {result.stderr}"

    stdout_lines = result.stdout.strip().split('\n')
    assert stdout_lines and stdout_lines[0].strip() == "timestamp,symbol,price,vol,rolling_avg_price"

    expected_rows = compute_expected_output(filepath)
    actual_rows = stdout_lines[1:]
    assert len(expected_rows) == len(actual_rows), \
        f"Expected {len(expected_rows)} rows, got {len(actual_rows)} for {filepath}"

    for expected, actual_line in zip(expected_rows, actual_rows):
        parts = actual_line.split(',')
        assert len(parts) == 5, f"Malformed output row: {actual_line!r}"
        ts, sym, price, vol, avg = expected
        a_ts, a_sym, a_price, a_vol, a_avg = parts
        assert a_ts == ts and a_sym == sym and a_vol == vol, \
            f"Output data mismatch: expected {expected}, got {parts}"
        try:
            actual_price = float(a_price)
            actual_avg = float(a_avg)
        except ValueError:
            pytest.fail(f"Non-numeric price or average in row: {actual_line!r}")
        assert abs(actual_price - price) <= 1e-4
        assert abs(actual_avg - avg) <= 1e-4


def test_evil_corpus_rejected():
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil files found to test."

    bypassed = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)

        if result.returncode != 1:
            bypassed.append((os.path.basename(filepath), "Exit code not 1"))
            continue

        if "REJECTED" not in result.stderr:
            bypassed.append((os.path.basename(filepath), "REJECTED not in stderr"))
            continue

        if not os.path.isfile(LOG_FILE):
            bypassed.append((os.path.basename(filepath), f"Log file {LOG_FILE} missing"))
            continue

        with open(LOG_FILE, 'r') as f:
            log_content = f.read()

        expected_log = f"ERROR: Invalid encoding in file {filepath}"
        if expected_log not in log_content:
            bypassed.append((os.path.basename(filepath), "Missing expected log entry"))
            continue

    if bypassed:
        details = ", ".join(f"{f} ({r})" for f, r in bypassed)
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {details}")


def test_clean_corpus_accepted():
    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No clean files found to test."

    modified = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)

        if result.returncode != 0:
            modified.append((os.path.basename(filepath), f"Exit code {result.returncode} instead of 0"))
            continue

        stdout_lines = result.stdout.strip().split('\n')
        if not stdout_lines:
            modified.append((os.path.basename(filepath), "Empty output"))
            continue

        if stdout_lines[0].strip() != "timestamp,symbol,price,vol,rolling_avg_price":
            modified.append((os.path.basename(filepath), "Incorrect header"))
            continue

        expected_rows = compute_expected_output(filepath)
        actual_rows = stdout_lines[1:]

        if len(expected_rows) != len(actual_rows):
            modified.append((os.path.basename(filepath), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}"))
            continue

        mismatch = False
        for expected, actual_line in zip(expected_rows, actual_rows):
            parts = actual_line.split(',')
            if len(parts) != 5:
                mismatch = True
                break

            ts, sym, price, vol, avg = expected
            a_ts, a_sym, a_price, a_vol, a_avg = parts

            if a_ts != ts or a_sym != sym or a_vol != vol:
                mismatch = True
                break

            try:
                if abs(float(a_price) - price) > 1e-4 or abs(float(a_avg) - avg) > 1e-4:
                    mismatch = True
                    break
            except ValueError:
                mismatch = True
                break

        if mismatch:
            modified.append((os.path.basename(filepath), "Output data mismatch"))

    if modified:
        details = ", ".join(f"{f} ({r})" for f, r in modified)
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/failed: {details}")


def make_random_csv(path, row_count, symbol_count, include_unicode=False):
    rng = secrets.SystemRandom()
    symbols = []
    for i in range(symbol_count):
        token = secrets.token_hex(3).upper()
        symbols.append(("MÜ" if include_unicode and i == 0 else "S") + token)

    headers = ["timestamp"]
    for sym in symbols:
        headers.extend([f"{sym}_price", f"{sym}_vol"])

    start = rng.randrange(1_000_000, 9_000_000)
    bases = [rng.randrange(100, 5000) for _ in symbols]
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(headers)
        for row_index in range(row_count):
            row = [str(start + row_index)]
            for sym_index in range(symbol_count):
                whole_tenths = bases[sym_index] + row_index * (sym_index + 1) + rng.randrange(-4, 5)
                row.extend([f"{whole_tenths / 10:.1f}", str(rng.randrange(1, 100000))])
            writer.writerow(row)


def test_runtime_generated_clean_inputs(tmp_path):
    cases = [(4, 1, True), (9, 3, False), (27, 5, False), (1203, 4, False)]
    for index, (rows, symbols, unicode_name) in enumerate(cases):
        path = tmp_path / f"ticks_{secrets.token_hex(8)}_{index}.csv"
        make_random_csv(path, rows, symbols, unicode_name)
        assert_clean_result(str(path))


def test_runtime_generated_invalid_utf8_and_null(tmp_path):
    base_path = tmp_path / f"base_{secrets.token_hex(8)}.csv"
    make_random_csv(base_path, 13, 3, False)
    valid = base_path.read_bytes()
    bad_sequences = [b"\x00", b"\x80", b"\xc0\xaf", b"\xe2\x28\xa1", b"\xf4\x90\x80\x80"]
    rng = secrets.SystemRandom()

    for index, bad in enumerate(bad_sequences):
        filepath = tmp_path / f"input_{secrets.token_hex(10)}_{index}.csv"
        position = rng.randrange(0, len(valid) + 1)
        filepath.write_bytes(valid[:position] + bad + valid[position:])

        try:
            os.remove(LOG_FILE)
        except FileNotFoundError:
            pass

        result = subprocess.run([EXECUTABLE, str(filepath)], capture_output=True)
        stderr = result.stderr.decode("utf-8", errors="replace")
        assert result.returncode == 1, f"Invalid input returned {result.returncode}: {filepath}"
        assert "REJECTED" in stderr, f"REJECTED missing from stderr for {filepath}"
        assert os.path.isfile(LOG_FILE), f"Log file missing after rejecting {filepath}"
        with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
            log_content = f.read()
        expected_log = f"ERROR: Invalid encoding in file {filepath}"
        assert expected_log in log_content, f"Missing expected log entry for {filepath}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
