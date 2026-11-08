#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import sys
import tempfile
import importlib.util
import pytest


def test_vendored_filter_valid_is_repaired():
    cleaner_path = '/app/data_purify/data_purify/cleaner.py'
    assert os.path.isfile(cleaner_path), f"Vendored cleaner not found at {cleaner_path}"

    spec = importlib.util.spec_from_file_location('vendored_data_purify_cleaner', cleaner_path)
    assert spec is not None and spec.loader is not None
    cleaner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cleaner)

    records = [
        {"x": 1.0, "y": 2.0, "category": "A"},
        {"x": 3.0, "y": 4.0, "category": "unknown"},
        {"x": 5.0, "y": 6.0, "category": "B"},
        {"x": 7.0, "y": 8.0},
    ]
    before = [dict(r) for r in records]
    result = cleaner.filter_valid(records)

    assert result == [records[0], records[2], records[3]]
    assert records == before, "filter_valid must not blank or mutate the input dataset"


def test_fixed_package_is_installed_and_functional():
    code = r'''
import importlib.metadata
from data_purify.cleaner import filter_valid

assert importlib.metadata.version("data_purify") == "0.1.0"
records = [
    {"x": 1.0, "y": 2.0, "category": "unknown"},
    {"x": 3.0, "y": 4.0, "category": "A"},
    {"x": 5.0, "y": 6.0, "category": "B"},
]
assert filter_valid(records) == records[1:]
'''
    env = os.environ.copy()
    env.pop('PYTHONPATH', None)
    proc = subprocess.run(
        [sys.executable, '-c', code],
        cwd='/tmp',
        env=env,
        text=True,
        capture_output=True,
    )
    assert proc.returncode == 0, f"Installed data_purify check failed: {proc.stderr}"


def test_process_uses_filter_valid_result():
    agent_path = '/home/user/process.py'
    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"

    with tempfile.TemporaryDirectory() as shim_dir:
        marker = os.path.join(shim_dir, 'filter_called')
        sitecustomize = os.path.join(shim_dir, 'sitecustomize.py')
        with open(sitecustomize, 'w', encoding='utf-8') as f:
            f.write(r'''
import os
import data_purify.cleaner

def instrumented_filter_valid(records):
    with open(os.environ["FILTER_VALID_MARKER"], "w", encoding="utf-8") as marker_file:
        marker_file.write("called")
    return [
        {"x": 0.0, "y": 1.0, "category": "A"},
        {"x": 1.0, "y": 3.0, "category": "B"},
    ]

data_purify.cleaner.filter_valid = instrumented_filter_valid
''')

        env = os.environ.copy()
        env['FILTER_VALID_MARKER'] = marker
        old_pythonpath = env.get('PYTHONPATH')
        env['PYTHONPATH'] = shim_dir if not old_pythonpath else shim_dir + os.pathsep + old_pythonpath

        direct_input = [
            {"x": 0.0, "y": 0.0, "category": "A"},
            {"x": 1.0, "y": 0.0, "category": "B"},
        ]
        proc = subprocess.run(
            [sys.executable, agent_path],
            input=json.dumps(direct_input),
            env=env,
            text=True,
            capture_output=True,
        )

        assert proc.returncode == 0, f"Agent script failed under filter instrumentation: {proc.stderr}"
        assert os.path.isfile(marker), "process.py did not call data_purify.cleaner.filter_valid"
        assert proc.stdout == '201.0000\n', (
            "process.py did not compute from the dataset returned by filter_valid; "
            f"got stdout {proc.stdout!r}"
        )


def test_fuzz_equivalence():
    oracle_path = '/verifier/oracle.py'
    agent_path = '/home/user/process.py'

    assert os.path.isfile(oracle_path), f"Oracle script not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"

    random.seed(42)

    # Generate 100 random inputs
    inputs = []

    # Add some edge cases explicitly
    # 1. Empty array
    inputs.append([])

    # 2. All unknown
    inputs.append([{"x": 1.0, "y": 2.0, "category": "unknown"}, {"x": 3.0, "y": 4.0, "category": "unknown"}])

    # 3. Only 1 valid
    inputs.append([{"x": 1.0, "y": 2.0, "category": "A"}, {"x": 3.0, "y": 4.0, "category": "unknown"}])

    # 4. Perfectly collinear
    inputs.append([{"x": 1.0, "y": 2.0, "category": "A"}, {"x": 2.0, "y": 4.0, "category": "B"}, {"x": 3.0, "y": 6.0, "category": "A"}])

    # 5. Zero variance in x
    inputs.append([{"x": 1.0, "y": 2.0, "category": "A"}, {"x": 1.0, "y": 4.0, "category": "B"}, {"x": 1.0, "y": 6.0, "category": "A"}])

    # 6. Zero variance in y
    inputs.append([{"x": 1.0, "y": 2.0, "category": "A"}, {"x": 2.0, "y": 2.0, "category": "B"}, {"x": 3.0, "y": 2.0, "category": "A"}])

    # Fill the rest with random data
    while len(inputs) < 100:
        length = random.randint(0, 50)
        arr = []
        for _ in range(length):
            arr.append({
                "x": random.uniform(-100, 100),
                "y": random.uniform(-100, 100),
                "category": random.choice(["A", "B", "unknown"])
            })
        inputs.append(arr)

    for i, inp in enumerate(inputs):
        inp_str = json.dumps(inp)

        # Run oracle
        oracle_proc = subprocess.run(
            ['python3', oracle_path],
            input=inp_str,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ['python3', agent_path],
            input=inp_str,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input {i}: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input {i}.\n"
            f"Input: {inp_str}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
