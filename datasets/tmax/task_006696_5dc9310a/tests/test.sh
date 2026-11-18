#!/bin/bash
set +e
mkdir -p /logs/verifier
export HOME=/home/user
export GOPATH=/home/user/go
export GOCACHE=/tmp/verifier-go-cache

run_verifier() {
    cd /home/user/ml_prep || return 1

    python3 - <<'PY' || return 1
import os
import re

main_path = '/home/user/ml_prep/main.go'
mod_path = '/home/user/ml_prep/go.mod'
assert os.path.isfile(main_path), f'{main_path} is missing'
assert os.path.isfile(mod_path), f'{mod_path} is missing'

with open(mod_path, encoding='utf-8') as f:
    mod = f.read()
modules = re.findall(r'^\s*module\s+(\S+)\s*$', mod, re.MULTILINE)
assert modules == ['ml_prep'], f'Go module must be named ml_prep, got {modules}'
assert 'gonum.org/v1/gonum' in mod, 'go.mod does not declare the Gonum dependency'

with open(main_path, encoding='utf-8') as f:
    source = f.read()
match = re.search(r'(?:(\w+)\s+)?"gonum\.org/v1/gonum/stat"', source)
assert match, 'main.go must import gonum.org/v1/gonum/stat'
alias = match.group(1) or 'stat'
assert alias not in ('_', '.'), 'Gonum stat must be imported as a usable package'
assert re.search(r'\b' + re.escape(alias) + r'\s*\.', source), 'main.go does not use the Gonum stat package'
PY

    go build -o /tmp/ml_prep_submission . || return 1

    cat > /tmp/shuffle_oracle.go <<'GO'
package main

import (
    "fmt"
    "math/rand"
    "os"
    "strconv"
)

func main() {
    n, err := strconv.Atoi(os.Args[1])
    if err != nil { panic(err) }
    seed, err := strconv.ParseInt(os.Args[2], 10, 64)
    if err != nil { panic(err) }
    values := make([]int, n)
    for i := range values { values[i] = i }
    r := rand.New(rand.NewSource(seed))
    r.Shuffle(len(values), func(i, j int) { values[i], values[j] = values[j], values[i] })
    for i, value := range values {
        if i != 0 { fmt.Print(",") }
        fmt.Print(value)
    }
}
GO
    go build -o /tmp/shuffle_oracle /tmp/shuffle_oracle.go || return 1

    python3 - <<'PY'
import csv
import io
import math
import os
import secrets
import subprocess

RAW = '/home/user/raw_data.csv'
TRAIN = '/home/user/ml_prep/train.csv'
VAL = '/home/user/ml_prep/val.csv'
LOG = '/home/user/discarded.log'
BINARY = '/tmp/ml_prep_submission'
HEADER = ['id', 'feature_a', 'feature_b', 'category']

with open(RAW, 'rb') as f:
    original_raw = f.read()


def parse_expected(raw_bytes):
    text = raw_bytes.decode('utf-8')
    rows = list(csv.reader(io.StringIO(text)))
    assert rows and rows[0] == HEADER, 'test input header is malformed'
    valid = []
    discarded = []
    for row in rows[1:]:
        first = row[0] if row else ''
        if len(row) != 4:
            discarded.append(first)
            continue
        try:
            int(row[0])
            fa = float(row[1])
            fb = float(row[2])
        except ValueError:
            discarded.append(first)
            continue
        valid.append((row[0], fa, fb, row[3]))

    mean_a = sum(r[1] for r in valid) / len(valid)
    mean_b = sum(r[2] for r in valid) / len(valid)
    std_a = math.sqrt(sum((r[1] - mean_a) ** 2 for r in valid) / len(valid))
    std_b = math.sqrt(sum((r[2] - mean_b) ** 2 for r in valid) / len(valid))
    standardized = [
        [row_id, f'{(fa-mean_a)/std_a:.6f}', f'{(fb-mean_b)/std_b:.6f}', category]
        for row_id, fa, fb, category in valid
    ]
    return standardized, discarded


def shuffled_indices(count, seed):
    output = subprocess.check_output(
        ['/tmp/shuffle_oracle', str(count), str(seed)], text=True, timeout=10
    ).strip()
    return [] if not output else [int(value) for value in output.split(',')]


def read_csv(path):
    assert os.path.isfile(path), f'{path} is missing'
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.reader(f))


def run_case(raw_bytes, seed):
    with open(RAW, 'wb') as f:
        f.write(raw_bytes)
    for path in (TRAIN, VAL, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        [BINARY, f'-seed={seed}'],
        cwd='/home/user/ml_prep',
        check=True,
        timeout=30,
    )

    expected_rows, expected_discarded = parse_expected(raw_bytes)
    order = shuffled_indices(len(expected_rows), seed)
    shuffled = [expected_rows[i] for i in order]
    split = (len(shuffled) + 1) // 2

    train_rows = read_csv(TRAIN)
    val_rows = read_csv(VAL)
    assert train_rows and train_rows[0] == HEADER, f'train.csv header incorrect: {train_rows[:1]}'
    assert val_rows and val_rows[0] == HEADER, f'val.csv header incorrect: {val_rows[:1]}'
    assert train_rows == [HEADER] + shuffled[:split], 'train.csv does not contain the seeded first half'
    assert val_rows == [HEADER] + shuffled[split:], 'val.csv does not contain the seeded remaining half'

    assert os.path.isfile(LOG), f'{LOG} is missing'
    with open(LOG, encoding='utf-8') as f:
        discarded = f.read().splitlines()
    assert discarded == expected_discarded, (
        f'Expected discarded ids {expected_discarded}, but got {discarded}'
    )
    return train_rows, val_rows, discarded


# Preserve the original exact assertions while also checking the actual seeded split.
train_rows, val_rows, discarded = run_case(original_raw, 42)
assert discarded == ['3', 'bad_id', '8']
assert len(train_rows) == 5, f'train.csv should have 5 lines, got {len(train_rows)}'
assert len(val_rows) == 5, f'val.csv should have 5 lines, got {len(val_rows)}'
expected_data = {
    '1': ('-0.307238', '-0.365397', 'cat1'),
    '2': ('0.076810', '-0.783001', 'cat2'),
    '4': ('1.228952', '1.235389', 'cat3'),
    '5': ('-1.459381', '0.260998', 'cat1'),
    '6': ('-0.537667', '-0.504596', 'cat3'),
    '7': ('0.460857', '-1.479002', 'cat1'),
    '9': ('1.612999', '1.722585', 'cat1'),
    '10': ('-1.075334', '-0.086999', 'cat2'),
}
seen_ids = set()
for row in train_rows[1:] + val_rows[1:]:
    assert len(row) == 4, f'Row {row} does not have exactly 4 columns'
    row_id, fa, fb, category = row
    assert row_id in expected_data, f'Unexpected id {row_id}'
    assert row_id not in seen_ids, f'Duplicate id {row_id}'
    seen_ids.add(row_id)
    assert (fa, fb, category) == expected_data[row_id]
assert seen_ids == set(expected_data), 'Not all expected valid rows were found'

# Exercise the compiled artifact on an unpredictable odd-sized input to reject
# prewritten outputs and verify schema filtering, scaling, ceil splitting, and seed use.
base = 10000 + secrets.randbelow(80000)
valid = []
for i in range(9):
    fa = (secrets.randbelow(200000) - 100000) / 137.0 + i * 0.019
    fb = (secrets.randbelow(300000) - 150000) / 173.0 - i * 0.023
    valid.append([str(base + i), f'{fa:.9f}', f'{fb:.9f}', f'group{i % 4}'])
rows = [
    HEADER,
    valid[0],
    [f'bad_{base}', '1.0', '2.0', 'bad'],
    valid[1], valid[2],
    [str(base + 100), 'not-a-float', '3.0', 'bad'],
    valid[3], valid[4], valid[5],
    [str(base + 101), '1.0', '2.0', 'bad', 'extra'],
    valid[6], valid[7], valid[8],
]
buffer = io.StringIO(newline='')
writer = csv.writer(buffer, lineterminator='\n')
writer.writerows(rows)
challenge_raw = buffer.getvalue().encode('utf-8')

try:
    run_case(challenge_raw, 17)
finally:
    # Restore the supplied dataset and the required final seed-42 artifacts.
    with open(RAW, 'wb') as f:
        f.write(original_raw)
    run_case(original_raw, 42)
PY
}

if run_verifier; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
