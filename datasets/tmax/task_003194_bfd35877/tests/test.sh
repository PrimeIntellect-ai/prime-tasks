#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import string
import subprocess
import pytest

EXECUTABLE = "/home/user/query_filter"


def run_filter(payload):
    result = subprocess.run(
        [EXECUTABLE],
        input=payload,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.returncode, result.stdout.strip()


def test_query_filter_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        file_path = os.path.join(clean_dir, cf)
        with open(file_path, 'r') as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True, text=True, timeout=5)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_failed.append(cf)

    evil_bypassed = []
    for ef in evil_files:
        file_path = os.path.join(evil_dir, ef)
        with open(file_path, 'r') as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True, text=True, timeout=5)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(ef)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ("$where", "$lookup"):
                return True
            if key == "$group" and isinstance(child, dict) and child.get("_id") == "$user_email":
                return True
            if oracle(child):
                return True
    elif isinstance(value, list):
        return any(oracle(child) for child in value)
    return False


def random_name(rng):
    return "k_" + ''.join(rng.choice(string.ascii_letters) for _ in range(12))


def clean_tree(rng, depth=0):
    if depth >= 4 or rng.random() < 0.28:
        return rng.choice([
            None, True, False, rng.randint(-100000, 100000),
            random_name(rng), "$where", "$lookup", "$user_email"
        ])
    if rng.random() < 0.45:
        return [clean_tree(rng, depth + 1) for _ in range(rng.randint(0, 4))]
    return {
        random_name(rng): clean_tree(rng, depth + 1)
        for _ in range(rng.randint(1, 4))
    }


def wrap(rng, value):
    for _ in range(rng.randint(1, 5)):
        choice = rng.randrange(3)
        if choice == 0:
            value = {random_name(rng): value, random_name(rng): clean_tree(rng, 3)}
        elif choice == 1:
            value = [clean_tree(rng, 3), value, clean_tree(rng, 3)]
        else:
            value = {random_name(rng): [clean_tree(rng, 3), value]}
    return value


def encode(rng, value):
    style = rng.randrange(4)
    if style == 0:
        return json.dumps(value, separators=(",", ":"), sort_keys=bool(rng.randrange(2)))
    if style == 1:
        return json.dumps(value, indent=rng.choice([1, 2, 4]), sort_keys=bool(rng.randrange(2)))
    if style == 2:
        return "\n\t" + json.dumps(value, separators=(", ", " : ")) + "\n"
    return json.dumps(value)


def test_generated_recursive_queries():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = []

    # Novel recursive clean documents, including operator names as values and
    # near-miss keys that substring-based filters must not reject.
    for _ in range(18):
        cases.append(clean_tree(rng))

    for _ in range(8):
        cases.append(wrap(rng, {
            "$where_suffix_" + random_name(rng): "harmless",
            "$lookup_backup_" + random_name(rng): {"text": "$lookup"},
            "note": "$where",
            "ordinary_id": "$user_email"
        }))

    for _ in range(8):
        cases.append(wrap(rng, {
            "$group": {
                "_id": rng.choice(["user_email", "$other_" + random_name(rng)]),
                "mentioned": "$user_email"
            },
            "separate": {"_id": "$user_email"}
        }))

    for _ in range(8):
        cases.append(wrap(rng, {
            "$group": {"_id": {"path": "$user_email"}, "count": {"$sum": 1}},
            "description": "$where and $lookup"
        }))

    # Freshly generated violations at varying nesting depths and JSON layouts.
    for _ in range(12):
        cases.append(wrap(rng, {"$where": random_name(rng)}))
    for _ in range(12):
        cases.append(wrap(rng, {"$lookup": {
            "from": random_name(rng), "as": random_name(rng)
        }}))
    for _ in range(12):
        cases.append(wrap(rng, {"$group": {
            "_id": "$user_email", random_name(rng): {"$sum": rng.randint(1, 9)}
        }}))

    rng.shuffle(cases)
    for index, value in enumerate(cases):
        expected_evil = oracle(value)
        payload = encode(rng, value)
        returncode, output = run_filter(payload)
        expected_code = 1 if expected_evil else 0
        expected_output = "EVIL" if expected_evil else "CLEAN"
        assert returncode == expected_code and output == expected_output, (
            f"Generated case {index} misclassified; expected {expected_output} "
            f"with exit {expected_code}, got {output!r} with exit {returncode}. "
            f"Payload: {payload!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
