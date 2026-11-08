#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
from collections import Counter

import pytest

SOURCE_PATH = '/home/user/analyze.c'
RESULTS_PATH = '/home/user/results.json'
DATASET_PATH = '/home/user/dataset/edges.txt'
VERIFY_BINARY = '/tmp/analyze_verifier'


def run_analyzer():
    proc = subprocess.run(
        [VERIFY_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"Analyzer exited with status {proc.returncode}: {proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        pytest.fail(f"Analyzer stdout is not valid JSON: {e}; stdout={proc.stdout!r}")


def expected_for_edges(edges):
    concepts = set()
    degrees = Counter()
    for source, target in edges:
        concepts.add(source)
        concepts.add(target)
        degrees[source] += 1
    filtered = [(name, degrees[name]) for name in concepts if degrees[name] >= 2]
    filtered.sort(key=lambda item: (-item[1], item[0]))
    return [
        {'concept': name, 'out_degree': degree}
        for name, degree in filtered[3:6]
    ]


@pytest.fixture(scope='session', autouse=True)
def compiled_analyzer():
    assert os.path.isfile(SOURCE_PATH), "The C source file /home/user/analyze.c is missing."
    compile_proc = subprocess.run(
        ['gcc', '-O2', SOURCE_PATH, '-o', VERIFY_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_proc.returncode == 0, f"Failed to compile analyze.c: {compile_proc.stderr}"
    assert os.path.isfile(VERIFY_BINARY) and os.access(VERIFY_BINARY, os.X_OK)

    with open(DATASET_PATH, 'rb') as f:
        original_dataset = f.read()
    try:
        yield
    finally:
        with open(DATASET_PATH, 'wb') as f:
            f.write(original_dataset)


def test_c_source_exists():
    assert os.path.isfile('/home/user/analyze.c'), "The C source file /home/user/analyze.c is missing."


def test_results_json_exists():
    assert os.path.isfile('/home/user/results.json'), "The results file /home/user/results.json is missing."


def test_results_json_content():
    results_path = '/home/user/results.json'

    try:
        with open(results_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file /home/user/results.json does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read /home/user/results.json: {e}")

    expected_data = [
        {"concept": "DataScience", "out_degree": 2},
        {"concept": "NeuralNetworks", "out_degree": 2},
        {"concept": "Statistics", "out_degree": 2}
    ]

    assert isinstance(data, list), "The JSON output should be a list of objects."
    assert len(data) == 3, f"Expected 3 items in the JSON array, but found {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert isinstance(actual_item, dict), f"Item at index {i} is not a JSON object."
        assert actual_item.get("concept") == expected_item["concept"], f"Expected concept '{expected_item['concept']}' at index {i}, got '{actual_item.get('concept')}'."
        assert actual_item.get("out_degree") == expected_item["out_degree"], f"Expected out_degree {expected_item['out_degree']} for concept '{expected_item['concept']}', got {actual_item.get('out_degree')}."


def test_program_generates_submitted_results():
    generated = run_analyzer()
    with open(RESULTS_PATH, 'r') as f:
        submitted = json.load(f)
    assert generated == submitted, "results.json does not match the compiled C program's output."


def test_program_computes_randomized_datasets():
    for _ in range(2):
        tag = secrets.token_hex(6)
        sources = [f'Concept_{tag}_{secrets.token_hex(3)}' for _ in range(9)]
        degree_plan = [7, 6, 5, 4, 4, 3, 2, 2, 1]
        edges = []
        for source, degree in zip(sources, degree_plan):
            for n in range(degree):
                edges.append((source, f'Target_{tag}_{secrets.token_hex(4)}_{n}'))
        random.SystemRandom().shuffle(edges)

        with open(DATASET_PATH, 'w') as f:
            for source, target in edges:
                f.write(f'{source} {target}\n')

        expected = expected_for_edges(edges)
        actual = run_analyzer()
        assert isinstance(actual, list), "Analyzer output must be a JSON array."
        assert actual == expected, f"Incorrect output for a generated edge list: expected {expected}, got {actual}"
        for item in actual:
            assert isinstance(item, dict)
            assert set(item.keys()) == {'concept', 'out_degree'}
            assert isinstance(item['concept'], str)
            assert isinstance(item['out_degree'], int) and not isinstance(item['out_degree'], bool)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
