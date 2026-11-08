#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_output_csv_exists():
    assert os.path.isfile("/home/user/output.csv"), "The file /home/user/output.csv was not created."

def test_output_csv_content():
    expected_rows = [
        "1,0,7,0.75",
        "2,1,8,0.75",
        "3,0,1,0.67",
        "4,1,2,0.67",
        "5,0,1,0.67",
        "6,1,2,0.33",
        "7,0,1,0.75",
        "8,1,2,0.75"
    ]

    with open("/home/user/output.csv", "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_rows), f"Expected {len(expected_rows)} lines in output.csv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_rows)):
        assert actual == expected, f"Mismatch at line {i+1}: expected '{expected}', got '{actual}'."

def test_c_source_exists():
    assert os.path.isfile("/home/user/organizer.c"), "The C source file /home/user/organizer.c was not found."
TEST_EOF

cat << 'HIDDEN_EOF' > /tmp/test_organizer_behavior.py
import os
import secrets
import subprocess
from fractions import Fraction

HOME = "/home/user"
MODEL = os.path.join(HOME, "model.txt")
DATASETS = os.path.join(HOME, "datasets.txt")
OUTPUT = os.path.join(HOME, "output.csv")
BINARY = os.path.join(HOME, "organizer")


def expected_rows(priors, probabilities, datasets):
    categories = {}
    tag_sets = {}
    for dataset_id, tags in datasets:
        scores = []
        for category in (0, 1):
            score = priors[category]
            for tag in tags:
                score *= probabilities.get(tag, (0.5, 0.5))[category]
            scores.append(score)
        categories[dataset_id] = 0 if scores[0] >= scores[1] else 1
        tag_sets[dataset_id] = set(tags)

    rows = []
    for dataset_id, _ in sorted(datasets):
        candidates = [
            other_id for other_id, _ in datasets
            if other_id != dataset_id and categories[other_id] == categories[dataset_id]
        ]
        if not candidates:
            similar_id = -1
            similarity = Fraction(0, 1)
        else:
            best = None
            for other_id in candidates:
                union = tag_sets[dataset_id] | tag_sets[other_id]
                intersection = tag_sets[dataset_id] & tag_sets[other_id]
                value = Fraction(len(intersection), len(union)) if union else Fraction(0, 1)
                candidate = (value, -other_id, other_id)
                if best is None or candidate > best:
                    best = candidate
            similarity, _, similar_id = best
        rows.append(f"{dataset_id},{categories[dataset_id]},{similar_id},{float(similarity):.2f}")
    return rows


def run_case(priors, probabilities, datasets):
    with open(MODEL, "w") as f:
        f.write(f"PRIOR {priors[0]} {priors[1]}\n")
        for tag, values in probabilities.items():
            f.write(f"TAG {tag} {values[0]} {values[1]}\n")

    with open(DATASETS, "w") as f:
        for dataset_id, tags in datasets:
            f.write(" ".join(map(str, [dataset_id] + tags)) + "\n")

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([BINARY], cwd=HOME, check=True, timeout=10)
    assert os.path.isfile(OUTPUT), "The compiled organizer did not create output.csv"
    with open(OUTPUT) as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = expected_rows(priors, probabilities, datasets)
    assert actual == expected, f"Behavioral test mismatch:\nexpected {expected}\nactual   {actual}"


def main():
    originals = {}
    for path in (MODEL, DATASETS, OUTPUT):
        originals[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        tag_base = 1000 + secrets.randbelow(100000)
        id_base = 100 + secrets.randbelow(100000)
        x, y, z, w, q, u, v = [tag_base + i for i in range(7)]
        ids = [id_base + n for n in (41, 7, 83, 19, 62, 3, 95, 28)]
        probabilities = {
            x: (0.9, 0.1),
            y: (0.1, 0.9),
            z: (0.8, 0.2),
            w: (0.2, 0.8),
            q: (0.1, 0.9),
        }
        datasets = [
            (ids[0], [x, z]),
            (ids[1], [x]),
            (ids[2], [u]),
            (ids[3], [u, v]),
            (ids[4], [x]),
            (ids[5], [y, w]),
            (ids[6], [y]),
            (ids[7], [q]),
        ]
        # Preserve a deliberately non-sorted input order.
        datasets = [datasets[i] for i in (2, 5, 0, 7, 3, 1, 6, 4)]
        run_case((0.5, 0.5), probabilities, datasets)

        tag_base += 200000
        id_a = id_base + 200001
        id_b = id_base + 200099
        run_case(
            (0.5, 0.5),
            {tag_base: (0.99, 0.01), tag_base + 1: (0.01, 0.99)},
            [(id_b, [tag_base + 1]), (id_a, [tag_base])],
        )
    finally:
        for path, data in originals.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)


if __name__ == "__main__":
    main()
HIDDEN_EOF

run_checks() {
    # Preserve all original assertions against the agent-produced final state.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    # Compile and execute the submitted C source, then ensure it reproduces the
    # required result rather than accepting a separately hardcoded CSV file.
    gcc /home/user/organizer.c -o /home/user/organizer -O2 || return 1
    rm -f /home/user/output.csv
    (cd /home/user && ./organizer) || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    # Exercise classification, unknown-tag defaults, ordering, tie-breaking,
    # Jaccard matching, and the no-same-category-peer case on fresh inputs.
    python3 /tmp/test_organizer_behavior.py || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
