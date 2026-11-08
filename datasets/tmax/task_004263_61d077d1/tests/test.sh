#!/bin/bash
set -u
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp /home/user/features.csv "$BACKUP_DIR/features.csv"
cp /home/user/labels.csv "$BACKUP_DIR/labels.csv"
cp /home/user/test_ids.txt "$BACKUP_DIR/test_ids.txt"

restore_inputs() {
    cp "$BACKUP_DIR/features.csv" /home/user/features.csv
    cp "$BACKUP_DIR/labels.csv" /home/user/labels.csv
    cp "$BACKUP_DIR/test_ids.txt" /home/user/test_ids.txt
}
trap 'restore_inputs; rm -rf "$BACKUP_DIR"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pytest

def read_csv(path):
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        return list(reader)

def test_predictions_csv_exists():
    path = "/home/user/predictions.csv"
    assert os.path.isfile(path), f"Expected output file {path} is missing."

def test_predictions_logic_and_output():
    features_path = "/home/user/features.csv"
    labels_path = "/home/user/labels.csv"
    test_ids_path = "/home/user/test_ids.txt"

    assert os.path.isfile(features_path), f"Missing {features_path}"
    assert os.path.isfile(labels_path), f"Missing {labels_path}"
    assert os.path.isfile(test_ids_path), f"Missing {test_ids_path}"

    features = read_csv(features_path)
    labels = read_csv(labels_path)
    with open(test_ids_path, 'r') as f:
        test_ids = {int(line.strip()) for line in f if line.strip()}

    labels_dict = {int(row['user_id']): int(row['label']) for row in labels}

    data = []
    for row in features:
        uid = int(row['user_id'])
        if uid in labels_dict:
            data.append({
                'user_id': uid,
                'f1': float(row['f1']),
                'f2': float(row['f2']),
                'f3': float(row['f3']),
                'label': labels_dict[uid]
            })

    train_data = [d for d in data if d['user_id'] not in test_ids]
    test_data = [d for d in data if d['user_id'] in test_ids]

    stats = {}
    n = len(train_data)
    assert n > 1, "Not enough training data to compute sample standard deviation."

    for f in ['f1', 'f2', 'f3']:
        mean = sum(d[f] for d in train_data) / n
        variance = sum((d[f] - mean) ** 2 for d in train_data) / (n - 1)
        std = math.sqrt(variance)
        stats[f] = {'mean': mean, 'std': std}

    for d in train_data + test_data:
        for f in ['f1', 'f2', 'f3']:
            d[f'{f}_norm'] = (d[f] - stats[f]['mean']) / stats[f]['std']

    predictions = []
    for test_u in test_data:
        best_dist = float('inf')
        best_train_uid = float('inf')
        best_label = None
        for train_u in train_data:
            dist = math.sqrt(
                (test_u['f1_norm'] - train_u['f1_norm']) ** 2 +
                (test_u['f2_norm'] - train_u['f2_norm']) ** 2 +
                (test_u['f3_norm'] - train_u['f3_norm']) ** 2
            )
            if dist < best_dist or (dist == best_dist and train_u['user_id'] < best_train_uid):
                best_dist = dist
                best_train_uid = train_u['user_id']
                best_label = train_u['label']
        predictions.append((test_u['user_id'], best_label))

    predictions.sort(key=lambda x: x[0])
    expected_csv = "user_id,predicted_label\n" + "\n".join(f"{u},{l}" for u, l in predictions) + "\n"

    predictions_path = "/home/user/predictions.csv"
    with open(predictions_path, 'r') as f:
        actual_csv = f.read().strip() + "\n"

    actual_csv = actual_csv.replace('\r\n', '\n')

    assert actual_csv == expected_csv, (
        f"Predictions in {predictions_path} do not match the expected output.\n"
        f"Expected:\n{expected_csv}\nGot:\n{actual_csv}"
    )
TEST_EOF

generate_hidden_fixture() {
python3 << 'PY'
import csv
import math
import random
import secrets

rng = random.Random(secrets.randbits(128))

def stats(rows):
    out = []
    for j in range(3):
        vals = [r[j] for r in rows]
        mean = sum(vals) / len(vals)
        var = sum((v - mean) ** 2 for v in vals) / (len(vals) - 1)
        if var == 0:
            return None
        out.append(math.sqrt(var))
    return out

def nearest(test, train, scales):
    ranked = []
    for uid, point, _label in train:
        d = sum(((test[j] - point[j]) / scales[j]) ** 2 for j in range(3))
        ranked.append((d, uid))
    ranked.sort()
    return ranked[0][1], ranked[1][0] - ranked[0][0]

for _ in range(20000):
    base = rng.randrange(10000, 90000)
    ids = rng.sample(range(base, base + 5000), 11)
    points = [[rng.randint(-200, 200) for _ in range(3)] for _ in range(11)]
    labels = rng.sample(range(1000, 9000), 8)
    train = [(ids[i], points[i], labels[i]) for i in range(8)]
    tests = [(ids[i], points[i]) for i in range(8, 11)]
    train_scales = stats([p for _, p, _ in train])
    leaked_scales = stats([p for _, p, _ in train] + [p for _, p in tests])
    if train_scales is None or leaked_scales is None:
        continue
    proper = [nearest(p, train, train_scales) for _, p in tests]
    leaked = [nearest(p, train, leaked_scales) for _, p in tests]
    if any(a[0] != b[0] for a, b in zip(proper, leaked)) and all(a[1] > 1e-7 for a in proper):
        break
else:
    raise RuntimeError('Could not construct hidden normalization fixture')

feature_rows = [(uid, *point) for uid, point, _ in train]
feature_rows += [(uid, *point) for uid, point in tests]
feature_rows.append((base + 9001, 17, -23, 41))  # Feature-only user: must be dropped by join.
rng.shuffle(feature_rows)

label_rows = [(uid, label) for uid, _point, label in train]
label_rows += [(uid, rng.randrange(1000, 9000)) for uid, _point in tests]
label_rows.append((base + 9002, 7777))  # Label-only user: must be dropped by join.
rng.shuffle(label_rows)

with open('/home/user/features.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['user_id', 'f1', 'f2', 'f3'])
    w.writerows(feature_rows)
with open('/home/user/labels.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['user_id', 'label'])
    w.writerows(label_rows)
with open('/home/user/test_ids.txt', 'w') as f:
    for uid, _point in reversed(tests):
        f.write(f'{uid}\n')
PY
}

run_recommender() {
    rm -f /home/user/predictions.csv
    (cd /home/user/recommender && cargo run --quiet) || return 1
    test -f /home/user/predictions.csv || return 1
}

verify_all() {
    PROJECT=/home/user/recommender
    test -d "$PROJECT" || return 1
    test -f "$PROJECT/Cargo.toml" || return 1
    test -f "$PROJECT/src/main.rs" || return 1
    test -s "$PROJECT/src/main.rs" || return 1
    find "$PROJECT" -type f -name '*.rs' -size +0c -print -quit | grep -q . || return 1

    (cd "$PROJECT" && cargo build --quiet) || return 1

    # Execute the Rust application on the original fixtures and retain the original assertions.
    run_recommender || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Replace the fixed fixtures with an unpredictable case whose correct result is recomputed.
    # The generated case also guarantees that train-only and leaked normalization disagree.
    generate_hidden_fixture || return 1
    run_recommender || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Restore the required final inputs/output and check them once more.
    restore_inputs
    run_recommender || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
