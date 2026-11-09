#!/bin/bash
mkdir -p /logs/verifier

verify() {
    test -d /home/user/data_prep || return 1
    test -f /home/user/data_prep/Cargo.toml || return 1
    test -d /home/user/data_prep/src || return 1
    find /home/user/data_prep/src -type f -name '*.rs' -print -quit | grep -q . || return 1
    grep -R -q 'StdRng' /home/user/data_prep/src --include='*.rs' || return 1
    grep -R -q 'seed_from_u64' /home/user/data_prep/src --include='*.rs' || return 1

    cp /home/user/input.csv /tmp/original_input.csv || return 1

    cat > /tmp/test_final_state.py <<'TEST_EOF'
import csv
import math
import os

EXPECTED_HEADERS = ['id', 'word_count', 'sensor_value', 'is_outlier']


def get_input_data():
    input_path = '/home/user/input.csv'
    assert os.path.exists(input_path), f"Input file {input_path} is missing."
    with open(input_path, 'r', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def compute_expected():
    data = get_input_data()
    train_size = int(len(data) * 0.8)
    train_data = data[:train_size]
    test_data = data[train_size:]

    train_known_values = [
        float(row['sensor_value'])
        for row in train_data
        if row['sensor_value'].strip() != ''
    ]
    train_mean = sum(train_known_values) / len(train_known_values)
    variance = sum((x - train_mean) ** 2 for x in train_known_values) / len(train_known_values)
    train_std = math.sqrt(variance)
    upper_bound = train_mean + 2 * train_std
    lower_bound = train_mean - 2 * train_std

    def process_row(row):
        sensor_value = (
            train_mean
            if row['sensor_value'].strip() == ''
            else float(row['sensor_value'])
        )
        return {
            'id': row['id'],
            'word_count': str(len(row['text_log'].split())),
            'sensor_value': sensor_value,
            'is_outlier': str(int(sensor_value > upper_bound or sensor_value < lower_bound)),
        }

    return ([process_row(row) for row in train_data],
            [process_row(row) for row in test_data])


def read_csv(path):
    assert os.path.exists(path), f"Output file {path} is missing."
    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == EXPECTED_HEADERS, (
            f"Column headers mismatch in {path}. Expected {EXPECTED_HEADERS}, "
            f"got {reader.fieldnames}."
        )
        return list(reader)


def check_rows(path, expected_rows):
    actual_rows = read_csv(path)
    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch in {path}. Expected {len(expected_rows)}, "
        f"got {len(actual_rows)}."
    )

    for act, exp in zip(actual_rows, expected_rows):
        assert act['id'] == exp['id'], (
            f"ID mismatch in {path}: expected {exp['id']}, got {act['id']}"
        )
        assert act['word_count'] == exp['word_count'], (
            f"word_count mismatch for ID {act['id']} in {path}: "
            f"expected {exp['word_count']}, got {act['word_count']}"
        )
        assert act['is_outlier'] == exp['is_outlier'], (
            f"is_outlier mismatch for ID {act['id']} in {path}: "
            f"expected {exp['is_outlier']}, got {act['is_outlier']}"
        )
        act_val = float(act['sensor_value'])
        exp_val = float(exp['sensor_value'])
        assert abs(act_val - exp_val) <= 0.001, (
            f"sensor_value mismatch for ID {act['id']} in {path}: "
            f"expected {exp_val:.4f}, got {act_val:.4f}"
        )


def test_train_processed():
    expected_train, _ = compute_expected()
    check_rows('/home/user/train_processed.csv', expected_train)


def test_test_processed():
    _, expected_test = compute_expected()
    check_rows('/home/user/test_processed.csv', expected_test)


def test_train_bootstrapped():
    expected_train, _ = compute_expected()
    with open('/tmp/expected_bootstrap_indices.txt', 'r', encoding='utf-8') as f:
        indices = [int(line.strip()) for line in f if line.strip()]
    assert len(indices) == len(expected_train)
    expected_bootstrap = [expected_train[index] for index in indices]
    check_rows('/home/user/train_bootstrapped.csv', expected_bootstrap)
TEST_EOF

    # Exercise the submitted Rust program on verifier-selected data first.
    cat > /home/user/input.csv <<'DYNAMIC_EOF'
id,text_log,sensor_value
101,alpha beta,1.0
102,"comma, inside log",
103,three word entry here,2.0
104,single,4.0
105,five small words live here,5.0
106,missing again,
107,ordinary reading,7.0
108,another ordinary reading,8.0
109,high training reading,9.0
110,extreme training reading,50.0
111,test missing value,
112,test low,-20.0
113,test normal words,6.0
DYNAMIC_EOF

    rm -f /home/user/train_processed.csv /home/user/test_processed.csv /home/user/train_bootstrapped.csv
    (cd /home/user/data_prep && cargo run --quiet) || return 1

    # Build an independent sequence generator using the exact rand version locked
    # by the submitted project.
    test -f /home/user/data_prep/Cargo.lock || return 1
    RAND_VERSION=$(python3 - <<'PY'
import re
text = open('/home/user/data_prep/Cargo.lock', encoding='utf-8').read()
for block in text.split('[[package]]')[1:]:
    name = re.search(r'^name\s*=\s*"([^"]+)"', block, re.M)
    version = re.search(r'^version\s*=\s*"([^"]+)"', block, re.M)
    if name and version and name.group(1) == 'rand':
        print(version.group(1))
        break
PY
) || return 1
    test -n "$RAND_VERSION" || return 1

    rm -rf /tmp/rng_oracle
    mkdir -p /tmp/rng_oracle/src || return 1
    cat > /tmp/rng_oracle/Cargo.toml <<EOF
[package]
name = "rng_oracle"
version = "0.1.0"
edition = "2018"

[dependencies]
rand = "=$RAND_VERSION"
EOF
    cat > /tmp/rng_oracle/src/main.rs <<'RUST_EOF'
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use std::env;

fn main() {
    let n: usize = env::args().nth(1).unwrap().parse().unwrap();
    let mut rng = StdRng::seed_from_u64(42);
    for _ in 0..n {
        println!("{}", rng.gen_range(0..n));
    }
}
RUST_EOF

    (cd /tmp/rng_oracle && cargo run --quiet --offline -- 10 > /tmp/expected_bootstrap_indices.txt) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -q -x --tb=short || return 1

    # Restore the supplied input, execute the artifact again, and retain the
    # originally required outputs as the final state.
    cp /tmp/original_input.csv /home/user/input.csv || return 1
    rm -f /home/user/train_processed.csv /home/user/test_processed.csv /home/user/train_bootstrapped.csv
    (cd /home/user/data_prep && cargo run --quiet) || return 1
    (cd /tmp/rng_oracle && cargo run --quiet --offline -- 8 > /tmp/expected_bootstrap_indices.txt) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -q -x --tb=short || return 1
}

STATUS=0
verify || STATUS=$?

# Always restore the task input even when a verification step fails.
if test -f /tmp/original_input.csv; then
    cp /tmp/original_input.csv /home/user/input.csv
fi

if test "$STATUS" -eq 0; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
