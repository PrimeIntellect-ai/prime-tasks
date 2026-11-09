#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import subprocess
import sys

BASE = '/home/user/simulator'
PIPELINE = os.path.join(BASE, 'run_pipeline.sh')
DATA = os.path.join(BASE, 'data.txt')
RESULT = os.path.join(BASE, 'final_result.txt')


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, f'Could not load {path}'
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected_from_data(path):
    total = 0.0
    with open(path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            x_str, y_str, z_str = line.strip().split(',')
            x, y, z = float(x_str), float(y_str), float(z_str)
            total += (x ** 2 + y) / z
    return f'{total:.2f}'


def test_pipeline_runs_and_final_result_correct():
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is missing'
    assert os.path.isfile(os.path.join(BASE, 'parser.py')), 'parser.py is missing'
    assert os.path.isfile(os.path.join(BASE, 'simulator.py')), 'simulator.py is missing'

    proc = subprocess.run(
        ['bash', PIPELINE], cwd=BASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, (
        f'run_pipeline.sh failed with exit code {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )

    assert os.path.isfile(DATA), f'{DATA} is missing'
    assert os.path.isfile(RESULT), f'{RESULT} is missing. Did the pipeline complete successfully?'
    expected_result = expected_from_data(DATA)
    with open(RESULT, 'r') as f:
        actual_result = f.read().strip()
    assert actual_result == expected_result, (
        f'Incorrect final result in {RESULT}. Expected {expected_result}, '
        f'but got {actual_result}. Check both the math formula and the concurrency logic in simulator.py.'
    )


def test_parser_cycle_detection_and_general_resolution():
    parser = load_module('student_parser', os.path.join(BASE, 'parser.py'))
    assert hasattr(parser, 'resolve_alias'), 'resolve_alias function missing in parser.py'

    test_config_cycle = {'node_A': 'node_B', 'node_B': 'node_C', 'node_C': 'node_A'}
    try:
        res_cycle = parser.resolve_alias('node_A', test_config_cycle)
    except RecursionError:
        assert False, 'resolve_alias raised a RecursionError. Cycle detection is not fixed.'
    assert res_cycle == 'CYCLE_DETECTED', (
        "resolve_alias did not return 'CYCLE_DETECTED' for a cycle. "
        f'Got: {res_cycle}'
    )

    test_config_normal = {'node_X': 'node_Y', 'node_Y': 'node_Z'}
    res_normal = parser.resolve_alias('node_X', test_config_normal)
    assert res_normal == 'node_Z', (
        "resolve_alias failed to resolve a normal alias chain. "
        f"Expected 'node_Z', got: {res_normal}"
    )

    cases = [
        ('self', {'self': 'self'}, 'CYCLE_DETECTED'),
        ('tail', {'tail': 'a', 'a': 'b', 'b': 'c', 'c': 'a'}, 'CYCLE_DETECTED'),
        ('b', {'a': 'b', 'b': 'c', 'c': 'b'}, 'CYCLE_DETECTED'),
        ('start', {'start': 'p', 'p': 'q', 'q': 'terminal', 'u': 'v', 'v': 'u'}, 'terminal'),
        ('missing', {'a': 'b'}, 'missing'),
    ]
    for start, mapping, expected in cases:
        try:
            actual = parser.resolve_alias(start, mapping)
        except RecursionError:
            assert False, f'resolve_alias recursed forever for start={start!r}, mapping={mapping!r}'
        assert actual == expected, f'For {start!r} and {mapping!r}, expected {expected!r}, got {actual!r}'

    rng = random.Random(7319)
    for case_num in range(20):
        length = rng.randint(3, 30)
        names = [f'case_{case_num}_node_{i}' for i in range(length)]
        terminal = f'case_{case_num}_terminal'
        mapping = {names[i]: names[i + 1] for i in range(length - 1)}
        mapping[names[-1]] = terminal
        start_index = rng.randrange(length)
        assert parser.resolve_alias(names[start_index], mapping) == terminal

        cycle_at = rng.randrange(length)
        cyclic = dict(mapping)
        cyclic[names[-1]] = names[cycle_at]
        for start in (names[0], names[cycle_at], names[-1]):
            assert parser.resolve_alias(start, cyclic) == 'CYCLE_DETECTED'


def test_formula_on_derived_inputs():
    simulator = load_module('student_simulator', os.path.join(BASE, 'simulator.py'))
    assert hasattr(simulator, 'calculate_efficiency'), 'calculate_efficiency function missing in simulator.py'

    rng = random.Random(19427)
    inputs = [(2.0, 7.0, 3.0), (-4.0, 5.5, 2.0), (0.0, -3.0, 4.0)]
    inputs.extend(
        (rng.uniform(-20, 20), rng.uniform(-30, 30), rng.uniform(0.25, 10))
        for _ in range(40)
    )
    for x, y, z in inputs:
        expected = (x ** 2 + y) / z
        actual = simulator.calculate_efficiency(x, y, z)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f'calculate_efficiency({x}, {y}, {z}) returned {actual}; expected {expected}'
        )


def test_simulator_concurrency_under_forced_thread_interleaving():
    with open(DATA, 'rb') as f:
        original_data = f.read()

    # Every correct value is exactly 6.5, so the expected formatted total is exact.
    stress_data = b'3,4,2\n' * 403
    expected = f'{403 * 6.5:.2f}'
    runner = r'''
import runpy
import threading
import time

def trace(frame, event, arg):
    frame.f_trace_opcodes = True
    if event == 'opcode' and frame.f_code.co_filename.endswith('simulator.py'):
        time.sleep(0.00005)
    return trace

threading.settrace(trace)
runpy.run_path('/home/user/simulator/simulator.py', run_name='__main__')
'''

    try:
        with open(DATA, 'wb') as f:
            f.write(stress_data)

        # Repeated forced opcode interleaving exposes an unsynchronized read/modify/write,
        # while allowing locks, per-thread reduction, queues, and other valid fixes.
        for attempt in range(3):
            if os.path.exists(RESULT):
                os.remove(RESULT)
            proc = subprocess.run(
                [sys.executable, '-c', runner], cwd=BASE, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
            assert proc.returncode == 0, (
                f'simulator.py failed during concurrency test {attempt + 1}.\n'
                f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
            )
            assert os.path.isfile(RESULT), 'simulator.py did not create final_result.txt'
            with open(RESULT, 'r') as f:
                actual = f.read().strip()
            assert actual == expected, (
                f'Concurrent simulator run {attempt + 1} produced {actual!r}; expected {expected!r}. '
                'The shared total must be updated deterministically and without lost updates.'
            )
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)
        # Leave final_result.txt exactly as generated by the repaired full pipeline.
        subprocess.run(
            ['bash', PIPELINE], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

    expected_original = expected_from_data(DATA)
    assert os.path.isfile(RESULT), f'{RESULT} is missing after the final pipeline run'
    with open(RESULT, 'r') as f:
        actual_original = f.read().strip()
    assert actual_original == expected_original, (
        f'Final pipeline result was {actual_original!r}; expected {expected_original!r}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
