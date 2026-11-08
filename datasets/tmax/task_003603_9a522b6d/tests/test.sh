#!/bin/bash
set +e
mkdir -p /logs/verifier
success=1
RAW='/home/user/data/raw_expression.json'
RESULTS='/home/user/results/gene_fits.csv'
SCRIPT='/home/user/analyze.py'
BACKUP=$(mktemp)
cp "$RAW" "$BACKUP" || success=0

# Require and execute the requested analysis script on the original dataset.
if [[ ! -f "$SCRIPT" || -L "$SCRIPT" || ! -s "$SCRIPT" ]]; then
    success=0
else
    rm -f "$RESULTS"
    if ! timeout 120s python3 "$SCRIPT"; then
        success=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest

RESULTS_FILE = '/home/user/results/gene_fits.csv'

def test_results_file_exists():
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."

def test_csv_headers():
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."
    with open(RESULTS_FILE, 'r') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"File {RESULTS_FILE} is empty.")
    expected_headers = ['gene_id', 'amplitude', 'period', 'phase', 'baseline']
    assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

def test_csv_sorting_and_rounding():
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."
    with open(RESULTS_FILE, 'r') as f:
        rows = list(csv.DictReader(f))
    gene_ids = [row['gene_id'] for row in rows]
    assert gene_ids == sorted(gene_ids), "The rows are not sorted alphabetically by gene_id."
    for row in rows:
        for col in ['amplitude', 'period', 'phase', 'baseline']:
            val_str = row[col]
            if '.' in val_str:
                decimals = val_str.split('.')[1]
                assert len(decimals) == 3, f"Value {val_str} for {col} in gene {row['gene_id']} is not rounded to exactly 3 decimal places."
            else:
                pytest.fail(f"Value {val_str} for {col} in gene {row['gene_id']} does not have decimal places.")

def test_csv_values():
    assert os.path.isfile(RESULTS_FILE), f"Expected output file {RESULTS_FILE} does not exist."
    expected = {
        'BMAL1': {'amplitude': 15.143, 'period': 23.829, 'phase': 3.962, 'baseline': 29.870},
        'CLOCK': {'amplitude': 4.909, 'period': 24.536, 'phase': 2.443, 'baseline': 15.035},
        'PER1': {'amplitude': 9.873, 'period': 24.150, 'phase': 0.942, 'baseline': 20.010}
    }
    with open(RESULTS_FILE, 'r') as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 3, f"Expected exactly 3 rows of data, got {len(rows)}."
    for row in rows:
        g = row['gene_id']
        assert g in expected, f"Unexpected gene_id {g} in results."
        try:
            amp = float(row['amplitude'])
            period = float(row['period'])
            phase = float(row['phase'])
            baseline = float(row['baseline'])
        except ValueError as e:
            pytest.fail(f"Could not parse numeric values for gene {g}: {e}")
        assert abs(amp - expected[g]['amplitude']) < 0.1, f"Amplitude for {g} is {amp}, expected ~{expected[g]['amplitude']}."
        assert abs(period - expected[g]['period']) < 0.1, f"Period for {g} is {period}, expected ~{expected[g]['period']}."
        assert abs(phase - expected[g]['phase']) < 0.1, f"Phase for {g} is {phase}, expected ~{expected[g]['phase']}."
        assert abs(baseline - expected[g]['baseline']) < 0.1, f"Baseline for {g} is {baseline}, expected ~{expected[g]['baseline']}."
TEST_EOF

if [[ $success -eq 1 ]] && ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    success=0
fi

# Replace the input with an unseen deterministic dataset, then run the submitted
# script again. This prevents a precomputed CSV for the original records from passing.
if [[ $success -eq 1 ]]; then
python3 - << 'PY_EOF'
import json
import numpy as np

rng = np.random.default_rng(91827)
params = {
    'ALPHA': (7.4, 16.0, 0.65, 12.5),
    'DELTA': (11.2, 24.0, 2.15, 31.0),
    'OMEGA': (4.8, 32.0, 5.10, 8.2),
}
records = []
for gene, (amp, period, phase, baseline) in params.items():
    for t in np.arange(0.0, 96.0, 2.0):
        y = amp * np.cos(2.0 * np.pi * t / period + phase) + baseline
        y += rng.normal(0.0, 0.18)
        records.append({
            'gene_id': gene,
            'time_hours': float(t),
            'expression_level': round(float(y), 4),
        })
rng.shuffle(records)
with open('/home/user/data/raw_expression.json', 'w') as f:
    json.dump(records, f, indent=2)
PY_EOF
    if [[ $? -ne 0 ]]; then
        success=0
    else
        rm -f "$RESULTS"
        if ! timeout 120s python3 "$SCRIPT"; then
            success=0
        fi
    fi
fi

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import csv
import json
import math
import os
import re

import numpy as np
from scipy.optimize import curve_fit

RAW = '/home/user/data/raw_expression.json'
RESULTS = '/home/user/results/gene_fits.csv'
COLS = ['gene_id', 'amplitude', 'period', 'phase', 'baseline']
NUMERIC = COLS[1:]

def model(t, amplitude, period, phase, baseline):
    return amplitude * np.cos(2.0 * np.pi * t / period + phase) + baseline

def derive_expected():
    with open(RAW) as f:
        records = json.load(f)
    grouped = {}
    for record in records:
        grouped.setdefault(record['gene_id'], []).append(record)
    expected = {}
    for gene, group in grouped.items():
        group = sorted(group, key=lambda r: float(r['time_hours']))
        t = np.asarray([float(r['time_hours']) for r in group], dtype=float)
        y = np.asarray([float(r['expression_level']) for r in group], dtype=float)
        spacing = float(np.median(np.diff(t)))
        frequencies = np.fft.rfftfreq(len(y), d=spacing)
        power = np.abs(np.fft.rfft(y - np.mean(y)))
        power[0] = 0.0
        dominant_frequency = frequencies[int(np.argmax(power))]
        period_guess = 1.0 / dominant_frequency
        p0 = [(float(np.max(y)) - float(np.min(y))) / 2.0,
              period_guess, 0.0, float(np.mean(y))]
        fitted, _ = curve_fit(model, t, y, p0=p0, maxfev=100000)
        amplitude, period, phase, baseline = map(float, fitted)
        if amplitude < 0:
            amplitude = -amplitude
            phase += math.pi
        if period < 0:
            period = -period
            phase = -phase
        phase %= 2.0 * math.pi
        expected[gene] = {
            'amplitude': amplitude,
            'period': period,
            'phase': phase,
            'baseline': baseline,
        }
    return expected

def test_unseen_dataset_results():
    assert os.path.isfile(RESULTS), f'Expected output file {RESULTS} does not exist.'
    with open(RESULTS, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == COLS, f'Expected headers {COLS}, got {reader.fieldnames}.'
        rows = list(reader)
    expected = derive_expected()
    assert len(rows) == len(expected), f'Expected {len(expected)} rows, got {len(rows)}.'
    ids = [row['gene_id'] for row in rows]
    assert ids == sorted(expected), f'Rows must contain every gene exactly once in alphabetical order; got {ids}.'
    for row in rows:
        gene = row['gene_id']
        for column in NUMERIC:
            text = row[column]
            assert re.fullmatch(r'-?\d+\.\d{3}', text), f'{gene} {column} is not formatted to exactly 3 decimals: {text}'
            value = float(text)
            assert math.isfinite(value), f'{gene} {column} is not finite.'
            assert abs(value - expected[gene][column]) < 0.12, (
                f'{column} for {gene} is {value}, expected approximately {expected[gene][column]:.3f}.'
            )
        assert float(row['amplitude']) > 0.0, f'Amplitude for {gene} must be positive.'
        assert 0.0 <= float(row['phase']) < 2.0 * math.pi, f'Phase for {gene} is not normalized.'
DYNAMIC_EOF

if [[ $success -eq 1 ]] && ! python3 -m pytest /tmp/test_dynamic.py -x --tb=short; then
    success=0
fi

cp "$BACKUP" "$RAW" 2>/dev/null
rm -f "$BACKUP"

if [[ $success -eq 1 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
