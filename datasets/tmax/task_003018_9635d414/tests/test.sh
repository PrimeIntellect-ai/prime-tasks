#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/filter_backup"


def test_filter_backup_executable_exists():
    executable = EXECUTABLE
    assert os.path.isfile(executable), f"Executable not found at {executable}"
    assert os.access(executable, os.X_OK), f"File at {executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter_backup must be a compiled native executable"


def test_adversarial_corpus():
    executable = EXECUTABLE
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.jsonl')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.jsonl')]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    evil_failed = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run([executable, filepath], capture_output=True, text=True, timeout=5)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "ACCEPT":
            clean_failed.append((filename, result.returncode, output))

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run([executable, filepath], capture_output=True, text=True, timeout=5)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "REJECT":
            evil_failed.append((filename, result.returncode, output))

    error_messages = []
    if evil_failed:
        basenames = [f[0] for f in evil_failed]
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(basenames)}")
    if clean_failed:
        basenames = [f[0] for f in clean_failed]
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(basenames)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def shuffled_object(rng, pairs):
    pairs = list(pairs)
    rng.shuffle(pairs)
    return dict(pairs)


def has_category_cycle(rows):
    parent = {
        row["cat_id"]: row["parent_id"]
        for row in rows
        if row.get("_table") == "categories"
    }
    done = set()
    for start in parent:
        if start in done:
            continue
        seen = set()
        node = start
        while node in parent and node not in done:
            if node in seen:
                return True
            seen.add(node)
            node = parent[node]
        done.update(seen)
    return False


def expected_for_objects(rows):
    schemas = {
        "categories": {"_table", "cat_id", "parent_id", "name"},
        "metrics": {"_table", "metric_id", "cat_id", "value"},
    }
    for row in rows:
        if not isinstance(row, dict):
            return False
        table = row.get("_table")
        if table not in schemas or set(row) != schemas[table]:
            return False
    return not has_category_cycle(rows)


def run_generated_case(directory, content, should_accept):
    path = os.path.join(directory, secrets.token_hex(12) + ".jsonl")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)

    result = subprocess.run(
        [EXECUTABLE, path], capture_output=True, text=True, timeout=5,
        cwd=directory,
    )
    expected_code = 0 if should_accept else 1
    expected_output = "ACCEPT\n" if should_accept else "REJECT\n"
    assert result.returncode == expected_code, (
        f"wrong exit status for generated input: expected {expected_code}, "
        f"got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout == expected_output, (
        f"wrong stdout for generated input: expected {expected_output!r}, "
        f"got {result.stdout!r}"
    )


def encode_rows(rng, rows):
    rendered = []
    for row in rows:
        if rng.randrange(2):
            rendered.append(json.dumps(row, separators=(",", ":"), ensure_ascii=False))
        else:
            rendered.append(json.dumps(row, ensure_ascii=False))
    return "\n".join(rendered) + "\n"


def test_randomized_schema_and_cycle_validation():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    with tempfile.TemporaryDirectory(prefix="verify-") as directory:
        # Fresh graph cases use randomized identifiers, row order, key order, and paths.
        for case_number in range(14):
            count = rng.randint(5, 18)
            base = rng.randint(10000, 2_000_000)
            ids = [base + 17 * i for i in range(count)]
            parents = {}

            if case_number % 2 == 0:
                # A DAG: every non-null parent precedes its child.
                for i, cat_id in enumerate(ids):
                    parents[cat_id] = None if i == 0 or rng.randrange(4) == 0 else rng.choice(ids[:i])
            else:
                # Force a randomized cycle of length 1 through 5.
                cycle_len = rng.randint(1, min(5, count))
                cycle_nodes = rng.sample(ids, cycle_len)
                for i, cat_id in enumerate(cycle_nodes):
                    parents[cat_id] = cycle_nodes[(i + 1) % cycle_len]
                for cat_id in ids:
                    if cat_id not in parents:
                        parents[cat_id] = None

            rows = []
            for cat_id in ids:
                rows.append(shuffled_object(rng, [
                    ("_table", "categories"),
                    ("cat_id", cat_id),
                    ("parent_id", parents[cat_id]),
                    ("name", "node-" + secrets.token_hex(5)),
                ]))

            if case_number % 2 == 0:
                for i in range(rng.randint(1, 5)):
                    rows.append(shuffled_object(rng, [
                        ("_table", "metrics"),
                        ("metric_id", base * 10 + i),
                        ("cat_id", rng.choice(ids)),
                        ("value", rng.random() * 1000.0),
                    ]))

            rng.shuffle(rows)
            expected = expected_for_objects(rows)
            assert expected == (case_number % 2 == 0)
            run_generated_case(directory, encode_rows(rng, rows), expected)

        # Generate strict-schema violations without relying on the installed corpus.
        seed = rng.randint(2_100_000, 4_000_000)
        valid_category = shuffled_object(rng, [
            ("_table", "categories"),
            ("cat_id", seed),
            ("parent_id", None),
            ("name", "root-" + secrets.token_hex(4)),
        ])
        valid_metric = shuffled_object(rng, [
            ("_table", "metrics"),
            ("metric_id", seed + 1),
            ("cat_id", seed),
            ("value", rng.random() * 50),
        ])

        invalid_sets = []
        for key in ("cat_id", "parent_id", "name", "_table"):
            row = dict(valid_category)
            del row[key]
            invalid_sets.append([row])
        for key in ("metric_id", "cat_id", "value", "_table"):
            row = dict(valid_metric)
            del row[key]
            invalid_sets.append([row])

        extra_category = dict(valid_category)
        extra_category["unexpected_" + secrets.token_hex(3)] = rng.randint(1, 99)
        invalid_sets.append([extra_category])
        extra_metric = dict(valid_metric)
        extra_metric["unexpected_" + secrets.token_hex(3)] = "x"
        invalid_sets.append([extra_metric])

        unknown = dict(valid_category)
        unknown["_table"] = "unknown_" + secrets.token_hex(5)
        invalid_sets.append([unknown])
        invalid_sets.append([[1, 2, 3]])

        for rows in invalid_sets:
            assert not expected_for_objects(rows)
            run_generated_case(directory, encode_rows(rng, rows), False)

        # Malformed JSON and a malformed row embedded among otherwise valid rows.
        malformed = json.dumps(valid_category)[:-1] + "\n"
        run_generated_case(directory, malformed, False)
        mixed_malformed = json.dumps(valid_category) + "\n{" + secrets.token_hex(6) + "\n" + json.dumps(valid_metric) + "\n"
        run_generated_case(directory, mixed_malformed, False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
