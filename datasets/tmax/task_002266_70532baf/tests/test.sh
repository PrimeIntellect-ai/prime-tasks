#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import math
import sys

def test_result_json_exists():
    assert os.path.isfile('/home/user/result.json'), "/home/user/result.json is missing. Did you forget to create it?"

def test_result_json_contents():
    with open('/home/user/result.json', 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/result.json is not valid JSON."

    # Compute expected bad commit
    cmd = subprocess.run(
        ['git', 'log', '--grep=refactor: optimize calc module', '--format=%H'],
        cwd='/home/user/repo', capture_output=True, text=True
    )
    expected_bad_commit = cmd.stdout.strip()

    assert 'bad_commit' in result, "'bad_commit' key is missing from result.json."
    assert result['bad_commit'] == expected_bad_commit, f"'bad_commit' is incorrect. Expected {expected_bad_commit}, got {result['bad_commit']}."

    # Verify secret token
    assert 'secret_token' in result, "'secret_token' key is missing from result.json."
    assert result['secret_token'] == "FPT-ANOMALY-RECOVERY-992A", "'secret_token' is incorrect. Did you extract it correctly from the bytecode?"

    # Compute expected variance robustly
    with open('/home/user/data.txt', 'r') as f:
        data = [float(x.strip()) for x in f.readlines()]
    n = len(data)
    mean = sum(data) / n
    expected_variance = sum((x - mean) ** 2 for x in data) / (n - 1)

    assert 'fixed_variance' in result, "'fixed_variance' key is missing from result.json."
    assert isinstance(result['fixed_variance'], (int, float)), "'fixed_variance' must be a number."
    assert math.isclose(result['fixed_variance'], expected_variance, rel_tol=1e-5, abs_tol=1e-15), \
        f"'fixed_variance' is incorrect or suffers from catastrophic cancellation. Expected ~{expected_variance}, got {result['fixed_variance']}."

def test_calc_py_fixed():
    # Verify that calc.py at HEAD produces the correct variance
    sys.path.insert(0, '/home/user/repo')
    try:
        import calc
        with open('/home/user/data.txt', 'r') as f:
            data = [float(x.strip()) for x in f.readlines()]
        variance = calc.get_variance(data)

        n = len(data)
        mean = sum(data) / n
        expected_variance = sum((x - mean) ** 2 for x in data) / (n - 1)

        assert math.isclose(variance, expected_variance, rel_tol=1e-5, abs_tol=1e-15), \
            "calc.py's get_variance still suffers from precision loss. Please implement a numerically stable algorithm."
    except ImportError:
        assert False, "Could not import calc.py from /home/user/repo."
    except AttributeError:
        assert False, "calc.py does not have a get_variance function."
    finally:
        sys.path.pop(0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
