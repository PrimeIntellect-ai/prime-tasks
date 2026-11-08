#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import secrets
import subprocess
import pytest

TARGET_FILE = "/home/user/target_vector.txt"
MATCH_FILE = "/home/user/best_match.txt"
CSV_FILE = "/home/user/past_experiments.csv"
GENERATOR = "/home/user/generate_vector.py"


def test_target_vector_file():
    assert os.path.isfile(TARGET_FILE), f"Expected file {TARGET_FILE} does not exist."

    with open(TARGET_FILE, "r") as f:
        content = f.read().strip()

    assert content, f"File {TARGET_FILE} is empty."

    parts = content.split(",")
    assert len(parts) == 5, f"Expected 5 comma-separated values in {TARGET_FILE}, found {len(parts)}."

    try:
        vector = [float(x) for x in parts]
    except ValueError:
        pytest.fail(f"Could not parse values in {TARGET_FILE} as floats.")

    expected_vector = [0.26202468, 0.15868397, 0.27812652, 0.45931689, 0.32100054]

    for act, exp in zip(vector, expected_vector):
        assert abs(act - exp) < 1e-4, f"Vector value {act} does not match expected {exp} within tolerance."

    env = os.environ.copy()
    env.update({
        "OMP_NUM_THREADS": "1",
        "OPENBLAS_NUM_THREADS": "1",
        "NP_SEED": "1337",
    })
    result = subprocess.run(
        ["python3", GENERATOR], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"generate_vector.py failed: {result.stderr}"
    assert content == result.stdout.strip(), (
        f"{TARGET_FILE} is not the standard output produced by generate_vector.py "
        "with the required environment."
    )


def test_best_match_file():
    assert os.path.isfile(MATCH_FILE), f"Expected file {MATCH_FILE} does not exist."

    with open(MATCH_FILE, "r") as f:
        content = f.read().strip()

    assert content == "exp_beta", f"Expected 'exp_beta' in {MATCH_FILE}, but found '{content}'."


def _cosine(a, b):
    return sum(x * y for x, y in zip(a, b)) / (
        math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
    )


def _restore(path, data):
    with open(path, "wb") as f:
        f.write(data)


def _exercise(script):
    rng = secrets.SystemRandom()
    for _ in range(3):
        target = [rng.uniform(0.2, 1.5) for _ in range(5)]
        orthogonal = [-target[1], target[0], 0.0, 0.0, 0.0]

        rows = [
            ("best_" + secrets.token_hex(8), [20.0 * x for x in target]),
            ("near_" + secrets.token_hex(8), [x + 0.01 * y for x, y in zip(target, orthogonal)]),
            ("dot_" + secrets.token_hex(8), [100.0 * (x + 0.5 * y) for x, y in zip(target, orthogonal)]),
            ("other_" + secrets.token_hex(8), list(reversed(target))),
        ]
        rng.shuffle(rows)
        expected = max(rows, key=lambda row: _cosine(target, row[1]))[0]

        with open(TARGET_FILE, "w") as f:
            f.write(",".join(format(x, ".17g") for x in target))
        with open(CSV_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["exp_id", "v1", "v2", "v3", "v4", "v5"])
            for exp_id, vector in rows:
                writer.writerow([exp_id] + [format(x, ".17g") for x in vector])
        if os.path.exists(MATCH_FILE):
            os.remove(MATCH_FILE)

        result = subprocess.run(
            ["python3", script], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        if result.returncode != 0 or not os.path.isfile(MATCH_FILE):
            return False
        with open(MATCH_FILE, "r") as f:
            if f.read().strip() != expected:
                return False
    return True


def test_search_script_implements_cosine_similarity():
    candidates = [
        p for p in glob.glob("/home/user/**/*.py", recursive=True)
        if os.path.abspath(p) != os.path.abspath(GENERATOR)
    ]
    candidates.sort(key=lambda p: (os.path.basename(p) != "search.py", p))
    assert candidates, "No Python similarity-search script was found under /home/user."

    originals = {}
    for path in (TARGET_FILE, CSV_FILE, MATCH_FILE):
        originals[path] = open(path, "rb").read() if os.path.exists(path) else None

    working = None
    try:
        for script in candidates:
            _restore(TARGET_FILE, originals[TARGET_FILE])
            _restore(CSV_FILE, originals[CSV_FILE])
            if originals[MATCH_FILE] is None:
                if os.path.exists(MATCH_FILE):
                    os.remove(MATCH_FILE)
            else:
                _restore(MATCH_FILE, originals[MATCH_FILE])
            try:
                if _exercise(script):
                    working = script
                    break
            except (OSError, subprocess.SubprocessError, ValueError, ZeroDivisionError):
                continue
    finally:
        for path, data in originals.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                _restore(path, data)

    assert working is not None, (
        "No submitted Python script correctly recomputed the highest cosine-similarity "
        "experiment on independently generated inputs."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
