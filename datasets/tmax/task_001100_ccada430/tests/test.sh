#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import json
import os
import re
import subprocess

import numpy as np


@functools.lru_cache(maxsize=1)
def get_reference():
    """Compute reference objective values and the expected optimized threshold."""
    script = r'''
import json
import h5py
import numpy as np
from scipy.optimize import minimize
import networkx as nx

FILE_PATH = "/home/user/sim_data.h5"
POINTS = [0.0, 0.5, 100.0, 10000.0]

def evaluate_threshold(thresh, file_path):
    thresh_val = thresh[0]
    with h5py.File(file_path, 'r') as f:
        G = nx.Graph()
        nodes = sorted(list(f.keys()))

        for n in nodes:
            G.add_node(n, signal=f[n][:])

        total_energy = 0.0
        for n in nodes:
            sig = G.nodes[n]['signal']
            sig_masked = np.where(np.abs(sig) > thresh_val, sig, 0)
            sp = np.fft.fft(sig_masked)
            energy = np.sum(np.abs(sp)**2)
            total_energy += energy

    return -total_energy

values = [float(evaluate_threshold(np.array([x]), FILE_PATH)) for x in POINTS]
res = minimize(evaluate_threshold, x0=[0.5], args=(FILE_PATH,), method='Nelder-Mead', options={'xatol': 1e-8, 'fatol': 1e-8})
print(json.dumps({
    "values": values,
    "threshold4": f"{res.x[0]:.4f}"
}))
'''
    result = subprocess.run(
        ["python3", "-c", script], capture_output=True, text=True,
        check=True, timeout=180
    )
    return json.loads(result.stdout.strip())


def get_expected_value():
    return get_reference()["threshold4"]


def run_submission_evaluator(hash_seed):
    """Import the submitted artifact and exercise its objective function."""
    runner = r'''
import importlib.util
import json
import numpy as np

path = "/home/user/analyze.py"
spec = importlib.util.spec_from_file_location("submitted_analyze", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, "evaluate_threshold", None))
points = [0.0, 0.5, 100.0, 10000.0]
values = [float(module.evaluate_threshold(np.array([x]), "/home/user/sim_data.h5")) for x in points]
print("VERIFIER_VALUES=" + json.dumps([v.hex() for v in values]))
'''
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = str(hash_seed)
    result = subprocess.run(
        ["python3", "-c", runner], capture_output=True, text=True,
        env=env, timeout=180
    )
    assert result.returncode == 0, (
        f"analyze.py could not be imported and evaluated with PYTHONHASHSEED={hash_seed}:\n"
        f"{result.stdout}\n{result.stderr}"
    )
    matches = re.findall(r"^VERIFIER_VALUES=(.+)$", result.stdout, re.MULTILINE)
    assert matches, "The submitted evaluator did not produce verifiable results."
    return json.loads(matches[-1])


def test_analyze_script_fixed():
    """Check the source and behavior of the repaired analysis script."""
    file_path = "/home/user/analyze.py"
    assert os.path.isfile(file_path), f"Expected script {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "set(f.keys())" not in content, "The script still contains the non-deterministic `set(f.keys())` operation."
    assert "sorted" in content or "list(f" in content, "The script does not appear to sort or deterministically order the nodes."

    # Exercise the actual evaluator under several independent hash orders. A
    # deterministic reduction must produce bit-identical values every time.
    runs = [run_submission_evaluator(seed) for seed in (1, 2, 3, 17, 101)]
    assert all(values == runs[0] for values in runs[1:]), (
        "evaluate_threshold still changes with PYTHONHASHSEED; the node reduction order is not deterministic."
    )

    # Confirm that the submitted evaluator retained the original computation.
    actual = [float.fromhex(value) for value in runs[0]]
    expected = get_reference()["values"]
    assert np.allclose(actual, expected, rtol=1e-12, atol=0.0), (
        "evaluate_threshold no longer performs the required spectral-energy computation."
    )


def test_analyze_script_executes():
    """Actually run the repaired artifact and validate its optimized result."""
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = "29"
    result = subprocess.run(
        ["python3", "/home/user/analyze.py"], capture_output=True, text=True,
        env=env, timeout=180
    )
    assert result.returncode == 0, f"analyze.py failed when executed:\n{result.stdout}\n{result.stderr}"
    match = re.search(r"Optimized Threshold:\s*([-+0-9.eE]+)", result.stdout)
    assert match, "analyze.py did not report an optimized threshold when executed."
    assert f"{float(match.group(1)):.4f}" == get_expected_value(), (
        "analyze.py reported an incorrect optimized threshold."
    )


def test_answer_file_correct():
    """Check if answer.txt contains the correct reproducible optimized threshold."""
    answer_path = "/home/user/answer.txt"
    assert os.path.isfile(answer_path), f"Expected answer file {answer_path} is missing."

    with open(answer_path, "r") as f:
        answer_text = f.read().strip()

    expected_val = get_expected_value()

    assert answer_text == expected_val, f"Incorrect optimized threshold in {answer_path}. Expected {expected_val}, got {answer_text}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
