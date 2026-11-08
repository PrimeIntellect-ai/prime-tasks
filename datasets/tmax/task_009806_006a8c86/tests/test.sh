#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import json
import base64
import random
import subprocess
import sys
import pytest


def get_expected_structure():
    return [
        {"4": [2, 2]},
        {"9": [3, 3]},
        {"25": [5, 5]},
        {"49": [7, 7]},
        {"121": [11, 11]}
    ]


def expected_factors(value):
    n = value
    factors = []
    divisor = 2
    while divisor * divisor <= n:
        while n % divisor == 0:
            factors.append(divisor)
            n //= divisor
        divisor += 1
    if n > 1:
        factors.append(n)
    return factors


def expected_structure(numbers):
    return [
        {str(n): expected_factors(n)}
        for n in sorted(numbers)
    ]


def decode_result(result):
    assert isinstance(result, str), "process_numbers must return a base64 string."
    decoded = base64.b64decode(result, validate=True).decode("utf-8")
    return json.loads(decoded)


def test_build_success_log():
    log_path = "/home/user/build_success.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist. The regression test might have failed or not written the output."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {log_path} is empty."

    try:
        decoded_bytes = base64.b64decode(content)
        decoded_str = decoded_bytes.decode("utf-8")
    except Exception as e:
        pytest.fail(f"Content of {log_path} is not a valid UTF-8 base64 string: {e}")

    try:
        parsed_json = json.loads(decoded_str)
    except Exception as e:
        pytest.fail(f"Decoded content of {log_path} is not valid JSON: {e}")

    expected = get_expected_structure()
    assert parsed_json == expected, f"Parsed JSON from {log_path} does not match expected output.\nExpected: {expected}\nGot: {parsed_json}"


def test_regression_test_script():
    script_path = "/home/user/regression_test.py"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "assert" in content, f"File {script_path} does not contain any 'assert' statements."
    assert "process_numbers" in content, f"File {script_path} does not seem to call 'process_numbers'."

    try:
        tree = ast.parse(content, filename=script_path)
    except SyntaxError as e:
        pytest.fail(f"File {script_path} is not valid Python: {e}")

    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), \
        "regression_test.py must contain a real Python assert statement."

    required_values = [4, 9, 25, 49, 121]
    found_required_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
            continue
        if node.func.id != "process_numbers" or len(node.args) != 1:
            continue
        arg = node.args[0]
        if isinstance(arg, ast.List):
            try:
                values = [ast.literal_eval(item) for item in arg.elts]
            except Exception:
                continue
            if values == required_values:
                found_required_call = True
                break
    assert found_required_call, \
        "regression_test.py must call process_numbers([4, 9, 25, 49, 121])."

    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user/math_build" + os.pathsep + env.get("PYTHONPATH", "")
    completed = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, \
        f"Running regression_test.py failed.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"


def test_factorizer_functionality():
    module_path = "/home/user/math_build"
    assert os.path.exists(os.path.join(module_path, "factorizer.py")), "factorizer.py is missing."

    if module_path not in sys.path:
        sys.path.insert(0, module_path)

    try:
        import factorizer
    except ImportError as e:
        pytest.fail(f"Could not import factorizer: {e}")

    # Test functional correctness and encoding
    try:
        res = factorizer.process_numbers([4, 9, 25, 49, 121])
    except Exception as e:
        pytest.fail(f"process_numbers raised an exception: {e}")

    try:
        decoded_str = base64.b64decode(res).decode("utf-8")
        parsed = json.loads(decoded_str)
    except Exception as e:
        pytest.fail(f"Output of process_numbers is not valid base64 UTF-8 JSON: {e}")

    assert parsed == get_expected_structure(), "process_numbers did not return the expected mathematical results."

    # Test for race conditions with a larger set of numbers
    large_input = [i * i for i in range(2, 100)]
    try:
        res_large = factorizer.process_numbers(large_input)
        parsed_large = json.loads(base64.b64decode(res_large).decode("utf-8"))
    except Exception as e:
        pytest.fail(f"process_numbers failed on a larger input set: {e}")

    assert len(parsed_large) == len(large_input), "Concurrency bug is still present: missing results when processing many numbers."
    assert parsed_large == expected_structure(large_input), \
        "process_numbers returned incorrect factors for the larger input set."

    # Exercise mathematical correctness on values selected at verification time.
    rng = random.SystemRandom()
    generated = set()
    while len(generated) < 120:
        generated.add(rng.randrange(2, 50000))
    generated_input = list(generated)
    rng.shuffle(generated_input)

    try:
        generated_result = factorizer.process_numbers(generated_input)
        parsed_generated = decode_result(generated_result)
    except Exception as e:
        pytest.fail(f"process_numbers failed on generated inputs: {e}")

    assert parsed_generated == expected_structure(generated_input), \
        "process_numbers returned incorrect factors or nondeterministic ordering for generated inputs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
