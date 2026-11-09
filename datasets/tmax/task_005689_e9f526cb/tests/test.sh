#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_material_cleaner.py
import csv
import json
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT = Path('/home/user/material_cleaner')
MANIFEST = PROJECT / 'Cargo.toml'
DATASET = Path('/home/user/materials.csv')
OUTPUT = Path('/home/user/output.json')
FEATURES = [
    'density',
    'tensile_strength',
    'flexibility',
    'thermal_conductivity',
    'electrical_conductivity',
]
EXPECTED_DROPPED = ['flexibility']
EXPECTED_SIMILAR = [33, 41, 27]


def regular_file(path):
    return path.exists() and stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink()


def read_result():
    assert OUTPUT.is_file(), f'Expected output file {OUTPUT} does not exist.'
    try:
        with OUTPUT.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {OUTPUT} does not contain valid JSON: {exc}')
    assert isinstance(data, dict), 'output.json must contain a JSON object.'
    assert 'dropped_features' in data, "Key 'dropped_features' is missing from the JSON output."
    assert 'similar_to_1' in data, "Key 'similar_to_1' is missing from the JSON output."
    return data


def assert_original_result(data):
    assert data['dropped_features'] == EXPECTED_DROPPED, (
        f"Expected dropped_features to be {EXPECTED_DROPPED}, but got {data['dropped_features']}."
    )
    assert data['similar_to_1'] == EXPECTED_SIMILAR, (
        f"Expected similar_to_1 to be {EXPECTED_SIMILAR}, but got {data['similar_to_1']}."
    )


def cargo_metadata():
    proc = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(MANIFEST)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f'Cargo project metadata failed:\n{proc.stderr}'
    metadata = json.loads(proc.stdout)
    bins = []
    project_root = PROJECT.resolve()
    for package in metadata.get('packages', []):
        if Path(package['manifest_path']).resolve() != MANIFEST.resolve():
            continue
        for target in package.get('targets', []):
            if 'bin' in target.get('kind', []):
                source = Path(target['src_path'])
                try:
                    source.resolve().relative_to(project_root)
                except ValueError:
                    continue
                if source.suffix == '.rs' and regular_file(source):
                    bins.append(target['name'])
    assert bins, 'The Cargo project must contain a regular Rust source file for a binary target.'
    return bins


def run_program(bin_names):
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    command = ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST)]
    if len(bin_names) == 1:
        command += ['--bin', bin_names[0]]
    proc = subprocess.run(
        command,
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, (
        f'The Rust program failed with exit status {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    return read_result()


def write_original_dataset():
    np.random.seed(42)
    n = 50
    tensile = np.random.uniform(100.0, 500.0, n)  # replaced below after density draw
    np.random.seed(42)
    density = np.random.uniform(1.0, 10.0, n)
    tensile = np.random.uniform(100.0, 500.0, n)
    flexibility = -0.8 * tensile + np.random.normal(0, 5.0, n)
    thermal = np.random.uniform(10.0, 50.0, n)
    electrical = np.random.uniform(1.0, 5.0, n)
    pd.DataFrame({
        'id': np.arange(1, n + 1),
        'density': density,
        'tensile_strength': tensile,
        'flexibility': flexibility,
        'thermal_conductivity': thermal,
        'electrical_conductivity': electrical,
    }).to_csv(DATASET, index=False)


def pearson(a, b):
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    da = [x - ma for x in a]
    db = [x - mb for x in b]
    denom = math.sqrt(sum(x*x for x in da) * sum(x*x for x in db))
    assert denom != 0
    return sum(x*y for x, y in zip(da, db)) / denom


def expected_for(rows):
    columns = {name: [float(row[name]) for row in rows] for name in FEATURES}
    dropped = []
    for later in range(1, len(FEATURES)):
        for earlier in range(later):
            if abs(pearson(columns[FEATURES[earlier]], columns[FEATURES[later]])) > 0.95:
                dropped.append(FEATURES[later])
                break

    remaining = [name for name in FEATURES if name not in dropped]
    normalized = {}
    for name in remaining:
        values = columns[name]
        low, high = min(values), max(values)
        assert high > low
        normalized[name] = [(x - low) / (high - low) for x in values]

    target_index = next(i for i, row in enumerate(rows) if int(row['id']) == 1)
    distances = []
    for i, row in enumerate(rows):
        item_id = int(row['id'])
        if item_id == 1:
            continue
        distance = math.sqrt(sum(
            (normalized[name][i] - normalized[name][target_index]) ** 2
            for name in remaining
        ))
        distances.append((distance, item_id))
    distances.sort(key=lambda item: (item[0], item[1]))
    return {'dropped_features': dropped, 'similar_to_1': [item_id for _, item_id in distances[:3]]}


def make_case(mode):
    rng = np.random.default_rng(secrets.randbits(64))
    n = 43
    density = rng.uniform(1.0, 12.0, n)
    tensile = rng.uniform(50.0, 650.0, n)
    flexibility = rng.uniform(-400.0, 200.0, n)
    thermal = rng.uniform(3.0, 90.0, n)
    electrical = rng.uniform(0.2, 9.0, n)

    if mode == 0:
        flexibility = -rng.uniform(0.5, 2.0) * tensile + rng.normal(0.0, 0.25, n)
    elif mode == 1:
        thermal = rng.uniform(2.0, 7.0) * density + rng.normal(0.0, 0.01, n)
        electrical = rng.uniform(0.01, 0.04) * tensile + rng.normal(0.0, 0.01, n)
    elif mode == 2:
        # Two exact zero-distance recommendations exercise the lower-id tie rule.
        density[1:3] = density[0]
        tensile[1:3] = tensile[0]
        flexibility[1:3] = flexibility[0]
        thermal[1:3] = thermal[0]
        electrical[1:3] = electrical[0]

    rows = []
    for i in range(n):
        rows.append({
            'id': i + 1,
            'density': float(density[i]),
            'tensile_strength': float(tensile[i]),
            'flexibility': float(flexibility[i]),
            'thermal_conductivity': float(thermal[i]),
            'electrical_conductivity': float(electrical[i]),
        })
    return rows


def write_rows(rows):
    with DATASET.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['id'] + FEATURES)
        writer.writeheader()
        writer.writerows(rows)


# Preserve the original verifier's assertions on the agent-created output.
initial = read_result()
assert_original_result(initial)

assert PROJECT.is_dir(), f'Expected Cargo project directory {PROJECT} does not exist.'
assert regular_file(MANIFEST), f'Expected a regular Cargo manifest at {MANIFEST}.'
bin_names = cargo_metadata()

saved_dataset = DATASET.read_bytes() if DATASET.exists() else None
saved_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
try:
    # Execute the submitted Rust artifact against the canonical task dataset.
    write_original_dataset()
    canonical = run_program(bin_names)
    assert_original_result(canonical)

    # Exercise correlation, dropping, normalization, distance ranking, and ties
    # on fresh inputs whose expected answers are independently computed.
    for mode in range(3):
        rows = make_case(mode)
        expected = expected_for(rows)
        write_rows(rows)
        actual = run_program(bin_names)
        assert actual['dropped_features'] == expected['dropped_features'], (
            f"Dynamic case {mode}: expected dropped_features {expected['dropped_features']}, "
            f"got {actual['dropped_features']}."
        )
        assert actual['similar_to_1'] == expected['similar_to_1'], (
            f"Dynamic case {mode}: expected similar_to_1 {expected['similar_to_1']}, "
            f"got {actual['similar_to_1']}."
        )
finally:
    if saved_dataset is None:
        if DATASET.exists():
            DATASET.unlink()
    else:
        DATASET.write_bytes(saved_dataset)
    if saved_output is None:
        if OUTPUT.exists():
            OUTPUT.unlink()
    else:
        OUTPUT.write_bytes(saved_output)
PY_EOF

if python3 /tmp/verify_material_cleaner.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
