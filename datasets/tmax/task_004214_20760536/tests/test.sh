#!/bin/bash
mkdir -p /logs/verifier

verify() (
    set -e

    project=/home/user/iot_pipeline
    metrics=/home/user/model_metrics.json
    data=/home/user/data/raw_sensors.csv

    test -d "$project"
    test -f "$project/Cargo.toml"
    test -d "$project/src"
    find "$project/src" -type f -name '*.rs' -print -quit | grep -q .

    cd "$project"
    cargo metadata --no-deps --format-version 1 > /tmp/iot_metadata.json
    python3 - <<'PY'
import json
with open('/tmp/iot_metadata.json') as f:
    metadata = json.load(f)
packages = [p for p in metadata['packages'] if p['manifest_path'] == '/home/user/iot_pipeline/Cargo.toml']
assert packages, 'Cargo project package was not found'
assert any(d['name'] == 'nalgebra' for d in packages[0]['dependencies']), 'nalgebra must be a project dependency'
PY

    python3 - <<'PY'
from pathlib import Path
import re
src = '\n'.join(p.read_text(errors='ignore') for p in Path('/home/user/iot_pipeline/src').rglob('*.rs'))
assert re.search(r'\bnalgebra\b', src), 'Rust source must use nalgebra'
assert re.search(r'\.transpose\s*\(', src), 'OLS implementation must transpose the design matrix'
assert re.search(r'(?:try_)?inverse\s*\(', src), 'OLS implementation must invert X^T X'
assert re.search(r'\bInstant\b', src), 'Inference benchmark must measure elapsed time'
assert re.search(r'\b(?:1000|1_000)\b', src), 'Inference benchmark must specify 1,000 iterations'
assert re.search(r'\b(?:for|while|loop)\b', src), 'Inference benchmark must contain an iteration loop'
PY

    cargo build --release

    rm -f "$metrics"
    timeout 180 cargo run --release
    test -f "$metrics"

    python3 - <<'PY'
import json, math, os
path = '/home/user/model_metrics.json'
assert os.path.isfile(path), f'Output file does not exist: {path}'
with open(path) as f:
    data = json.load(f)
assert 'intercept' in data, "Missing 'intercept' in JSON output."
assert 'weights' in data, "Missing 'weights' in JSON output."
assert 'avg_inference_micros' in data, "Missing 'avg_inference_micros' in JSON output."
assert isinstance(data['intercept'], (int, float)), 'Intercept must be a number.'
assert math.isclose(data['intercept'], 2.5, rel_tol=1e-3, abs_tol=1e-3), f"Intercept mismatch: expected 2.5, got {data['intercept']}"
assert isinstance(data['weights'], list), 'Weights must be an array.'
assert len(data['weights']) == 3, f"Weights array must have exactly 3 elements, got {len(data['weights'])}"
for i, expected in enumerate([1.5, -0.8, 0.4]):
    assert isinstance(data['weights'][i], (int, float)), f'Weight at index {i} must be a number.'
    assert math.isclose(data['weights'][i], expected, rel_tol=1e-3, abs_tol=1e-3), f"Weight {i} mismatch: expected {expected}, got {data['weights'][i]}"
assert isinstance(data['avg_inference_micros'], (int, float)), 'avg_inference_micros must be a number.'
assert data['avg_inference_micros'] >= 0, 'avg_inference_micros must be non-negative.'
assert math.isfinite(float(data['avg_inference_micros'])), 'avg_inference_micros must be finite.'
PY

    cp "$data" /tmp/raw_sensors.original.csv
    trap 'cp /tmp/raw_sensors.original.csv /home/user/data/raw_sensors.csv' EXIT

    python3 - <<'PY'
import csv, json, random, secrets
rng = random.Random(secrets.randbits(128))
coeff = [rng.uniform(-7, 7) for _ in range(4)]
rows = []
for i in range(1, 121):
    if i <= 25:
        s1 = rng.uniform(-8, -0.1) if i % 2 else rng.uniform(0.1, 9)
        s2 = rng.uniform(-8, -0.1) if i % 2 == 0 else rng.uniform(0.1, 9)
        target = rng.uniform(-1000, 1000)
    else:
        s1 = rng.uniform(0.1, 9)
        s2 = rng.uniform(0.1, 9)
        target = coeff[0] + coeff[1]*s1 + coeff[2]*s2 + coeff[3]*s1*s2
    rows.append((i, s1, s2, target))
with open('/home/user/data/raw_sensors.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['id', 'sensor_1', 'sensor_2', 'target'])
    w.writerows(rows)
PY

    rm -f "$metrics"
    timeout 180 cargo run --release
    test -f "$metrics"

    python3 - <<'PY'
import csv, json, math

def solve(a, b):
    n = len(b)
    a = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        assert abs(a[pivot][col]) > 1e-12
        a[col], a[pivot] = a[pivot], a[col]
        scale = a[col][col]
        a[col] = [v / scale for v in a[col]]
        for r in range(n):
            if r != col:
                factor = a[r][col]
                a[r] = [a[r][c] - factor*a[col][c] for c in range(n + 1)]
    return [a[i][n] for i in range(n)]

x, y = [], []
with open('/home/user/data/raw_sensors.csv', newline='') as f:
    for row in csv.DictReader(f):
        s1, s2 = float(row['sensor_1']), float(row['sensor_2'])
        if s1 < 0.0 or s2 < 0.0:
            continue
        x.append([1.0, s1, s2, s1*s2])
        y.append(float(row['target']))
xtx = [[sum(r[i]*r[j] for r in x) for j in range(4)] for i in range(4)]
xty = [sum(r[i]*t for r, t in zip(x, y)) for i in range(4)]
expected = solve(xtx, xty)
with open('/home/user/model_metrics.json') as f:
    data = json.load(f)
assert set(('intercept', 'weights', 'avg_inference_micros')).issubset(data)
assert isinstance(data['intercept'], (int, float)) and math.isfinite(float(data['intercept']))
assert isinstance(data['weights'], list) and len(data['weights']) == 3
actual = [data['intercept']] + data['weights']
for i, (got, want) in enumerate(zip(actual, expected)):
    assert isinstance(got, (int, float)) and math.isfinite(float(got))
    assert math.isclose(got, want, rel_tol=1e-3, abs_tol=1e-3), f'Dynamic OLS coefficient {i} mismatch: expected {want}, got {got}'
assert isinstance(data['avg_inference_micros'], (int, float))
assert math.isfinite(float(data['avg_inference_micros'])) and data['avg_inference_micros'] >= 0
PY
)

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
