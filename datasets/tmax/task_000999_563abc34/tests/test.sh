#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_cholesky_diags_output():
    """Check that the output file exists and contains the correct traces."""
    output_file = "/home/user/cholesky_diags.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, 'r') as f:
        content = f.read().strip()

    expected_content = "15.908070,15.908070"
    assert content == expected_content, f"Expected output '{expected_content}', but got '{content}'."

def test_script_exists():
    """Check that the script file was created."""
    script_file = "/home/user/prepare_data.py"
    assert os.path.exists(script_file), f"Script file {script_file} does not exist."
    assert os.path.isfile(script_file), f"Script file {script_file} is not a regular file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 - <<'PY'
import json
import os
import re
import subprocess
import textwrap

script = "/home/user/prepare_data.py"
output = "/home/user/cholesky_diags.txt"
instrument_dir = "/tmp/cholesky_instrument"
log_file = "/tmp/cholesky_instrument_result.json"
os.makedirs(instrument_dir, exist_ok=True)

sitecustomize = r'''
import atexit
import json
import os
import secrets
import numpy as np

_log = os.environ["CHOLESKY_TEST_LOG"]
_real_linspace = np.linspace
_real_cholesky = np.linalg.cholesky
_grid_seen = False
_domain = 0
_attempt = 0
_failures = [secrets.randbelow(3) + 1, secrets.randbelow(3) + 1]
_expected = []
_errors = []

_grid = _real_linspace(0, 1, 200)
_subdomains = [_grid[:100], _grid[100:]]
_bases = [np.exp(-100 * (x[:, None] - x[None, :]) ** 2) for x in _subdomains]

def checked_linspace(start, stop, num=50, endpoint=True, *args, **kwargs):
    global _grid_seen
    result = _real_linspace(start, stop, num, endpoint, *args, **kwargs)
    if start == 0 and stop == 1 and num == 200 and endpoint is True and np.array_equal(result, _grid):
        _grid_seen = True
    return result

def checked_cholesky(a, *args, **kwargs):
    global _domain, _attempt
    if _domain >= 2:
        _errors.append("unexpected extra cholesky call")
        return _real_cholesky(a, *args, **kwargs)

    arr = np.asarray(a)
    base = _bases[_domain]
    jitter = 1e-8 * (10 ** _attempt)
    expected_matrix = base + jitter * np.eye(100)
    if arr.shape != (100, 100) or not np.allclose(arr, expected_matrix, rtol=1e-11, atol=1e-13):
        _errors.append("cholesky input did not equal the required covariance plus the expected jitter")
        raise AssertionError(_errors[-1])

    if _attempt < _failures[_domain]:
        _attempt += 1
        raise np.linalg.LinAlgError("injected numerical failure")

    factor = _real_cholesky(arr, *args, **kwargs)
    _expected.append(float(np.diag(factor).sum()))
    _domain += 1
    _attempt = 0
    return factor

np.linspace = checked_linspace
np.linalg.cholesky = checked_cholesky

@atexit.register
def write_result():
    data = {
        "valid": _grid_seen and _domain == 2 and len(_expected) == 2 and not _errors,
        "grid_seen": _grid_seen,
        "domains_completed": _domain,
        "expected": _expected,
        "errors": _errors,
    }
    with open(_log, "w") as f:
        json.dump(data, f)
'''

with open(os.path.join(instrument_dir, "sitecustomize.py"), "w") as f:
    f.write(textwrap.dedent(sitecustomize))

for path in (output, log_file):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

env = os.environ.copy()
env["PYTHONPATH"] = instrument_dir
env["CHOLESKY_TEST_LOG"] = log_file
result = subprocess.run(["python3", script], cwd="/home/user", env=env,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, timeout=30)
assert result.returncode == 0, f"prepare_data.py failed under behavioral testing: {result.stderr}"
assert os.path.isfile(log_file), "instrumentation log was not produced"
with open(log_file) as f:
    data = json.load(f)
assert data["valid"], f"required NumPy operations were not performed correctly: {data}"
assert os.path.isfile(output), "executing prepare_data.py did not create the output file"
with open(output) as f:
    content = f.read().strip()
assert re.fullmatch(r"-?\d+\.\d{6},-?\d+\.\d{6}", content), f"incorrect output format: {content!r}"
expected = ",".join(f"{value:.6f}" for value in data["expected"])
assert content == expected, f"script did not write traces from the successful Cholesky factors: expected {expected!r}, got {content!r}"

# Restore the required ordinary final state by executing the submitted script normally.
result = subprocess.run(["python3", script], cwd="/home/user",
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, timeout=30)
assert result.returncode == 0, f"prepare_data.py failed during normal execution: {result.stderr}"
with open(output) as f:
    final_content = f.read().strip()
assert final_content == "15.908070,15.908070", f"normal execution produced {final_content!r}"
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
