#!/bin/bash
mkdir -p /logs/verifier

PROJECT=/home/user/anomaly_cleaner
WORKDIR=$(mktemp -d)
ORIGINALS="$WORKDIR/originals"
mkdir -p "$ORIGINALS"
cp -a /home/user/train.csv "$ORIGINALS/train.csv" 2>/dev/null
cp -a /home/user/test.csv "$ORIGINALS/test.csv" 2>/dev/null

cleanup() {
    if [ -f "$ORIGINALS/train.csv" ]; then
        cp -a "$ORIGINALS/train.csv" /home/user/train.csv
    fi
    if [ -f "$ORIGINALS/test.csv" ]; then
        cp -a "$ORIGINALS/test.csv" /home/user/test.csv
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
import csv
import os
import re


def compute_median(values):
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n % 2 == 1:
        return sorted_vals[n // 2]
    return (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0


def compute_mad(values, median):
    return compute_median([abs(v - median) for v in values])


def compute_f1(y_true, y_pred):
    tp = sum(1 for yt, yp in zip(y_true, y_pred) if yt == 1 and yp == 1)
    fp = sum(1 for yt, yp in zip(y_true, y_pred) if yt == 0 and yp == 1)
    fn = sum(1 for yt, yp in zip(y_true, y_pred) if yt == 1 and yp == 0)

    precision = tp / (tp + fp) if tp + fp > 0 else 0.0
    recall = tp / (tp + fn) if tp + fn > 0 else 0.0
    if precision + recall == 0:
        return 0.0
    return 2 * precision * recall / (precision + recall)


def get_expected_results():
    train_data = []
    with open('/home/user/train.csv', newline='') as f:
        for row in csv.DictReader(f):
            train_data.append({
                'id': row['id'],
                'value': float(row['value']),
                'is_anomaly': int(row['is_anomaly']),
            })

    test_data = []
    with open('/home/user/test.csv', newline='') as f:
        for row in csv.DictReader(f):
            test_data.append({'id': row['id'], 'value': float(row['value'])})

    k_values = [1.0, 1.5, 2.0, 2.5, 3.0]
    fold_size = len(train_data) // 4
    cv_results = []
    k_f1_sums = {k: 0.0 for k in k_values}

    for fold in range(4):
        val_start = fold * fold_size
        val_end = val_start + fold_size
        val_set = train_data[val_start:val_end]
        train_set = train_data[:val_start] + train_data[val_end:]

        train_values = [d['value'] for d in train_set]
        median = compute_median(train_values)
        mad = compute_mad(train_values, median)
        y_true = [d['is_anomaly'] for d in val_set]

        for k in k_values:
            y_pred = [1 if abs(d['value'] - median) > k * mad else 0 for d in val_set]
            f1 = compute_f1(y_true, y_pred)
            cv_results.append((k, fold, f1))
            k_f1_sums[k] += f1

    best_k = None
    best_f1_avg = -1.0
    for k in k_values:
        avg_f1 = k_f1_sums[k] / 4.0
        if avg_f1 > best_f1_avg:
            best_f1_avg = avg_f1
            best_k = k
        elif avg_f1 == best_f1_avg and (best_k is None or k < best_k):
            best_k = k

    all_train_values = [d['value'] for d in train_data]
    global_median = compute_median(all_train_values)
    global_mad = compute_mad(all_train_values, global_median)
    cleaned = [
        d for d in test_data
        if abs(d['value'] - global_median) <= best_k * global_mad
    ]
    return cv_results, cleaned


def test_cv_results():
    cv_path = '/home/user/cv_results.csv'
    assert os.path.isfile(cv_path), f'File not found: {cv_path}'
    expected_cv, _ = get_expected_results()

    with open(cv_path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['k', 'fold', 'f1_score'], f'Incorrect header in cv_results.csv: {header}'
        rows = list(reader)

    assert len(rows) == len(expected_cv), \
        f'Expected {len(expected_cv)} rows in cv_results.csv, found {len(rows)}'

    parsed_rows = []
    for r in rows:
        assert len(r) == 3, f'Expected 3 columns in cv_results.csv, found {len(r)}'
        assert re.fullmatch(r'\d+\.\d{4}', r[2]), \
            f'f1_score must be formatted to 4 decimal places, found {r[2]!r}'
        parsed_rows.append((float(r[0]), int(r[1]), float(r[2])))

    expected_cv_sorted = sorted(expected_cv, key=lambda x: (x[0], x[1]))
    parsed_rows_sorted = sorted(parsed_rows, key=lambda x: (x[0], x[1]))
    for exp, act in zip(expected_cv_sorted, parsed_rows_sorted):
        assert exp[0] == act[0], f'Expected k={exp[0]}, found {act[0]}'
        assert exp[1] == act[1], f'Expected fold={exp[1]}, found {act[1]}'
        assert abs(exp[2] - act[2]) < 1e-4, \
            f'Expected f1_score={exp[2]:.4f} for k={exp[0]} fold={exp[1]}, found {act[2]}'


def test_cleaned_test():
    cleaned_path = '/home/user/cleaned_test.csv'
    assert os.path.isfile(cleaned_path), f'File not found: {cleaned_path}'
    _, expected_cleaned = get_expected_results()

    with open(cleaned_path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'value'], f'Incorrect header in cleaned_test.csv: {header}'
        rows = list(reader)

    assert len(rows) == len(expected_cleaned), \
        f'Expected {len(expected_cleaned)} rows in cleaned_test.csv, found {len(rows)}'
    for index, (actual, expected) in enumerate(zip(rows, expected_cleaned)):
        assert len(actual) == 2, \
            f'Expected 2 columns in cleaned_test.csv row {index + 2}, found {len(actual)}'
        assert actual[0] == expected['id'], \
            'The IDs in cleaned_test.csv do not match the expected non-anomalous rows.'
        try:
            actual_value = float(actual[1])
        except ValueError as exc:
            raise AssertionError(f'Invalid value in cleaned_test.csv row {index + 2}: {actual[1]!r}') from exc
        assert actual_value == expected['value'], \
            f'Expected value={expected["value"]} for id={expected["id"]}, found {actual[1]}'
TEST_EOF

build_binary() {
    [ -d "$PROJECT" ] || return 1
    [ -f "$PROJECT/Cargo.toml" ] || return 1
    [ -f "$PROJECT/src/main.rs" ] || return 1

    timeout 180s cargo build --quiet --manifest-path "$PROJECT/Cargo.toml" || return 1
    cargo metadata --no-deps --format-version 1 --manifest-path "$PROJECT/Cargo.toml" \
        > "$WORKDIR/metadata.json" || return 1

    BIN=$(python3 - "$WORKDIR/metadata.json" "$PROJECT/Cargo.toml" << 'PY_EOF'
import json
import os
import sys

with open(sys.argv[1]) as f:
    metadata = json.load(f)
manifest = os.path.realpath(sys.argv[2])
for package in metadata['packages']:
    if os.path.realpath(package['manifest_path']) == manifest:
        for target in package['targets']:
            if 'bin' in target['kind']:
                print(os.path.join(metadata['target_directory'], 'debug', target['name']))
                raise SystemExit(0)
raise SystemExit(1)
PY_EOF
) || return 1

    [ -n "$BIN" ] && [ -f "$BIN" ] && [ -x "$BIN" ] || return 1
    file "$BIN" | grep -Eq 'ELF.*executable' || return 1
}

run_and_check() {
    local before_train before_test after_train after_test
    before_train=$(sha256sum /home/user/train.csv | awk '{print $1}') || return 1
    before_test=$(sha256sum /home/user/test.csv | awk '{print $1}') || return 1
    chown root:root /home/user/train.csv /home/user/test.csv || return 1
    chmod 0444 /home/user/train.csv /home/user/test.csv || return 1
    rm -f /home/user/cv_results.csv /home/user/cleaned_test.csv

    timeout 60s runuser -u user -- sh -c 'cd "$1" && exec "$2"' sh "$PROJECT" "$BIN" || return 1

    after_train=$(sha256sum /home/user/train.csv | awk '{print $1}') || return 1
    after_test=$(sha256sum /home/user/test.csv | awk '{print $1}') || return 1
    [ "$before_train" = "$after_train" ] || return 1
    [ "$before_test" = "$after_test" ] || return 1
    python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short || return 1
}

make_alternate_inputs() {
    python3 - << 'PY_EOF'
import csv

anomalies = {4, 17, 23, 36, 49, 55, 67, 78}
with open('/home/user/train.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'value', 'is_anomaly'])
    for i in range(80):
        value = 35.0 + ((i * 11) % 23) * 0.41 + (i // 20) * 0.13
        if i in anomalies:
            value += 19.0 if i % 2 == 0 else -18.0
        writer.writerow([501 + i, f'{value:.2f}', int(i in anomalies)])

with open('/home/user/test.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'value'])
    for i in range(40):
        value = 35.5 + ((i * 7) % 19) * 0.43
        if i in {2, 14, 27, 35}:
            value += 21.0 if i % 2 == 0 else -20.0
        writer.writerow([901 + i, f'{value:.2f}'])
PY_EOF
}

verify_all() {
    build_binary || return 1

    make_alternate_inputs || return 1
    run_and_check || return 1

    cp -a "$ORIGINALS/train.csv" /home/user/train.csv || return 1
    cp -a "$ORIGINALS/test.csv" /home/user/test.csv || return 1
    run_and_check || return 1
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
