#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
from pathlib import Path
import secrets
import stat
import subprocess

PROJECT = Path('/home/user/target_encoder')
DATASET = Path('/home/user/dataset.csv')
TRAIN_OUT = Path('/home/user/train_encoded.csv')
TEST_OUT = Path('/home/user/test_encoded.csv')
BINARY = PROJECT / 'target/debug/target_encoder'

CANONICAL_DATASET = '''id,category,target
1,A,1.0
2,B,0.0
3,A,1.0
4,C,0.0
5,A,0.0
6,B,1.0
7,B,1.0
8,C,0.0
9,A,1.0
10,D,1.0
'''

ORIGINAL_MAIN = '''use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/dataset.csv").unwrap();
    let reader = BufReader::new(file);
    let mut lines = reader.lines().skip(1); // skip header

    let mut data = Vec::new();
    let mut sum_target = 0.0;
    let mut counts = HashMap::new();
    let mut sums = HashMap::new();

    for line in lines {
        let l = line.unwrap();
        let parts: Vec<&str> = l.split(',').collect();
        let id = parts[0].to_string();
        let cat = parts[1].to_string();
        let target: f64 = parts[2].parse().unwrap();

        data.push((id, cat.clone(), target));
        sum_target += target;
        *counts.entry(cat.clone()).or_insert(0.0) += 1.0;
        *sums.entry(cat.clone()).or_insert(0.0) += target;
    }

    let global_mean = sum_target / data.len() as f64;
    let prior_weight = 10.0;

    let mut encoded_data = Vec::new();
    for (id, cat, target) in &data {
        let count = counts.get(cat).unwrap();
        let sum = sums.get(cat).unwrap();
        let cat_mean = sum / count;

        let encoded = (count * cat_mean + prior_weight * global_mean) / (count + prior_weight);
        encoded_data.push((id.clone(), cat.clone(), *target, encoded));
    }

    let split_idx = (encoded_data.len() as f64 * 0.8) as usize;
    let (train, test) = encoded_data.split_at(split_idx);

    let mut train_out = File::create("/home/user/train_encoded.csv").unwrap();
    writeln!(train_out, "id,category,target,encoded_feature").unwrap();
    for (id, cat, t, e) in train {
        writeln!(train_out, "{},{},{},{:.4}", id, cat, t, e).unwrap();
    }

    let mut test_out = File::create("/home/user/test_encoded.csv").unwrap();
    writeln!(test_out, "id,category,target,encoded_feature").unwrap();
    for (id, cat, t, e) in test {
        writeln!(test_out, "{},{},{},{:.4}", id, cat, t, e).unwrap();
    }
}
'''


def expected_rows(rows):
    split_idx = math.floor(len(rows) * 0.8)
    train = rows[:split_idx]
    total = sum(row[2] for row in train)
    global_mean = total / len(train)
    counts = {}
    sums = {}
    for _, category, target in train:
        counts[category] = counts.get(category, 0) + 1
        sums[category] = sums.get(category, 0.0) + target

    result = []
    for row_id, category, target in rows:
        if category in counts:
            count = counts[category]
            category_mean = sums[category] / count
            encoded = (count * category_mean + 10.0 * global_mean) / (count + 10.0)
        else:
            encoded = global_mean
        result.append((row_id, category, target, encoded))
    return result[:split_idx], result[split_idx:]


def write_dataset(rows):
    with DATASET.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'category', 'target'])
        for row_id, category, target in rows:
            writer.writerow([row_id, category, format(target, '.6f')])


def read_and_check(path, expected):
    with path.open(newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['id', 'category', 'target', 'encoded_feature']
        actual = list(reader)
    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        row_id, category, target, encoded = want
        assert got['id'] == row_id
        assert got['category'] == category
        assert math.isclose(float(got['target']), target, rel_tol=0.0, abs_tol=1e-9)
        assert math.isclose(float(got['encoded_feature']), encoded, rel_tol=0.0, abs_tol=0.000051), \
            f"wrong encoding for {row_id}: expected {encoded}, got {got['encoded_feature']}"


def make_case(length):
    token = secrets.token_hex(5)
    train_len = math.floor(length * 0.8)
    train_categories = [f'A_{token}', f'B_{token}', f'C_{token}']
    rows = []
    for i in range(train_len):
        target = round(secrets.randbelow(6000001) / 1000000.0 - 2.0, 6)
        rows.append((f'{token}_{i}', train_categories[i % len(train_categories)], target))
    for i in range(train_len, length):
        category = train_categories[0] if i == train_len else f'UNSEEN_{token}_{i}'
        target = round(secrets.randbelow(8000001) / 1000000.0 + 5.0, 6)
        rows.append((f'{token}_{i}', category, target))
    return rows


def test_rust_source_is_changed_and_pipeline_handles_derived_inputs():
    main_rs = PROJECT / 'src/main.rs'
    assert main_rs.is_file(), 'src/main.rs is missing'
    assert main_rs.read_text() != ORIGINAL_MAIN, 'src/main.rs is still the original leaking implementation'

    saved_dataset = DATASET.read_bytes() if DATASET.exists() else None
    saved_outputs = {
        path: path.read_bytes() if path.exists() else None
        for path in (TRAIN_OUT, TEST_OUT)
    }
    try:
        clean = subprocess.run(['/usr/bin/cargo', 'clean'], cwd=PROJECT, capture_output=True, text=True)
        assert clean.returncode == 0, clean.stderr
        build = subprocess.run(['/usr/bin/cargo', 'build'], cwd=PROJECT, capture_output=True, text=True, timeout=120)
        assert build.returncode == 0, f'cargo build failed:\n{build.stdout}\n{build.stderr}'
        assert BINARY.is_file(), 'cargo build did not produce the target_encoder executable'
        assert os.access(BINARY, os.X_OK), 'built target_encoder artifact is not executable'
        assert BINARY.read_bytes()[:4] == b'\x7fELF', 'built artifact is not a native executable'

        for length in (5, 9, 13):
            rows = make_case(length)
            write_dataset(rows)
            for output in (TRAIN_OUT, TEST_OUT):
                if output.exists():
                    output.unlink()
            run = subprocess.run([str(BINARY)], cwd=PROJECT, capture_output=True, text=True, timeout=30)
            assert run.returncode == 0, f'built program failed:\n{run.stdout}\n{run.stderr}'
            assert TRAIN_OUT.is_file(), 'program did not create train_encoded.csv'
            assert TEST_OUT.is_file(), 'program did not create test_encoded.csv'
            expected_train, expected_test = expected_rows(rows)
            read_and_check(TRAIN_OUT, expected_train)
            read_and_check(TEST_OUT, expected_test)
    finally:
        if saved_dataset is None:
            DATASET.unlink(missing_ok=True)
        else:
            DATASET.write_bytes(saved_dataset)
        for path, contents in saved_outputs.items():
            if contents is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(contents)


def test_bash_script_exists_and_executable():
    script_path = '/home/user/test_repro.sh'
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_bash_script_execution():
    script_path = '/home/user/test_repro.sh'
    DATASET.write_text(CANONICAL_DATASET)
    TRAIN_OUT.unlink(missing_ok=True)
    TEST_OUT.unlink(missing_ok=True)
    clean = subprocess.run(['/usr/bin/cargo', 'clean'], cwd=PROJECT, capture_output=True, text=True)
    assert clean.returncode == 0, clean.stderr
    result = subprocess.run(['bash', script_path], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"{script_path} failed to execute successfully. stderr: {result.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'test_repro.sh did not compile the Rust project'


def test_encoded_files_exist():
    assert os.path.isfile('/home/user/train_encoded.csv'), "train_encoded.csv is missing."
    assert os.path.isfile('/home/user/test_encoded.csv'), "test_encoded.csv is missing."


def test_encoded_values():
    # Expected values derived from the 80/20 split of the dataset
    # Train: first 8 rows
    # Test: last 2 rows
    # Global mean (train) = 4.0 / 8 = 0.5
    # Prior weight = 10.0
    # A encoded = (3 * (2/3) + 10 * 0.5) / 13 = 7 / 13 ≈ 0.5385
    # B encoded = (3 * (2/3) + 10 * 0.5) / 13 = 7 / 13 ≈ 0.5385
    # C encoded = (2 * 0 + 10 * 0.5) / 12 = 5 / 12 ≈ 0.4167
    # D encoded (unseen) = 0.5

    expected_train = {
        '1': '0.538',
        '2': '0.538',
        '3': '0.538',
        '4': '0.416',
        '5': '0.538',
        '6': '0.538',
        '7': '0.538',
        '8': '0.416',
    }

    expected_test = {
        '9': '0.538',
        '10': '0.500',
    }

    with open('/home/user/train_encoded.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        assert len(rows) == 8, "train_encoded.csv should have exactly 8 data rows."
        for row in rows:
            assert 'encoded_feature' in row, "Missing 'encoded_feature' column in train_encoded.csv"
            expected_prefix = expected_train[row['id']]
            assert row['encoded_feature'].startswith(expected_prefix), \
                f"Row {row['id']} in train_encoded.csv has wrong encoded_feature. Expected starting with {expected_prefix}, got {row['encoded_feature']}"

    with open('/home/user/test_encoded.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        assert len(rows) == 2, "test_encoded.csv should have exactly 2 data rows."
        for row in rows:
            assert 'encoded_feature' in row, "Missing 'encoded_feature' column in test_encoded.csv"
            expected_prefix = expected_test[row['id']]
            assert row['encoded_feature'].startswith(expected_prefix), \
                f"Row {row['id']} in test_encoded.csv has wrong encoded_feature. Expected starting with {expected_prefix}, got {row['encoded_feature']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
