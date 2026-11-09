#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

PROJECT_DIR = '/home/user/build_debug'
DATA_PATH = os.path.join(PROJECT_DIR, 'data.json')
PROCESSOR_PATH = os.path.join(PROJECT_DIR, 'processor.py')
TEST_PATH = os.path.join(PROJECT_DIR, 'test_processor.py')


def test_data_json_unmodified():
    assert os.path.isfile(DATA_PATH), f"{DATA_PATH} is missing"

    # Check that it's encoded in utf-16le and contains the right data.
    try:
        with open(DATA_PATH, 'r', encoding='utf-16le') as f:
            data = json.load(f)
        assert data == {'values': [0.1, 0.2]}, "data.json was modified or corrupted"
    except Exception as e:
        assert False, f"Failed to read data.json with utf-16le encoding. Was it modified? Error: {e}"


def test_pytest_passes():
    assert os.path.isfile(TEST_PATH), f"{TEST_PATH} is missing"

    # Run pytest on the submitted test_processor.py.
    result = subprocess.run(
        ['python3', '-m', 'pytest', TEST_PATH],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, (
        f"pytest failed with exit code {result.returncode}.\n"
        f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    )


def test_load_and_sum_behavior():
    assert os.path.isfile(PROCESSOR_PATH), f"{PROCESSOR_PATH} is missing"

    spec = importlib.util.spec_from_file_location('submitted_processor', PROCESSOR_PATH)
    assert spec is not None and spec.loader is not None, "processor.py is not importable"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'load_and_sum', None)), "load_and_sum is missing or not callable"

    # Exercise the submitted implementation against independently generated
    # UTF-16LE JSON files, including the original data file.
    original_result = module.load_and_sum(DATA_PATH)
    assert math.isclose(original_result, sum([0.1, 0.2]), rel_tol=1e-12, abs_tol=1e-12)

    cases = [
        [1.25, -0.5, 2.0],
        [10, -4, 0.125, 3.5],
    ]
    with tempfile.TemporaryDirectory() as tmpdir:
        for index, values in enumerate(cases):
            path = os.path.join(tmpdir, f'case_{index}.json')
            with open(path, 'w', encoding='utf-16le') as f:
                json.dump({'values': values}, f)
            result = module.load_and_sum(path)
            expected = sum(values)
            assert math.isclose(result, expected, rel_tol=1e-12, abs_tol=1e-12), (
                f"load_and_sum({values!r}) returned {result!r}, expected {expected!r}"
            )


def _run_copied_test_with_result(forced_result):
    with tempfile.TemporaryDirectory() as tmpdir:
        copied_test = os.path.join(tmpdir, 'test_processor.py')
        shutil.copyfile(TEST_PATH, copied_test)

        # conftest is imported before the copied test module. Patching the real
        # processor module verifies that the submitted test actually exercises
        # load_and_sum and distinguishes correct from incorrect results.
        with open(os.path.join(tmpdir, 'conftest.py'), 'w', encoding='utf-8') as f:
            f.write(
                "import os\n"
                "import processor\n"
                "processor.load_and_sum = lambda filepath: float(os.environ['FORCED_RESULT'])\n"
            )

        env = os.environ.copy()
        env['FORCED_RESULT'] = repr(forced_result)
        env['PYTHONPATH'] = PROJECT_DIR + os.pathsep + env.get('PYTHONPATH', '')
        return subprocess.run(
            ['python3', '-m', 'pytest', '-q', copied_test],
            cwd=PROJECT_DIR,
            env=env,
            capture_output=True,
            text=True
        )


def test_submitted_test_exercises_result_and_handles_float_robustly():
    assert os.path.isfile(TEST_PATH), f"{TEST_PATH} is missing"

    exact_decimal = _run_copied_test_with_result(0.3)
    assert exact_decimal.returncode == 0, (
        "The submitted test does not accept the mathematically correct value 0.3; "
        "it may be hardcoding the broken floating-point representation.\n"
        f"Stdout:\n{exact_decimal.stdout}\nStderr:\n{exact_decimal.stderr}"
    )

    wrong_value = _run_copied_test_with_result(-123.456)
    assert wrong_value.returncode != 0, (
        "The submitted test still passes when load_and_sum returns a clearly wrong value, "
        "so it does not meaningfully exercise and assert the function's result.\n"
        f"Stdout:\n{wrong_value.stdout}\nStderr:\n{wrong_value.stderr}"
    )


def test_processor_py_fixed():
    assert os.path.isfile(PROCESSOR_PATH), f"{PROCESSOR_PATH} is missing"

    with open(PROCESSOR_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Retain the original source-level assertion in addition to behavioral checks.
    assert "utf-16" in content.lower(), "processor.py does not appear to fix the utf-16 encoding issue"


def test_test_processor_py_fixed():
    assert os.path.isfile(TEST_PATH), f"{TEST_PATH} is missing"

    with open(TEST_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Retain the original assertion in addition to exercising the test behavior.
    assert "assert result == 0.3" not in content, "test_processor.py still contains the exact 'assert result == 0.3' bug"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
