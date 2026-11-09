#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

RAW_FILE = Path('/home/user/raw_spectra.txt')
FILTER_C = Path('/home/user/filter.c')
FILTER_BIN = Path('/home/user/filter.bin')
SCRIPT = Path('/home/user/process_spectra.sh')
FILTERED_FILE = Path('/home/user/filtered_spectra.txt')
PEAKS_FILE = Path('/home/user/peaks.log')
PLOT_FILE = Path('/home/user/plot.txt')
COMPILED_SOURCE = Path('/tmp/filter_from_source.bin')
FLOAT_2DP = re.compile(r'^[+-]?\d+\.\d{2}$')


def expected_data(rows):
    wavelengths = [w for w, _ in rows]
    intensities = [v for _, v in rows]
    n = len(rows)
    filtered = []
    for i, value in enumerate(intensities):
        if i < 2 or i >= n - 2:
            filtered.append(value)
        else:
            filtered.append(sum(intensities[i-2:i+3]) / 5.0)

    # The script consumes the two-decimal values written by the C program.
    filtered_text = [f'{value:.2f}' for value in filtered]
    filtered_values = [float(value) for value in filtered_text]

    peaks = []
    for i in range(1, n - 1):
        if filtered_values[i] > filtered_values[i-1] and filtered_values[i] > filtered_values[i+1]:
            peaks.append((wavelengths[i], filtered_text[i]))

    maximum = max(filtered_values) if filtered_values else 1.0
    plot = []
    for wavelength, value in zip(wavelengths, filtered_values):
        if value <= 0:
            stars = 0
        else:
            stars = math.floor((value / maximum) * 20)
            if stars < 0:
                stars = 0
        plot.append((wavelength, stars))
    return wavelengths, filtered_text, peaks, plot


def write_raw(rows):
    RAW_FILE.write_text(''.join(f'{w} {v}\n' for w, v in rows))


def read_nonempty_lines(path):
    assert path.is_file(), f'Missing {path}'
    return [line for line in path.read_text().splitlines() if line.strip()]


def check_filtered(rows):
    wavelengths, expected, _, _ = expected_data(rows)
    assert FILTERED_FILE.is_file(), f'Missing {FILTERED_FILE}'
    lines = FILTERED_FILE.read_text().splitlines()
    assert len(lines) == len(rows), f'Expected {len(rows)} lines in {FILTERED_FILE}, got {len(lines)}'
    for i, line in enumerate(lines):
        parts = line.split()
        assert len(parts) == 2, f'Line {i+1} in {FILTERED_FILE} is malformed: {line!r}'
        assert int(parts[0]) == wavelengths[i], f'Line {i+1} wavelength mismatch'
        assert FLOAT_2DP.fullmatch(parts[1]), f'Line {i+1} intensity is not formatted to exactly two decimals: {parts[1]!r}'
        assert parts[1] == expected[i], f'Line {i+1} intensity mismatch: expected {expected[i]}, got {parts[1]}'


def check_peaks(rows):
    _, _, expected, _ = expected_data(rows)
    lines = read_nonempty_lines(PEAKS_FILE)
    assert len(lines) == len(expected), f'Expected {len(expected)} peaks in {PEAKS_FILE}, got {len(lines)}'
    for i, (line, (expected_w, expected_v)) in enumerate(zip(lines, expected)):
        parts = line.split()
        assert len(parts) == 2, f'Peak line {i+1} is malformed: {line!r}'
        assert int(parts[0]) == expected_w, f'Peak {i+1} wavelength mismatch'
        assert FLOAT_2DP.fullmatch(parts[1]), f'Peak {i+1} intensity is not formatted to two decimals: {parts[1]!r}'
        assert parts[1] == expected_v, f'Peak {i+1} intensity mismatch: expected {expected_v}, got {parts[1]}'


def check_plot(rows):
    _, _, _, expected = expected_data(rows)
    assert PLOT_FILE.is_file(), f'Missing {PLOT_FILE}'
    lines = PLOT_FILE.read_text().splitlines()
    assert len(lines) == len(expected), f'Expected {len(expected)} lines in {PLOT_FILE}, got {len(lines)}'
    for i, (line, (wavelength, stars)) in enumerate(zip(lines, expected)):
        wanted = f'{wavelength} | ' + ('*' * stars)
        assert line == wanted, f'Plot line {i+1} mismatch: expected {wanted!r}, got {line!r}'


def run_pipeline(executable, rows):
    write_raw(rows)
    FILTERED_FILE.write_text('stale output\n')
    subprocess.run([str(executable)], check=True, timeout=10)
    check_filtered(rows)

    if PEAKS_FILE.exists():
        PEAKS_FILE.unlink()
    PLOT_FILE.write_text('stale plot\n')
    subprocess.run([str(SCRIPT)], check=True, timeout=10)

    # Preserve all original output assertions after actually running both artifacts.
    check_filtered(rows)
    check_peaks(rows)
    check_plot(rows)


def make_random_case():
    rng = secrets.SystemRandom()
    n = rng.randint(9, 22)
    wavelength = rng.randint(200, 900)
    rows = []
    values = [rng.randint(-8, 28) for _ in range(n)]
    values[0] = -3
    values[n // 2] = 35
    values[-1] = 0
    for value in values:
        wavelength += rng.randint(1, 4)
        rows.append((wavelength, float(value)))
    return rows


def test_complete_pipeline():
    assert RAW_FILE.is_file(), f'Missing {RAW_FILE}'
    assert FILTER_C.is_file(), f'Missing {FILTER_C}'
    assert FILTER_BIN.is_file(), f'Missing {FILTER_BIN}'
    assert SCRIPT.is_file(), f'Missing {SCRIPT}'
    assert os.access(FILTER_BIN, os.X_OK), f'{FILTER_BIN} is not executable'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable'
    assert FILTER_BIN.read_bytes()[:4] == b'\x7fELF', f'{FILTER_BIN} is not a compiled ELF executable'

    original_raw = RAW_FILE.read_bytes()
    original_rows = []
    for line in original_raw.decode().splitlines():
        if line.strip():
            w, v = line.split()
            original_rows.append((int(w), float(v)))

    subprocess.run(
        ['gcc', str(FILTER_C), '-o', str(COMPILED_SOURCE)],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert COMPILED_SOURCE.read_bytes()[:4] == b'\x7fELF'

    cases = [original_rows, make_random_case(), make_random_case(), make_random_case()]
    for rows in cases:
        # Exercise both the submitted binary and a fresh build of the submitted source.
        run_pipeline(FILTER_BIN, rows)
        run_pipeline(COMPILED_SOURCE, rows)

    # Leave and verify the requested final outputs for the original supplied input.
    RAW_FILE.write_bytes(original_raw)
    run_pipeline(FILTER_BIN, original_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
