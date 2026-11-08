#!/bin/bash
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:$PATH"
export CARGO_HOME=/opt/cargo
export RUSTUP_HOME=/opt/rust

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_result_file_exists():
    assert os.path.isfile("/home/user/result.txt"), "The file /home/user/result.txt does not exist. Did you run `cargo run > /home/user/result.txt`?"

def test_result_file_content():
    with open("/home/user/result.txt", "r") as f:
        content = f.read().strip()

    assert content, "The file /home/user/result.txt is empty."

    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"The content of /home/user/result.txt is not a valid float: '{content}'")

    expected_value = 52.6986
    tolerance = 0.01
    assert abs(value - expected_value) < tolerance, f"Expected value around {expected_value}, but got {value}. The data leak might not be fixed correctly."

def test_processor_file_modified():
    with open("/home/user/dataset_processor/src/processor.rs", "r") as f:
        content = f.read()

    assert "BUG: Data Leak" not in content or "calculate_mean(all_data)" not in content, "The data leak bug seems to still be present in src/processor.rs."
TEST_EOF

if (
    set -e
    project=/home/user/dataset_processor
    test -f "$project/Cargo.toml"
    test -f "$project/src/main.rs"
    test -f "$project/src/processor.rs"

    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    cd "$project"
    cargo test --quiet

    actual_output="$(cargo run --quiet)"
    python3 - "$actual_output" << 'PY'
import math
import sys

text = sys.argv[1].strip()
try:
    value = float(text)
except ValueError as exc:
    raise AssertionError(f"cargo run did not produce a single valid float: {text!r}") from exc
assert math.isfinite(value), f"cargo run produced a non-finite value: {value}"
assert abs(value - 52.6986) < 0.01, f"cargo run produced {value}, expected approximately 52.6986"

with open('/home/user/result.txt') as f:
    saved = float(f.read().strip())
assert abs(saved - value) < 0.0001, f"result.txt ({saved}) does not reflect cargo run output ({value})"
PY

    backup="$(mktemp)"
    cp -a "$project/src/main.rs" "$backup"
    restore_main() {
        rm -f "$project/src/main.rs"
        cp -a "$backup" "$project/src/main.rs"
        rm -f "$backup"
    }
    trap restore_main EXIT
    rm -f "$project/src/main.rs"

    python3 - "$project/src/main.rs" /tmp/process_data_expected.json << 'PY'
import json
import math
import random
import sys

main_path, expected_path = sys.argv[1:]
rng = random.SystemRandom()
cases = []
for _ in range(10):
    size = rng.randint(5, 14)
    split = rng.randint(2, size - 1)
    train = [round(rng.uniform(-50.0, 50.0), 6) for _ in range(split)]
    while max(train) - min(train) < 0.001:
        train = [round(rng.uniform(-50.0, 50.0), 6) for _ in range(split)]
    test = [round(rng.uniform(-250.0, 250.0), 6) for _ in range(size - split)]
    data = train + test
    mean = sum(train) / len(train)
    std = math.sqrt(sum((x - mean) ** 2 for x in train) / len(train))
    expected = sum((x - mean) / std for x in test)
    cases.append((data, split, expected))

with open(expected_path, 'w') as f:
    json.dump([case[2] for case in cases], f)

with open(main_path, 'w') as f:
    f.write('mod processor;\n\nfn main() {\n')
    for data, split, _ in cases:
        values = ', '.join(format(x, '.17g') for x in data)
        f.write(f'    let data: Vec<f64> = vec![{values}];\n')
        f.write(f'    println!("{{:.17}}", processor::process_data(&data, {split}));\n')
    f.write('}\n')
PY

    cargo run --quiet > /tmp/process_data_actual.txt
    python3 - << 'PY'
import json
import math

with open('/tmp/process_data_expected.json') as f:
    expected = json.load(f)
with open('/tmp/process_data_actual.txt') as f:
    lines = [line.strip() for line in f if line.strip()]

assert len(lines) == len(expected), f"Expected {len(expected)} process_data results, got {len(lines)}"
for index, (line, want) in enumerate(zip(lines, expected)):
    try:
        got = float(line)
    except ValueError as exc:
        raise AssertionError(f"Hidden case {index} did not return a valid float: {line!r}") from exc
    tolerance = 1e-8 * max(1.0, abs(want))
    assert math.isfinite(got), f"Hidden case {index} returned a non-finite value"
    assert abs(got - want) <= tolerance, f"Hidden case {index}: expected {want}, got {got}"
PY
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
