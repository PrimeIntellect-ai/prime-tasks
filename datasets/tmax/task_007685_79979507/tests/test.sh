#!/bin/bash
set -u
mkdir -p /logs/verifier
status=0
project=/home/user/etl_pipeline
raw=/home/user/data/raw_sensors.csv
output=/home/user/data/clean_sensors.jsonl
summary=/home/user/logs/experiment.json

# Verify that a real Cargo project exists, declares ndarray, and uses ndarray's dot operation.
python3 - <<'PY' || status=1
import json
import pathlib
import re
import subprocess

project = pathlib.Path('/home/user/etl_pipeline')
manifest = project / 'Cargo.toml'
main = project / 'src' / 'main.rs'
assert manifest.is_file(), 'Cargo.toml is missing'
assert main.is_file(), 'src/main.rs is missing'

result = subprocess.run(
    ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(manifest)],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
)
assert result.returncode == 0, f'Invalid Cargo project: {result.stderr}'
metadata = json.loads(result.stdout)
packages = [p for p in metadata['packages'] if pathlib.Path(p['manifest_path']).resolve() == manifest.resolve()]
assert packages, 'Cargo metadata does not contain the ETL package'
assert any(d['name'] == 'ndarray' for d in packages[0].get('dependencies', [])), 'ndarray is not a Cargo dependency'

source = '\n'.join(p.read_text(errors='replace') for p in project.rglob('*.rs'))
assert re.search(r'\bndarray\b', source), 'Rust source does not reference ndarray'
assert re.search(r'\.dot\s*\(', source), 'Rust source does not use a dot product operation'
PY

# Compile the submitted project.
if ! cargo build --quiet --manifest-path "$project/Cargo.toml"; then
    status=1
fi

# Recreate the original fixture, execute the submitted Rust artifact, and retain all
# assertions from the original verifier.
cat > "$raw" <<'EOF'
timestamp,sensor_a,sensor_b,sensor_c
1600000000,10.0,20.0,50.0
1600000001,,22.0,150.0
1600000002,12.0,,40.0
1600000003,15.0,25.0,200.0
1600000004,11.0,21.0,90.0
EOF
rm -f "$output" "$summary"
if ! (cd "$project" && cargo run --quiet); then
    status=1
fi

python3 - <<'PY' || status=1
import json
import math
import os

log_path = '/home/user/logs/experiment.json'
assert os.path.isfile(log_path), f'File {log_path} is missing.'
with open(log_path) as f:
    data = json.load(f)
expected = {'total_rows': 5, 'outliers_capped': 2, 'missing_filled': 2}
for key in expected:
    assert key in data, f"Missing key '{key}' in experiment.json"
    assert data[key] == expected[key], f'Expected {key} to be {expected[key]}, got {data[key]}'

output_path = '/home/user/data/clean_sensors.jsonl'
assert os.path.isfile(output_path), f'File {output_path} is missing.'
expected_lines = [
    {'timestamp': 1600000000, 'sensor_proj': 21.0, 'sensor_c': 50.0},
    {'timestamp': 1600000001, 'sensor_proj': 17.6, 'sensor_c': 100.0},
    {'timestamp': 1600000002, 'sensor_proj': 6.0, 'sensor_c': 40.0},
    {'timestamp': 1600000003, 'sensor_proj': 27.5, 'sensor_c': 100.0},
    {'timestamp': 1600000004, 'sensor_proj': 22.3, 'sensor_c': 90.0},
]
parsed = []
with open(output_path) as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        if line:
            parsed.append(json.loads(line))
assert len(parsed) == len(expected_lines), f'Expected {len(expected_lines)} lines, got {len(parsed)}'
for i, (actual, expected) in enumerate(zip(parsed, expected_lines), 1):
    for key in ('timestamp', 'sensor_proj', 'sensor_c'):
        assert key in actual, f"Line {i} missing '{key}' key."
    assert actual['timestamp'] == expected['timestamp'], f'Line {i} timestamp mismatch.'
    assert math.isclose(actual['sensor_proj'], expected['sensor_proj'], rel_tol=1e-5), f'Line {i} sensor_proj mismatch.'
    assert math.isclose(actual['sensor_c'], expected['sensor_c'], rel_tol=1e-5), f'Line {i} sensor_c mismatch.'
PY

# Generate a fresh, unpredictable valid fixture so hardcoded output files cannot pass.
python3 - <<'PY' || status=1
import csv
import secrets

rng = secrets.SystemRandom()
base = rng.randrange(1700000000, 1900000000)
def val():
    return f'{rng.randrange(-400, 800) / 10:.1f}'
rows = [
    [base,     val(), val(), f'{rng.randrange(0, 1000) / 10:.1f}'],
    [base + 1, '',    val(), f'{rng.randrange(1001, 1800) / 10:.1f}'],
    [base + 2, val(), '',    '100.0'],
    [base + 3, '',    '',    f'{rng.randrange(1801, 3000) / 10:.1f}'],
    [base + 4, val(), val(), f'{rng.randrange(-500, 0) / 10:.1f}'],
    [base + 5, val(), val(), f'{rng.randrange(1001, 2500) / 10:.1f}'],
    [base + 6, val(), val(), f'{rng.randrange(0, 1000) / 10:.1f}'],
]
with open('/home/user/data/raw_sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_a', 'sensor_b', 'sensor_c'])
    writer.writerows(rows)
PY

rm -f "$output" "$summary"
if ! (cd "$project" && cargo run --quiet); then
    status=1
fi

# Derive expected results from the new input and validate exact schemas and metrics.
python3 - <<'PY' || status=1
import csv
import json
import math
import os

raw = '/home/user/data/raw_sensors.csv'
out = '/home/user/data/clean_sensors.jsonl'
summary_path = '/home/user/logs/experiment.json'
assert os.path.isfile(out), f'File {out} is missing after execution'
assert os.path.isfile(summary_path), f'File {summary_path} is missing after execution'

expected = []
missing = 0
capped = 0
with open(raw, newline='') as f:
    for row in csv.DictReader(f):
        if row['sensor_a'] == '':
            a = 0.0
            missing += 1
        else:
            a = float(row['sensor_a'])
        if row['sensor_b'] == '':
            b = 0.0
            missing += 1
        else:
            b = float(row['sensor_b'])
        c = float(row['sensor_c'])
        if c > 100.0:
            c = 100.0
            capped += 1
        expected.append({'timestamp': int(row['timestamp']), 'sensor_proj': a * 0.5 + b * 0.8, 'sensor_c': c})

with open(summary_path) as f:
    summary = json.load(f)
assert set(summary) == {'total_rows', 'outliers_capped', 'missing_filled'}, 'experiment.json must contain exactly the required keys'
assert type(summary['total_rows']) is int and summary['total_rows'] == len(expected)
assert type(summary['outliers_capped']) is int and summary['outliers_capped'] == capped
assert type(summary['missing_filled']) is int and summary['missing_filled'] == missing

actual = []
with open(out) as f:
    for number, line in enumerate(f, 1):
        line = line.strip()
        if line:
            value = json.loads(line)
            assert set(value) == {'timestamp', 'sensor_proj', 'sensor_c'}, f'Line {number} must contain exactly the required keys'
            actual.append(value)
assert len(actual) == len(expected), f'Expected {len(expected)} output rows, got {len(actual)}'
for number, (got, want) in enumerate(zip(actual, expected), 1):
    assert type(got['timestamp']) is int and got['timestamp'] == want['timestamp'], f'Line {number} timestamp mismatch'
    assert isinstance(got['sensor_proj'], (int, float)) and not isinstance(got['sensor_proj'], bool)
    assert isinstance(got['sensor_c'], (int, float)) and not isinstance(got['sensor_c'], bool)
    assert math.isclose(got['sensor_proj'], want['sensor_proj'], rel_tol=1e-9, abs_tol=1e-9), f'Line {number} sensor_proj mismatch'
    assert math.isclose(got['sensor_c'], want['sensor_c'], rel_tol=1e-9, abs_tol=1e-9), f'Line {number} sensor_c mismatch'
PY

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
