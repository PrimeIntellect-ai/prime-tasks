#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib.util
import os
import random
import subprocess
import threading
import time

SCRIPT_PATH = "/home/user/calc_series.py"
CRASH_INPUT = -42069


def expected_value(n):
    return 0 if n == CRASH_INPUT else (n ** 2) % 1000


def expected_sum(numbers):
    return sum(expected_value(n) for n in numbers)


def load_module():
    spec = importlib.util.spec_from_file_location("submitted_calc_series", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Could not load calc_series.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_crash_input_file():
    path = "/home/user/crash_input.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you write the crash input to it?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "-42069", f"Expected crash_input.txt to contain '-42069', but found '{content}'."


def test_final_result_file():
    path = "/home/user/final_result.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you write the final result to it?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = expected_sum(range(-100000, 100001))
    assert content == str(expected), f"Expected final_result.txt to contain '{expected}', but found '{content}'."


def test_calc_series_script_fixes():
    path = SCRIPT_PATH
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "ThreadPoolExecutor" in content, "The script must still use ThreadPoolExecutor for concurrency."
    assert "calculate_all" in content, "The script must still define calculate_all."


def test_process_number_is_safe_and_correct():
    module = load_module()
    assert callable(getattr(module, "process_number", None)), "process_number must be callable"
    assert module.process_number(CRASH_INPUT) == 0, "The crashing input must safely return 0"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    samples = [rng.randint(-100000, 100000) for _ in range(40)]
    samples += [-100000, -1, 0, 1, 99999, 100000]
    for n in samples:
        if n != CRASH_INPUT:
            assert module.process_number(n) == expected_value(n), f"Incorrect process_number result for {n}"


def test_calculate_all_is_correct_and_deterministic():
    module = load_module()
    assert callable(getattr(module, "calculate_all", None)), "calculate_all must be callable"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    numbers = [rng.randint(-100000, 100000) for _ in range(500)]
    numbers.extend([CRASH_INPUT, CRASH_INPUT, -100000, 0, 100000])
    wanted = expected_sum(numbers)

    results = [module.calculate_all(list(numbers)) for _ in range(4)]
    assert results == [wanted] * 4, f"calculate_all was incorrect or nondeterministic: {results}"

    second = [rng.randint(-100000, 100000) for _ in range(137)]
    assert module.calculate_all(second) == expected_sum(second), "calculate_all did not reset or accumulate correctly"


def test_calculate_all_really_processes_concurrently():
    module = load_module()
    original = module.process_number
    state_lock = threading.Lock()
    active = 0
    maximum_active = 0

    def observed_process_number(n):
        nonlocal active, maximum_active
        with state_lock:
            active += 1
            maximum_active = max(maximum_active, active)
        try:
            time.sleep(0.01)
            return original(n)
        finally:
            with state_lock:
                active -= 1

    module.process_number = observed_process_number
    numbers = list(range(-40, 40))
    result = module.calculate_all(numbers)
    assert result == expected_sum(numbers), "Concurrent calculation returned the wrong sum"
    assert maximum_active >= 2, "calculate_all did not execute process_number concurrently"


def test_main_executes_required_full_range():
    expected = str(expected_sum(range(-100000, 100001)))
    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert completed.returncode == 0, f"calc_series.py failed when executed: {completed.stderr}"
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    assert lines and lines[-1] == expected, (
        "Running calc_series.py must execute calculate_all(list(range(-100000, 100001))) "
        f"and output {expected}; got {completed.stdout!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
