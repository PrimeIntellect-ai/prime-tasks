#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess


def compute_expected(dataset_path):
    complete_rows = []
    missing_rows = []

    with open(dataset_path, "r") as f:
        lines = f.read().strip().split('\n')
        for line in lines[1:]:
            parts = line.strip().split()
            if not parts:
                continue
            id_val = int(parts[0])
            x1 = int(parts[1])
            x2 = int(parts[2])
            if parts[3] == '?':
                missing_rows.append((id_val, x1, x2))
            else:
                complete_rows.append((id_val, x1, x2, float(parts[3])))

    mses = {1: 0.0, 2: 0.0, 3: 0.0}
    for i, row in enumerate(complete_rows):
        id_val, x1, x2, y = row
        distances = []
        for j, other in enumerate(complete_rows):
            if i == j:
                continue
            o_id, o_x1, o_x2, o_y = other
            dist = abs(x1 - o_x1) + abs(x2 - o_x2)
            distances.append((dist, o_id, o_y))

        distances.sort(key=lambda x: (x[0], x[1]))
        for k in [1, 2, 3]:
            pred = sum(d[2] for d in distances[:k]) / k
            mses[k] += (pred - y) ** 2

    optimal_k = min([1, 2, 3], key=lambda k: (mses[k], k))

    expected_imputed = []
    for id_val, x1, x2 in missing_rows:
        distances = []
        for o_id, o_x1, o_x2, o_y in complete_rows:
            dist = abs(x1 - o_x1) + abs(x2 - o_x2)
            distances.append((dist, o_id, o_y))
        distances.sort(key=lambda x: (x[0], x[1]))
        pred = sum(d[2] for d in distances[:optimal_k]) / optimal_k
        expected_imputed.append((id_val, round(pred, 2)))

    expected_imputed.sort(key=lambda x: x[0])
    return optimal_k, expected_imputed


def validate_outputs(dataset_path):
    optimal_k, expected_imputed = compute_expected(dataset_path)

    k_path = "/home/user/optimal_k.txt"
    assert os.path.exists(k_path), f"File {k_path} was not created."
    with open(k_path, "r") as f:
        k_val = f.read().strip()
    assert k_val == str(optimal_k), (
        f"Expected optimal K to be {optimal_k}, but got '{k_val}'."
    )

    imputed_path = "/home/user/imputed.txt"
    assert os.path.exists(imputed_path), f"File {imputed_path} was not created."

    actual_imputed = []
    with open(imputed_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.split()
            assert len(parts) == 2, f"Invalid format in {imputed_path}: '{line.strip()}'"
            assert re.fullmatch(r"[+-]?\d+\.\d{2}", parts[1]), (
                f"Imputed value must have exactly 2 decimal places, got '{parts[1]}'."
            )
            actual_imputed.append((int(parts[0]), float(parts[1]), parts[1]))

    assert len(actual_imputed) == len(expected_imputed), (
        f"Expected {len(expected_imputed)} imputed values, but found {len(actual_imputed)}."
    )

    for act, exp in zip(actual_imputed, expected_imputed):
        assert act[0] == exp[0], f"Expected ID {exp[0]} in order, got {act[0]}."
        expected_str = f"{exp[1]:.2f}"
        actual_str = f"{act[1]:.2f}"
        assert actual_str == expected_str, (
            f"For ID {exp[0]}, expected imputed value {expected_str}, but got {actual_str}."
        )
        assert act[2] == expected_str, (
            f"For ID {exp[0]}, expected exact text {expected_str}, but got {act[2]}."
        )


def test_knn_imputation_results():
    dataset_path = "/home/user/dataset.txt"
    assert os.path.exists(dataset_path), f"Dataset file {dataset_path} is missing."
    validate_outputs(dataset_path)


def test_compiled_program_on_unseen_dataset():
    dataset_path = "/home/user/dataset.txt"
    with open(dataset_path, "rb") as f:
        original_dataset = f.read()

    base = secrets.randbelow(500) + 50
    dx = secrets.randbelow(101) - 50
    dy = secrets.randbelow(101) - 50
    rows = [
        (10, dx + 0, dy + 0, f"{base}.0"),
        (3,  dx + 0, dy + 4, f"{base + 8}.0"),
        (21, dx + 4, dy + 0, f"{base + 14}.0"),
        (7,  dx + 4, dy + 4, f"{base + 20}.0"),
        (15, dx + 2, dy + 2, f"{base + 9}.0"),
        (30, dx + 9, dy + 9, f"{base + 31}.0"),
        (2,  dx + 0, dy + 1, "?"),
        (19, dx + 4, dy + 1, "?"),
        (11, dx + 8, dy + 9, "?"),
    ]
    random.SystemRandom().shuffle(rows)
    generated = "ID X1 X2 Y\n" + "\n".join(
        f"{id_val} {x1} {x2} {y}" for id_val, x1, x2, y in rows
    ) + "\n"

    try:
        with open(dataset_path, "w") as f:
            f.write(generated)
        for path in ("/home/user/optimal_k.txt", "/home/user/imputed.txt"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        result = subprocess.run(
            ["/home/user/clean"], cwd="/home/user", timeout=20,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, (
            f"Compiled program failed on an unseen dataset: {result.stderr}"
        )
        validate_outputs(dataset_path)
    finally:
        with open(dataset_path, "wb") as f:
            f.write(original_dataset)
TEST_EOF

passed=0
if python3 - << 'PY'
import os, stat
p = "/home/user/clean.cpp"
st = os.lstat(p)
assert stat.S_ISREG(st.st_mode), "clean.cpp must be a regular C++ source file"
PY
then
    rm -f /home/user/clean /home/user/optimal_k.txt /home/user/imputed.txt
    if /usr/bin/g++ -O3 /home/user/clean.cpp -o /home/user/clean \
       && [ -f /home/user/clean ] && [ -x /home/user/clean ]; then
        rm -f /home/user/optimal_k.txt /home/user/imputed.txt
        if (cd /home/user && timeout 20s ./clean) \
           && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
            passed=1
        fi
    fi
fi

echo "$passed" > /logs/verifier/reward.txt
