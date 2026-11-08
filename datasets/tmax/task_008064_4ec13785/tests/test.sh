#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT_PATH = Path('/home/user/pricing_tool')
CSV_PATH = Path('/home/user/data/products.csv')
OUTPUT_PATH = Path('/home/user/output/analysis.json')
MANIFEST_PATH = PROJECT_PATH / 'Cargo.toml'


def compute_expected_results(csv_path):
    products = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            products[row['id']] = {
                'f1': float(row['feature1']),
                'f2': float(row['feature2']),
                'f3': float(row['feature3']),
                'price': float(row['price'])
            }

    underpriced_count = 0
    overpriced_count = 0

    for pid, data in products.items():
        predicted = (2.5 * data['f1']) + (1.2 * data['f2']) - (0.8 * data['f3']) + 15.0
        if data['price'] < predicted - 5.0:
            underpriced_count += 1
        elif data['price'] > predicted + 5.0:
            overpriced_count += 1

    p001_data = products.get('P001')
    closest_id = None
    min_dist = float('inf')

    if p001_data:
        for pid, data in products.items():
            if pid == 'P001':
                continue
            dist = math.sqrt(
                (data['f1'] - p001_data['f1'])**2 +
                (data['f2'] - p001_data['f2'])**2 +
                (data['f3'] - p001_data['f3'])**2
            )
            if dist < min_dist:
                min_dist = dist
                closest_id = pid

    return closest_id, underpriced_count, overpriced_count


def assert_output_correct(csv_path):
    output_path = str(OUTPUT_PATH)
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    expected_closest, expected_under, expected_over = compute_expected_results(csv_path)

    assert "P001_closest_id" in output_data, "Missing key 'P001_closest_id' in output JSON."
    assert "underpriced_count" in output_data, "Missing key 'underpriced_count' in output JSON."
    assert "overpriced_count" in output_data, "Missing key 'overpriced_count' in output JSON."

    assert output_data["P001_closest_id"] == expected_closest, \
        f"Expected P001_closest_id to be {expected_closest}, got {output_data['P001_closest_id']}"

    assert output_data["underpriced_count"] == expected_under, \
        f"Expected underpriced_count to be {expected_under}, got {output_data['underpriced_count']}"

    assert output_data["overpriced_count"] == expected_over, \
        f"Expected overpriced_count to be {expected_over}, got {output_data['overpriced_count']}"


def cargo_environment():
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    if Path('/home/user/.cargo').is_dir():
        env['CARGO_HOME'] = '/home/user/.cargo'
    return env


def verify_rust_project():
    assert PROJECT_PATH.is_dir(), f"Rust project directory {PROJECT_PATH} does not exist."
    assert MANIFEST_PATH.is_file(), f"Cargo manifest {MANIFEST_PATH} does not exist."

    result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(MANIFEST_PATH)],
        cwd=str(PROJECT_PATH), env=cargo_environment(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f"Invalid Cargo project:\n{result.stderr}"

    metadata = json.loads(result.stdout)
    project_root = PROJECT_PATH.resolve()
    binary_sources = []
    for package in metadata.get('packages', []):
        for target in package.get('targets', []):
            if 'bin' in target.get('kind', []):
                source = Path(target['src_path']).resolve()
                try:
                    source.relative_to(project_root)
                except ValueError:
                    continue
                if source.is_file() and source.suffix == '.rs':
                    binary_sources.append(source)
    assert binary_sources, "Cargo project does not contain a Rust binary target."


def run_rust_pipeline():
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST_PATH)],
        cwd=str(PROJECT_PATH), env=cargo_environment(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180
    )
    assert result.returncode == 0, f"Rust pipeline failed to run:\n{result.stderr}"
    assert OUTPUT_PATH.is_file(), \
        f"Rust pipeline did not create {OUTPUT_PATH}."


def make_challenge_csv():
    nearest_id = 'Q' + secrets.token_hex(6).upper()
    other_ids = ['Q' + secrets.token_hex(6).upper() for _ in range(5)]
    base = secrets.randbelow(20) + 10
    rows = [
        ('P001', base, base + 1, base - 2, 'fair'),
        (nearest_id, base + 0.2, base + 0.1, base - 1.9, 'under'),
        (other_ids[0], base + 7, base - 6, base + 5, 'over'),
        (other_ids[1], base - 8, base + 7, base - 6, 'under'),
        (other_ids[2], base + 10, base + 8, base + 9, 'over'),
        (other_ids[3], base - 9, base - 8, base + 7, 'fair'),
        (other_ids[4], base + 12, base - 9, base - 8, 'over'),
    ]

    lines = ['id,feature1,feature2,feature3,price']
    for pid, f1, f2, f3, classification in rows:
        predicted = (2.5 * f1) + (1.2 * f2) - (0.8 * f3) + 15.0
        if classification == 'under':
            price = predicted - 11.0
        elif classification == 'over':
            price = predicted + 11.0
        else:
            price = predicted
        lines.append(f'{pid},{f1},{f2},{f3},{price}')
    return '\n'.join(lines) + '\n'


def test_rust_pipeline_and_analysis_output():
    verify_rust_project()
    original_csv = CSV_PATH.read_bytes()

    try:
        # Execute the submitted Rust program against the provided dataset, then
        # retain all original output assertions.
        run_rust_pipeline()
        assert_output_correct(str(CSV_PATH))

        # Exercise the same pipeline on an unpredictable dataset so a fixed JSON
        # file or hard-coded answer cannot pass.
        CSV_PATH.write_text(make_challenge_csv(), encoding='utf-8')
        run_rust_pipeline()
        assert_output_correct(str(CSV_PATH))

        # Restore the provided dataset and leave its program-generated result in
        # the required output location.
        CSV_PATH.write_bytes(original_csv)
        run_rust_pipeline()
        assert_output_correct(str(CSV_PATH))
    finally:
        CSV_PATH.write_bytes(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
