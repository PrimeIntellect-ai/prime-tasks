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
import tempfile

import pytest

SCRIPT_PATH = "/home/user/query_filter.py"


def run_filter(directory):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, directory],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed on {directory}: {result.stderr}"
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def test_result_json():
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"Missing {result_path}"

    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{result_path} is not a valid JSON file")

    assert data.get("secret_node_id") == "NODE_ID_8192", "Incorrect secret_node_id in result.json"
    assert data.get("filter_script_path") == SCRIPT_PATH, "Incorrect filter_script_path in result.json"


def test_query_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_query_filter_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    expected_files = {f for f in os.listdir(clean_dir) if f.endswith(".cypher")}
    output_lines = run_filter(clean_dir)

    missing_files = expected_files - output_lines
    extra_files = output_lines - expected_files
    assert not missing_files, f"{len(missing_files)} of {len(expected_files)} clean files were rejected. Missing: {missing_files}"
    assert not extra_files, f"Script output extra unexpected filenames for clean corpus: {extra_files}"


def test_query_filter_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    evil_files = {f for f in os.listdir(evil_dir) if f.endswith(".cypher")}
    output_lines = run_filter(evil_dir)

    bypassed_files = output_lines.intersection(evil_files)
    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the filter. Bypassed: {bypassed_files}"


def identifier():
    return "v" + secrets.token_hex(4)


def filename():
    alphabet = string.ascii_lowercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(14)) + ".cypher"


def test_query_filter_randomized_mixed_corpora():
    # Each runtime-created directory mixes safe and evil queries under opaque,
    # randomized names, so behavior cannot be selected from known directory names.
    for _ in range(3):
        directory = tempfile.mkdtemp(prefix="cypher_check_" + secrets.token_hex(5) + "_")
        a, b, c, d = identifier(), identifier(), identifier(), identifier()
        label1, label2 = identifier(), identifier()
        rel = identifier().upper()

        cases = [
            (f"MATCH ({a}:{label1}) RETURN {a}", True),
            (f"MATCH ({a}:{label1})-[:{rel}]->({b}:{label2}) RETURN {a}, {b}", True),
            (f"MATCH ({a})-[]-({b}) RETURN {a}, {b}", True),
            (f"MATCH ({a})\nWITH {a}\nMATCH ({a})-[:{rel}]->({b})\nRETURN {a}, {b}", True),
            (f"MATCH ({a}:{label1}), ({b}:{label2}) RETURN {a}, {b}", False),
            (f"MATCH ({a})-[:{rel}]->({b}), ({c}) RETURN {a}, {b}, {c}", False),
            (f"MATCH ({a}),\n({b})\nRETURN {a}, {b}", False),
            (f"MATCH ({a})-[]-({b}), ({c})-[:{rel}]->({d}) RETURN {a}, {b}, {c}, {d}", False),
        ]
        random.SystemRandom().shuffle(cases)

        expected = set()
        for query, safe in cases:
            name = filename()
            with open(os.path.join(directory, name), "w") as f:
                f.write(query + "\n")
            if safe:
                expected.add(name)

        # Non-Cypher files must not be reported.
        with open(os.path.join(directory, "ignore_" + secrets.token_hex(4) + ".txt"), "w") as f:
            f.write(f"MATCH ({a}), ({b}) RETURN {a}, {b}\n")

        actual = run_filter(directory)
        assert actual == expected, (
            f"Incorrect classification in randomized mixed corpus. "
            f"Missing safe files: {expected - actual}; unexpected/evil files: {actual - expected}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
