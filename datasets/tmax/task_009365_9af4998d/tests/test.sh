#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import shutil
import subprocess
import tempfile
from collections import deque

import pytest

SCRIPT = '/home/user/process.py'
DATA_DIR = '/home/user/sensor_data'
OUTPUT = '/home/user/sensor_summary.json'


def load_output():
    assert os.path.isfile(OUTPUT), f"{OUTPUT} does not exist."
    with open(OUTPUT, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT} does not contain valid JSON.")


def assert_original_content(data):
    # Preserve the original verifier's assertions.
    for sensor in ["sensor_1", "sensor_2", "sensor_3"]:
        assert sensor in data, f"Key '{sensor}' is missing from the output JSON."
        assert isinstance(data[sensor], list), f"Value for '{sensor}' should be a list."
        assert len(data[sensor]) == 3, f"Expected 3 readings for '{sensor}', got {len(data[sensor])}."

    s1 = data["sensor_1"]
    assert s1[0]["timestamp"] == 3 and s1[0]["sma"] == 22.0
    assert s1[1]["timestamp"] == 4 and s1[1]["sma"] == 24.0
    assert s1[2]["timestamp"] == 5 and s1[2]["sma"] == 26.0

    s2 = data["sensor_2"]
    assert s2[0]["timestamp"] == 3 and s2[0]["sma"] == 15.0
    assert s2[1]["timestamp"] == 4 and s2[1]["sma"] == 20.0
    assert s2[2]["timestamp"] == 5 and s2[2]["sma"] == 23.33

    s3 = data["sensor_3"]
    assert s3[0]["timestamp"] == 3 and s3[0]["sma"] == 30.0
    assert s3[1]["timestamp"] == 4 and s3[1]["sma"] == 30.0
    assert s3[2]["timestamp"] == 5 and s3[2]["sma"] == 30.0


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def dotted_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return '.'.join(reversed(parts))


def assert_parallel_api_used(tree):
    module_aliases = set()
    direct_constructors = set()
    imported_parallel = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('concurrent.futures'):
                    imported_parallel = True
                    module_aliases.add(alias.asname or alias.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            if module == 'multiprocessing' or module == 'concurrent.futures':
                imported_parallel = True
                for alias in node.names:
                    if alias.name in {'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}:
                        direct_constructors.add(alias.asname or alias.name)
            elif module == 'concurrent':
                for alias in node.names:
                    if alias.name == 'futures':
                        imported_parallel = True
                        module_aliases.add(alias.asname or alias.name)

    constructor_calls = False
    work_calls = False
    constructors = {'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}
    work_methods = {'map', 'starmap', 'imap', 'imap_unordered', 'apply', 'apply_async', 'submit', 'start'}

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = dotted_name(node.func)
        pieces = name.split('.') if name else []
        if name in direct_constructors:
            constructor_calls = True
        elif pieces and pieces[-1] in constructors and pieces[0] in module_aliases:
            constructor_calls = True
        if pieces and pieces[-1] in work_methods:
            work_calls = True

    assert imported_parallel, "process.py must import multiprocessing or concurrent.futures."
    assert constructor_calls and work_calls, (
        "process.py must actually construct a multiprocessing/concurrent.futures worker "
        "facility and dispatch work through it."
    )


def derive_expected(directory):
    expected = {}
    for filename in sorted(os.listdir(directory)):
        if not (filename.startswith('sensor_') and filename.endswith('.csv')):
            continue
        key = filename[:-4]
        rows = []
        window = deque(maxlen=3)
        with open(os.path.join(directory, filename), newline='') as f:
            for record in csv.DictReader(f):
                timestamp = int(record['timestamp'])
                window.append(float(record['temperature']))
                if len(window) == 3:
                    rows.append({'timestamp': timestamp, 'sma': round(sum(window) / 3, 2)})
        expected[key] = rows
    return expected


def write_sensor(path, readings):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'temperature'])
        writer.writerows(readings)


def test_process_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT), "The script /home/user/process.py does not exist."
    with open(SCRIPT, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"process.py is not valid Python: {exc}")
    assert_parallel_api_used(tree)


def test_existing_output_json_exists_and_has_original_content():
    assert os.path.isfile(OUTPUT), "The output file does not exist. Did you run your script?"
    assert_original_content(load_output())


def test_script_recreates_original_output():
    os.remove(OUTPUT)
    run_script()
    assert_original_content(load_output())


def test_script_processes_unseen_inputs():
    parent = tempfile.mkdtemp(prefix='sensor-verifier-', dir='/home/user')
    saved_data = os.path.join(parent, 'original_sensor_data')
    saved_output = os.path.join(parent, 'original_summary.json')

    shutil.move(DATA_DIR, saved_data)
    if os.path.exists(OUTPUT):
        shutil.copy2(OUTPUT, saved_output)
    os.mkdir(DATA_DIR)

    try:
        write_sensor(os.path.join(DATA_DIR, 'sensor_17.csv'), [
            (101, 1.25), (108, 8.75), (150, -2.0), (151, 10.1),
            (900, 3.33), (1200, 7.77),
        ])
        write_sensor(os.path.join(DATA_DIR, 'sensor_204.csv'), [
            (4, 99.0), (40, -99.0),
        ])
        write_sensor(os.path.join(DATA_DIR, 'sensor_9.csv'), [
            (2, -5.5), (5, -4.25), (11, 0.0), (19, 2.5), (28, 10.0),
        ])
        write_sensor(os.path.join(DATA_DIR, 'sensor_731.csv'), [
            (5000 + i * 7, ((i * 37) % 113 - 56) / 7.0) for i in range(257)
        ])

        expected = derive_expected(DATA_DIR)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_script()
        actual = load_output()
        assert actual == expected, "Output does not match rolling SMAs derived from unseen CSV inputs."
    finally:
        shutil.rmtree(DATA_DIR, ignore_errors=True)
        shutil.move(saved_data, DATA_DIR)
        if os.path.exists(saved_output):
            shutil.copy2(saved_output, OUTPUT)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        shutil.rmtree(parent, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
