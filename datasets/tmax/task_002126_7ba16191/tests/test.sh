#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import subprocess
import difflib
import numpy as np
import pandas as pd
import pytest


def get_fuzz_ratio(s1, s2):
    """
    Independent implementation of fuzzywuzzy's fuzz.ratio
    which relies on difflib.SequenceMatcher.
    """
    if not isinstance(s1, str):
        s1 = str(s1)
    if not isinstance(s2, str):
        s2 = str(s2)
    return int(round(100 * difflib.SequenceMatcher(None, s1, s2).ratio()))


def run_fuzz_in_subprocess(cases, source_tree=False):
    script = f'''\
import json
from fuzzywuzzy import fuzz
cases = {cases!r}
result = {{
    "path": fuzz.__file__,
    "scores": [fuzz.ratio(a, b) for a, b in cases],
}}
if {not source_tree!r}:
    from importlib.metadata import version
    result["version"] = version("fuzzywuzzy")
print("RESULT=" + json.dumps(result))
'''
    env = os.environ.copy()
    if source_tree:
        env['PYTHONPATH'] = '/app/fuzzywuzzy'
    else:
        # Prevent the unpacked source directory from masquerading as an install.
        env.pop('PYTHONPATH', None)

    proc = subprocess.run(
        ['python3', '-c', script],
        cwd='/tmp',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    result_lines = [line for line in proc.stdout.splitlines() if line.startswith('RESULT=')]
    assert result_lines, f"Could not obtain fuzz.ratio results. stderr: {proc.stderr}"
    return json.loads(result_lines[-1][len('RESULT='):])


def test_fuzzywuzzy_fixed():
    """Check if the deliberate perturbation was removed from fuzz.py."""
    fuzz_py_path = "/app/fuzzywuzzy/fuzzywuzzy/fuzz.py"
    assert os.path.isfile(fuzz_py_path), f"Expected fuzz.py at {fuzz_py_path}"

    with open(fuzz_py_path, 'r') as f:
        content = f.read()

    assert "def ratio(s1, s2):\n    return 0" not in content, \
        "The deliberate perturbation 'return 0' in the ratio function is still present. It must be removed."

    data_a = pd.read_csv('/home/user/data_A.csv')['item_name'].tolist()
    data_b = pd.read_csv('/home/user/data_B.csv')['item_name'].tolist()
    cases = [(a, b) for a in data_a for b in data_b]
    cases.extend([
        ('identical text', 'identical text'),
        ('abc', 'xyz'),
        ('', ''),
        ('fuzzy wuzzy', 'fuzzy was a bear'),
    ])
    expected = [get_fuzz_ratio(a, b) for a, b in cases]

    # Exercise the repaired artifact directly from the required source tree.
    source_result = run_fuzz_in_subprocess(cases, source_tree=True)
    assert os.path.realpath(source_result['path']) == os.path.realpath(fuzz_py_path), \
        f"Source-tree import did not load {fuzz_py_path}: {source_result['path']}"
    assert source_result['scores'] == expected, \
        "The repaired source-tree fuzz.ratio does not produce correct scores."

    # Exercise a normal environment import, independently of the source path, to
    # ensure the distribution was actually installed (standard or editable mode).
    installed_result = run_fuzz_in_subprocess(cases, source_tree=False)
    assert installed_result.get('version') == '0.18.0', \
        f"Installed fuzzywuzzy version is not 0.18.0: {installed_result.get('version')}"
    assert installed_result['scores'] == expected, \
        "The installed fuzzywuzzy fuzz.ratio does not produce correct scores."


def test_ci_output_accuracy():
    """
    Recompute the 95% confidence interval using the bootstrap method
    and verify the agent's output is within the allowed tolerance.
    """
    output_path = '/home/user/ci_output.txt'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    try:
        agent_lower, agent_upper = map(float, content.split(','))
    except ValueError:
        pytest.fail(f"Could not parse two floats separated by a comma from {output_path}. Content: {content}")

    preds_path = '/home/user/model_predictions.csv'
    assert os.path.isfile(preds_path), f"Predictions file {preds_path} missing."

    preds = pd.read_csv(preds_path)
    matches = preds[preds['predicted_match'] == 1]

    scores = []
    for _, row in matches.iterrows():
        scores.append(get_fuzz_ratio(row['item_A'], row['item_B']))

    scores = np.array(scores)

    # Re-run the bootstrap procedure exactly as specified
    np.random.seed(42)
    resampled_means = []
    for _ in range(10000):
        resample = np.random.choice(scores, size=len(scores), replace=True)
        resampled_means.append(np.mean(resample))

    expected_lower = np.percentile(resampled_means, 2.5)
    expected_upper = np.percentile(resampled_means, 97.5)

    err_lower = abs(agent_lower - expected_lower)
    err_upper = abs(agent_upper - expected_upper)

    assert err_lower <= 0.5, \
        f"Lower bound {agent_lower} is too far from expected {expected_lower:.2f} (error: {err_lower:.2f} > 0.5)"
    assert err_upper <= 0.5, \
        f"Upper bound {agent_upper} is too far from expected {expected_upper:.2f} (error: {err_upper:.2f} > 0.5)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
