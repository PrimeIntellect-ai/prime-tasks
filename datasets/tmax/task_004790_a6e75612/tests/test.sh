#!/bin/bash
set -u
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
cp -a /home/user/experiments "$BACKUP_DIR/experiments"

restore_experiments() {
    rm -rf /home/user/experiments
    cp -a "$BACKUP_DIR/experiments" /home/user/experiments
}

cleanup() {
    restore_experiments
    rm -rf "$BACKUP_DIR" /tmp/submission-go-program
}
trap cleanup EXIT

install_fixture() {
    local case_id="$1"
    rm -rf /home/user/experiments
    mkdir -p /home/user/experiments

    CASE_ID="$case_id" python3 - <<'PY'
import json
import os

case_id = os.environ["CASE_ID"]
base = "/home/user/experiments"

if case_id == "1":
    # Engineered distances: batch_candidate=sqrt(1^2+2^2), lr_candidate=4.
    # Using unscaled raw fields would incorrectly favor lr_candidate.
    records = [
        ("exp_target.json", {"id": "fixture_target", "learning_rate": 0.020, "batch_size": 64, "accuracy": 0.80}),
        ("batch_candidate.json", {"id": "batch_candidate", "learning_rate": 0.021, "batch_size": 192, "accuracy": 0.80}),
        ("lr_candidate.json", {"id": "lr_candidate", "learning_rate": 0.024, "batch_size": 64, "accuracy": 0.80}),
    ]
else:
    # Engineered distances: accuracy_candidate=0.9, lr_candidate=1.0.
    # Using unscaled raw fields would incorrectly favor lr_candidate.
    records = [
        ("exp_target.json", {"id": "second_target", "learning_rate": 0.010, "batch_size": 64, "accuracy": 0.80}),
        ("accuracy_candidate.json", {"id": "accuracy_candidate", "learning_rate": 0.010, "batch_size": 64, "accuracy": 0.89}),
        ("lr_candidate.json", {"id": "second_lr_candidate", "learning_rate": 0.011, "batch_size": 64, "accuracy": 0.80}),
    ]

for name, data in records:
    with open(os.path.join(base, name), "w") as f:
        json.dump(data, f)
PY
}

check_current_output() {
    python3 - <<'PY'
import json
import math
import os
import sys

experiments_dir = "/home/user/experiments"
target_path = os.path.join(experiments_dir, "exp_target.json")
output_path = "/home/user/most_similar_exp.txt"

if not os.path.isfile(output_path) or not os.path.isfile(target_path):
    sys.exit(1)

with open(target_path) as f:
    target = json.load(f)

def features(data):
    return (
        data.get("learning_rate", 0.0) * 1000.0,
        data.get("batch_size", 0) / 64.0,
        (data.get("accuracy", 0.0) - 0.5) * 10.0,
    )

target_features = features(target)
closest_id = None
min_dist_sq = float("inf")
for filename in os.listdir(experiments_dir):
    if not filename.endswith(".json") or filename == "exp_target.json":
        continue
    with open(os.path.join(experiments_dir, filename)) as f:
        data = json.load(f)
    dist_sq = sum((a - b) ** 2 for a, b in zip(target_features, features(data)))
    if dist_sq < min_dist_sq:
        min_dist_sq = dist_sq
        closest_id = data.get("id")

if closest_id is None:
    sys.exit(1)
with open(output_path) as f:
    actual = f.read().strip()
sys.exit(0 if actual == closest_id else 1)
PY
}

build_program() {
    local source_dir="$1"
    rm -f /tmp/submission-go-program
    if (cd "$source_dir" && GO111MODULE=on go build -o /tmp/submission-go-program .) >/tmp/go-build.log 2>&1; then
        return 0
    fi
    (cd "$source_dir" && GO111MODULE=off go build -o /tmp/submission-go-program .) >/tmp/go-build.log 2>&1
}

execute_and_check() {
    rm -f /home/user/most_similar_exp.txt
    (cd /home/user && timeout 30s /tmp/submission-go-program) >/tmp/go-run.log 2>&1 || return 1
    check_current_output
}

main() {
    mapfile -t SOURCE_DIRS < <(
        find /home/user -maxdepth 4 -type f -name '*.go' \
            ! -path '/home/user/experiments/*' \
            ! -path '/home/user/go/*' \
            ! -path '*/.cache/*' \
            -printf '%h\n' 2>/dev/null | sort -u
    )

    [ "${#SOURCE_DIRS[@]}" -gt 0 ] || return 1

    local selected=""
    local source_dir
    for source_dir in "${SOURCE_DIRS[@]}"; do
        install_fixture 1 || continue
        build_program "$source_dir" || continue
        execute_and_check || continue

        install_fixture 2 || continue
        execute_and_check || continue

        selected="$source_dir"
        break
    done

    [ -n "$selected" ] || return 1
    find "$selected" -maxdepth 1 -type f -name '*.go' -print -quit | grep -q . || return 1

    # Restore the real artifacts, execute the verified Go program on them, and
    # retain the original verifier's final-state assertion below.
    restore_experiments || return 1
    execute_and_check || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_most_similar_exp_output():
    output_path = "/home/user/most_similar_exp.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    # Recompute the expected result based on the current JSON files in the directory
    experiments_dir = "/home/user/experiments"
    target_path = os.path.join(experiments_dir, "exp_target.json")

    assert os.path.isfile(target_path), f"Target experiment file {target_path} is missing."

    with open(target_path, 'r') as f:
        target_data = json.load(f)

    def get_features(data):
        f1 = data.get("learning_rate", 0.0) * 1000.0
        f2 = data.get("batch_size", 0) / 64.0
        f3 = (data.get("accuracy", 0.0) - 0.5) * 10.0
        return f1, f2, f3

    target_features = get_features(target_data)

    closest_id = None
    min_dist_sq = float('inf')

    for filename in os.listdir(experiments_dir):
        if not filename.endswith(".json"):
            continue
        if filename == "exp_target.json":
            continue

        file_path = os.path.join(experiments_dir, filename)
        with open(file_path, 'r') as f:
            data = json.load(f)

        features = get_features(data)

        dist_sq = sum((t - f) ** 2 for t, f in zip(target_features, features))

        if dist_sq < min_dist_sq:
            min_dist_sq = dist_sq
            closest_id = data.get("id")

    # Read the actual output
    with open(output_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == closest_id, f"Expected '{closest_id}', but got '{actual_output}' in {output_path}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
}

if main; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
