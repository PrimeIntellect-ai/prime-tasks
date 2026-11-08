#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import re

FOUR_DECIMALS = re.compile(r'^[+-]?\d+\.\d{4}$')

def sgn(z):
    if z > 0: return 1
    if z < 0: return -1
    return 0

def compute_expected_data():
    mesh_x = []
    mesh_T = []
    for i in range(101):
        z = (i - 50) / 50.0
        x = 5.0 + 5.0 * sgn(z) * (z ** 2)
        T = 40.0 + 50.0 * math.exp(-0.5 * (x - 5.0)**2)
        mesh_x.append(x)
        mesh_T.append(T)

    primers_path = '/home/user/primers.txt'
    if not os.path.exists(primers_path):
        return [], 0, 0, 0

    with open(primers_path, 'r') as f:
        primers = [line.strip() for line in f if line.strip()]

    expected_data = []
    for seq in primers:
        gc_count = seq.count('G') + seq.count('C')
        f_gc = gc_count / len(seq)
        Tm = 50.0 + 40.0 * f_gc

        best_i = 0
        min_diff = float('inf')
        for i in range(101):
            diff = abs(mesh_T[i] - Tm)
            if diff < min_diff - 1e-9:
                min_diff = diff
                best_i = i

        expected_data.append({
            'Sequence': seq,
            'f_GC': f_gc,
            'Tm': Tm,
            'Optimal_X': mesh_x[best_i]
        })

    if not expected_data:
        return expected_data, 0, 0, 0

    x_vals = [d['f_GC'] for d in expected_data]
    y_vals = [d['Optimal_X'] for d in expected_data]
    n = len(x_vals)
    mean_x = sum(x_vals) / n
    mean_y = sum(y_vals) / n

    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(x_vals, y_vals))
    den = sum((x - mean_x)**2 for x in x_vals)
    slope = num / den if den != 0 else 0
    intercept = mean_y - slope * mean_x
    rss = sum((y - (slope * x + intercept))**2 for x, y in zip(x_vals, y_vals))

    return expected_data, slope, intercept, rss

def test_training_data_csv():
    csv_path = '/home/user/training_data.csv'
    assert os.path.exists(csv_path), f"Expected output file {csv_path} does not exist."

    expected_data, _, _, _ = compute_expected_data()
    assert expected_data, "Could not compute expected data, missing primers.txt?"

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_data) + 1, "CSV row count mismatch."
    assert lines[0] == "Sequence,f_GC,Tm,Optimal_X", "CSV header mismatch."

    for i, expected in enumerate(expected_data):
        parts = lines[i+1].split(',')
        assert len(parts) == 4, f"Row {i+1} does not have 4 columns."
        assert parts[0] == expected['Sequence'], f"Row {i+1} Sequence mismatch."
        for column, value in zip(('f_GC', 'Tm', 'Optimal_X'), parts[1:]):
            assert FOUR_DECIMALS.fullmatch(value), \
                f"Row {i+1} {column} must be printed with exactly four decimal places."
        assert abs(float(parts[1]) - expected['f_GC']) < 1e-3, f"Row {i+1} f_GC mismatch."
        assert abs(float(parts[2]) - expected['Tm']) < 1e-3, f"Row {i+1} Tm mismatch."
        assert abs(float(parts[3]) - expected['Optimal_X']) < 1e-3, f"Row {i+1} Optimal_X mismatch."

def test_stats_log():
    log_path = '/home/user/stats.log'
    assert os.path.exists(log_path), f"Expected output file {log_path} does not exist."

    _, exp_slope, exp_intercept, exp_rss = compute_expected_data()

    with open(log_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 3, "stats.log must contain exactly 3 comma-separated values."
    for name, value in zip(('slope', 'intercept', 'RSS'), parts):
        assert FOUR_DECIMALS.fullmatch(value), \
            f"{name} must be printed with exactly four decimal places."

    act_slope, act_intercept, act_rss = map(float, parts)

    assert abs(act_slope - exp_slope) < 1e-3, f"Slope mismatch. Expected {exp_slope:.4f}, got {act_slope:.4f}"
    assert abs(act_intercept - exp_intercept) < 1e-3, f"Intercept mismatch. Expected {exp_intercept:.4f}, got {act_intercept:.4f}"
    assert abs(act_rss - exp_rss) < 1e-3, f"RSS mismatch. Expected {exp_rss:.4f}, got {act_rss:.4f}"
TEST_EOF

SOURCE=/home/user/prepare_data.c
BINARY=/tmp/prepare_data_verifier
BACKUP=$(mktemp /tmp/primers.XXXXXX)
HAVE_BACKUP=0

cleanup() {
    if [ "$HAVE_BACKUP" -eq 1 ]; then
        cp "$BACKUP" /home/user/primers.txt
    fi
    rm -f "$BACKUP" "$BINARY"
}
trap cleanup EXIT

run_tests() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
}

run_program_and_tests() {
    local before after
    before=$(sha256sum /home/user/primers.txt | awk '{print $1}') || return 1
    rm -f /home/user/training_data.csv /home/user/stats.log || return 1
    (cd /home/user && timeout 20s runuser -u user -- "$BINARY") || return 1
    after=$(sha256sum /home/user/primers.txt | awk '{print $1}') || return 1
    [ "$before" = "$after" ] || {
        echo "prepare_data.c must not modify primers.txt"
        return 1
    }
    run_tests || return 1
}

verify_all() {
    [ -f "$SOURCE" ] || {
        echo "Expected C source file $SOURCE does not exist or is not a regular file."
        return 1
    }

    gcc -std=c11 -O2 "$SOURCE" -lm -o "$BINARY" || return 1

    # Preserve the original verifier's checks against the agent-produced files.
    run_tests || return 1

    cp /home/user/primers.txt "$BACKUP" || return 1
    HAVE_BACKUP=1

    # Delete the outputs and require the compiled C artifact to recreate them.
    run_program_and_tests || return 1

    # Exercise the program on an independently generated primer set.
    python3 - << 'PY' || return 1
import random
rng = random.SystemRandom()
rows = []
for j in range(9):
    length = rng.randint(8, 32)
    gc_count = round(j * length / 8)
    chars = [rng.choice('GC') for _ in range(gc_count)]
    chars += [rng.choice('AT') for _ in range(length - gc_count)]
    rng.shuffle(chars)
    rows.append(''.join(chars))
with open('/home/user/primers.txt', 'w') as f:
    f.write('\n'.join(rows) + '\n')
PY
    run_program_and_tests || return 1

    # Restore the supplied input and leave outputs generated from it by the C program.
    cp "$BACKUP" /home/user/primers.txt || return 1
    run_program_and_tests || return 1
}

if verify_all; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
