#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import subprocess
import time

SOURCE = '/home/user/etl_inference.cpp'
EXECUTABLE = '/home/user/etl_inference'
LOG = '/home/user/experiment_log.json'
REBUILT = '/tmp/etl_inference_rebuilt'
execution_elapsed = None


def test_source_file_exists():
    assert os.path.isfile(SOURCE), "Source file /home/user/etl_inference.cpp does not exist."

    with open(SOURCE, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()

    # Confirm that the submitted source contains the required inference and timing machinery.
    assert 'chrono' in source, "Source must use std::chrono to time inference."
    assert re.search(r'\b(for|while)\s*\(', source), "Source must contain an inference loop."
    for token in ('1000000', '0.001', '3.5', '1.2', '0.8', '4.1'):
        assert token in source, f"Required inference constant {token} is missing from the source."


def test_executable_exists_and_is_reproducible_o3_build():
    global execution_elapsed

    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Executable {EXECUTABLE} is not an ELF binary."

    compile_result = subprocess.run(
        ['g++', '-O3', SOURCE, '-o', REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, \
        f"Source does not compile with g++ -O3:\n{compile_result.stderr}"

    def digest(path):
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                h.update(chunk)
        return h.digest()

    assert digest(EXECUTABLE) == digest(REBUILT), \
        "Submitted executable is not the reproducible g++ -O3 build of etl_inference.cpp."

    # Remove any agent-created log and require the submitted artifact to recreate it.
    if os.path.exists(LOG):
        os.remove(LOG)
    started_wall = time.time()
    started = time.perf_counter()
    result = subprocess.run(
        [EXECUTABLE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    execution_elapsed = time.perf_counter() - started
    assert result.returncode == 0, \
        f"Executable failed with code {result.returncode}:\n{result.stderr}"
    assert os.path.isfile(LOG), "Executing etl_inference did not produce experiment_log.json."
    assert os.path.getmtime(LOG) >= started_wall - 0.01, \
        "experiment_log.json was not freshly produced by the executable."


def test_experiment_log():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."

    with open(LOG, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "Log file is not valid JSON."

    assert isinstance(data, dict), "Log file must contain a JSON object."
    assert set(data) == {'language', 'batch_size', 'inference_time_sec', 'sum_scores'}, \
        f"Log has unexpected fields: {set(data)}"
    assert data.get("language") == "C++", f"Expected language to be 'C++', got {data.get('language')}"
    assert data.get("batch_size") == 1000000, f"Expected batch_size to be 1000000, got {data.get('batch_size')}"

    inference_time = data.get("inference_time_sec")
    assert isinstance(inference_time, (int, float)) and not isinstance(inference_time, bool), \
        "inference_time_sec must be a number."
    assert math.isfinite(inference_time), "inference_time_sec must be finite."
    assert inference_time > 0.0, f"inference_time_sec must be greater than 0.0, got {inference_time}"
    assert execution_elapsed is not None
    assert inference_time <= execution_elapsed + 0.1, \
        "Reported inference time cannot exceed the elapsed execution time."

    sum_scores = data.get("sum_scores")
    assert isinstance(sum_scores, (int, float)) and not isinstance(sum_scores, bool), \
        "sum_scores must be a number."
    assert math.isfinite(sum_scores), "sum_scores must be finite."

    # Calculate expected sum independently.
    expected_sum = 0.0
    for i in range(1000000):
        x = i * 0.001
        expected_sum += 3.5*(x**3) - 1.2*(x**2) + 0.8*x - 4.1

    # Check within 0.01%.
    tolerance = abs(expected_sum) * 0.0001
    assert math.isclose(sum_scores, expected_sum, abs_tol=tolerance), \
        f"sum_scores {sum_scores} is not within 0.01% of expected {expected_sum}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
