#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import json
import os
from pathlib import Path
import subprocess
import sys
import textwrap

import pytest

PROJECT = Path('/home/user/release_prep/fast_dsp')
PIPELINE = Path('/home/user/run_pipeline.py')
OUTPUT = Path('/home/user/final_output.json')


@pytest.fixture(scope='session', autouse=True)
def build_and_install_extension():
    for path in (PROJECT / 'setup.py', PROJECT / 'Makefile', PROJECT / 'src/processor.c'):
        assert path.is_file(), f'Required project file is missing: {path}'

    make_result = subprocess.run(
        ['make', '-C', str(PROJECT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert make_result.returncode == 0, f'Makefile build failed:\n{make_result.stdout}'

    pip_result = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '-e', '.'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert pip_result.returncode == 0, f'pip install -e . failed:\n{pip_result.stdout}'

    probe = subprocess.run(
        [sys.executable, '-c', textwrap.dedent('''
            import fast_dsp
            import importlib.machinery
            origin = getattr(fast_dsp, '__file__', '') or ''
            assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), origin
            assert callable(fast_dsp.sort_and_merge)
        ''')],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert probe.returncode == 0, f'fast_dsp is not an importable native extension:\n{probe.stdout}'


def test_extension_correctness_memory_safety_and_performance():
    # The expected values are derived at verification time, rather than copied
    # from the transmission's fixed answer.
    program = textwrap.dedent('''
        import random
        import fast_dsp

        cases = [
            [],
            [9],
            [5, -2, 5, 0, 17, -100, 8, 8, 3, 2, 1],
            list(range(500, -501, -1)),
        ]
        rng = random.Random(918273)
        cases.append([rng.randint(-10**7, 10**7) for _ in range(60000)])

        for values in cases:
            original = list(values)
            result = fast_dsp.sort_and_merge(values)
            assert isinstance(result, list)
            assert result == sorted(original), (len(original), result[:20])
    ''')
    result = subprocess.run(
        [sys.executable, '-c', program],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=8,
    )
    assert result.returncode == 0, (
        'The C extension failed correctness, large-array memory-safety, or '
        f'performance checks:\n{result.stdout}'
    )


def test_pipeline_contains_required_integration_logic():
    assert PIPELINE.is_file(), f'Expected pipeline script not found at {PIPELINE}'
    source = PIPELINE.read_text()
    tree = ast.parse(source, filename=str(PIPELINE))

    imported_module_names = set()
    imported_function_names = set()
    calls = []
    constants = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imported_module_names.add(alias.asname or alias.name.split('.')[0])
                imported_module_names.add(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imported_module_names.add(node.module)
                for alias in node.names:
                    if node.module == 'fast_dsp' and alias.name == 'sort_and_merge':
                        imported_function_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Call):
            calls.append(node.func)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            constants.append(node.value)

    uses_extension = any(
        (isinstance(func, ast.Attribute) and func.attr == 'sort_and_merge')
        or (isinstance(func, ast.Name) and func.id in imported_function_names)
        for func in calls
    )
    assert uses_extension, 'run_pipeline.py must call fast_dsp.sort_and_merge'

    assert any('ws://localhost:8080' in value for value in constants), (
        'run_pipeline.py must contain the required WebSocket endpoint'
    )
    websocket_import = any(
        name == 'socket' or name.startswith('websocket')
        for name in imported_module_names
    )
    call_names = {
        func.attr if isinstance(func, ast.Attribute) else func.id
        for func in calls
        if isinstance(func, (ast.Attribute, ast.Name))
    }
    assert websocket_import, 'run_pipeline.py must import WebSocket or socket client support'
    assert call_names.intersection({'connect', 'create_connection'}), (
        'run_pipeline.py must contain client connection logic'
    )
    assert call_names.intersection({'send', 'sendall'}), (
        'run_pipeline.py must contain logic to send through the client connection'
    )


def test_pipeline_executes_and_really_calls_native_extension():
    OUTPUT.unlink(missing_ok=True)
    marker = Path('/tmp/fast_dsp_called')
    marker.unlink(missing_ok=True)

    wrapper = textwrap.dedent(f'''
        import os
        import runpy
        import sys

        sys.path.insert(0, {str(PROJECT)!r})
        marker = {str(marker)!r}

        def profile(frame, event, arg):
            if event == 'c_call':
                if (getattr(arg, '__module__', None) == 'fast_dsp'
                        and getattr(arg, '__name__', None) == 'sort_and_merge'):
                    with open(marker, 'w') as f:
                        f.write('called')
            return profile

        sys.setprofile(profile)
        runpy.run_path({str(PIPELINE)!r}, run_name='__main__')
        sys.setprofile(None)
    ''')
    result = subprocess.run(
        [sys.executable, '-c', wrapper],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f'run_pipeline.py failed:\n{result.stdout}'
    assert marker.is_file(), (
        'run_pipeline.py executed without calling the native fast_dsp.sort_and_merge function'
    )


def test_final_output_mse():
    """
    Validates that the final output JSON contains the correct sorted integers
    transcribed from the audio file, evaluated using Mean Squared Error.
    """
    file_path = '/home/user/final_output.json'
    assert os.path.exists(file_path), f"Expected output file not found at {file_path}"

    truth = [1, 4, 8, 16, 17, 23, 42, 55, 88, 99]

    try:
        with open(file_path, 'r') as f:
            pred = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to read or parse JSON from {file_path}: {e}")

    assert isinstance(pred, list), f"Expected the JSON file to contain a list, but got {type(pred).__name__}"
    assert len(pred) > 0, "The output JSON list is empty."

    # Pad or truncate pred to match length
    if len(pred) < len(truth):
        pred.extend([0] * (len(truth) - len(pred)))
    elif len(pred) > len(truth):
        pred = pred[:len(truth)]

    mse = sum((p - t) ** 2 for p, t in zip(pred, truth)) / len(truth)

    threshold = 5.0
    assert mse <= threshold, (
        f"MSE is too high: {mse} > {threshold}. "
        f"The predicted array was {pred}, but the truth is {truth}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
