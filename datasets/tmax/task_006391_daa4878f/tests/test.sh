#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import subprocess
import sys
import importlib.util
import pytest

PROJECT = '/home/user/metrics_analyzer'
ANALYZER_PATH = os.path.join(PROJECT, 'analyzer.py')
TEST_PATH = os.path.join(PROJECT, 'test_analyzer.py')
FINAL_PATH = '/home/user/final_diff.json'


def load_analyzer():
    assert os.path.isfile(ANALYZER_PATH), f"The file {ANALYZER_PATH} does not exist."
    spec = importlib.util.spec_from_file_location('analyzer', ANALYZER_PATH)
    analyzer = importlib.util.module_from_spec(spec)
    sys.modules['analyzer'] = analyzer
    spec.loader.exec_module(analyzer)
    return analyzer


def reference_merge(stream_a, stream_b):
    result = []
    for ta, va in stream_a:
        candidates = [(tb, vb) for tb, vb in stream_b if abs(ta - tb) < 5]
        if candidates:
            tb, vb = min(candidates, key=lambda point: (abs(ta - point[0]), point[1]))
            result.append([ta, round(abs(va - vb), 2)])
    return result


def test_final_diff_json():
    # Regenerate the artifact so a hardcoded pre-existing final_diff.json cannot pass.
    if os.path.exists(FINAL_PATH):
        os.remove(FINAL_PATH)
    completed = subprocess.run(
        [sys.executable, 'main.py'], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert completed.returncode == 0, f"python3 main.py failed:\n{completed.stdout}"
    assert os.path.isfile(FINAL_PATH), f"The file {FINAL_PATH} does not exist. Did you run main.py?"

    with open(FINAL_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{FINAL_PATH} is not valid JSON.")

    expected_data = [[1, 5.0], [8, 2.0], [15, 5.0], [20, 5.0]]
    assert data == expected_data, f"Expected {expected_data} in {FINAL_PATH}, but got {data}"


def test_test_analyzer_has_mock():
    assert os.path.isfile(TEST_PATH), f"The file {TEST_PATH} does not exist."
    with open(TEST_PATH, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert 'patch' in content, 'test_analyzer.py does not use unittest.mock.patch as required.'
    assert 'process_streams' in content, 'test_analyzer.py does not test process_streams.'

    tree = ast.parse(content, filename=TEST_PATH)
    test_functions = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test')
    ]
    assert test_functions, 'test_analyzer.py does not define a test case.'

    def is_patch_call(node):
        if not isinstance(node, ast.Call):
            return False
        name = node.func.id if isinstance(node.func, ast.Name) else (
            node.func.attr if isinstance(node.func, ast.Attribute) else None
        )
        if name != 'patch':
            return False
        target_nodes = list(node.args[:1]) + [kw.value for kw in node.keywords if kw.arg == 'target']
        return any(isinstance(value, ast.Constant) and value.value == 'analyzer.fetch_stream'
                   for value in target_nodes)

    def is_process_call(node):
        if not isinstance(node, ast.Call):
            return False
        return ((isinstance(node.func, ast.Name) and node.func.id == 'process_streams') or
                (isinstance(node.func, ast.Attribute) and node.func.attr == 'process_streams'))

    def has_assertion(node):
        if isinstance(node, ast.Assert):
            return True
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else (
                node.func.id if isinstance(node.func, ast.Name) else ''
            )
            return name.startswith('assert')
        return False

    valid_test = any(
        any(is_patch_call(n) for n in ast.walk(fn)) and
        any(is_process_call(n) for n in ast.walk(fn)) and
        any(has_assertion(n) for n in ast.walk(fn))
        for fn in test_functions
    )
    assert valid_test, (
        'A test case must actually patch analyzer.fetch_stream, call process_streams, and assert its result.'
    )

    literals = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple, ast.Dict, ast.Set, ast.Constant)):
            try:
                literals.append(ast.literal_eval(node))
            except (ValueError, TypeError):
                pass
    required_literals = [
        [(10, 100.0), (20, 150.0), (30, 200.0)],
        [(12, 105.0), (19, 140.0), (35, 210.0)],
        [[10, 5.0], [20, 10.0]],
    ]
    for required in required_literals:
        assert required in literals, f'Mock test is missing required fixture or expected value: {required}'
    assert 'A' in literals and 'B' in literals, 'Mock fixture must handle stream IDs A and B.'

    # Execute the required test command and ensure at least one unittest really ran.
    completed = subprocess.run(
        [sys.executable, '-m', 'unittest', 'test_analyzer.py'], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert completed.returncode == 0, f"Required unittest command failed:\n{completed.stdout}"
    match = re.search(r'Ran\s+(\d+)\s+tests?', completed.stdout)
    assert match and int(match.group(1)) >= 1, f"No unittest test case was executed:\n{completed.stdout}"


def test_merge_and_diff_logic():
    analyzer = load_analyzer()
    assert hasattr(analyzer, 'merge_and_diff'), 'merge_and_diff function missing in analyzer.py'

    # Preserve the original fixed assertions.
    stream_a = [(10, 100.0), (20, 150.0), (30, 200.0)]
    stream_b = [(12, 105.0), (19, 140.0), (35, 210.0)]
    res = analyzer.merge_and_diff(stream_a, stream_b)
    assert res == [[10, 5.0], [20, 10.0]], f"merge_and_diff failed on basic mock data. Got {res}"

    stream_a_tie = [(10, 100.0)]
    stream_b_tie = [(8, 110.0), (12, 105.0)]
    res_tie = analyzer.merge_and_diff(stream_a_tie, stream_b_tie)
    assert res_tie == [[10, 5.0]], f"merge_and_diff failed tie-breaking logic. Got {res_tie}"

    stream_a_out = [(10, 100.0)]
    stream_b_out = [(15, 110.0)]
    res_out = analyzer.merge_and_diff(stream_a_out, stream_b_out)
    assert res_out == [], f"merge_and_diff failed out of bounds logic (must be strictly < 5). Got {res_out}"

    # Exercise independently generated inputs, including arbitrary ordering,
    # nearest matches, ties, duplicate timestamps, unmatched points, and rounding.
    rng = random.SystemRandom()
    cases = [
        ([], [(1, 1.0)]),
        ([(5, 1.005), (5, -3.337)], []),
        ([(50, 10.111)], [(54, 20.229), (46, 9.999), (49, 30.555)]),
        ([(0, 2.675), (10, -4.444)], [(-2, 8.125), (2, 7.125), (8, 0.001), (12, -1.001)]),
    ]
    for _ in range(40):
        stream_a = [
            (rng.randint(-100, 100), rng.randint(-100000, 100000) / 1000.0)
            for _ in range(rng.randint(0, 18))
        ]
        stream_b = [
            (rng.randint(-105, 105), rng.randint(-100000, 100000) / 1000.0)
            for _ in range(rng.randint(0, 22))
        ]
        rng.shuffle(stream_a)
        rng.shuffle(stream_b)
        cases.append((stream_a, stream_b))

    for stream_a, stream_b in cases:
        expected = reference_merge(stream_a, stream_b)
        actual = analyzer.merge_and_diff(stream_a, stream_b)
        assert actual == expected, (
            f"merge_and_diff failed for stream_a={stream_a}, stream_b={stream_b}. "
            f"Expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
