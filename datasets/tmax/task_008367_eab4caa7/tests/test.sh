#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier_audit
mkdir -p /tmp/verifier_audit

cat << 'AUDIT_EOF' > /tmp/verifier_audit/sitecustomize.py
import json
import os
import numpy as np

_LOG = os.environ.get("MC_AUDIT_LOG")
_original_default_rng = np.random.default_rng

def _write(record):
    if not _LOG:
        return
    data = (json.dumps(record, separators=(",", ":")) + "\n").encode("utf-8")
    fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)

class _AuditedGenerator:
    def __init__(self, generator, seed):
        self._generator = generator
        self._seed = seed

    def normal(self, loc=0.0, scale=1.0, size=None):
        seed = self._seed if isinstance(self._seed, (int, np.integer)) else None
        if isinstance(size, (int, np.integer)):
            logged_size = int(size)
        elif size is None:
            logged_size = None
        else:
            try:
                logged_size = list(size)
            except TypeError:
                logged_size = str(size)
        _write({
            "event": "normal",
            "pid": os.getpid(),
            "seed": int(seed) if seed is not None else None,
            "loc": float(loc),
            "scale": float(scale),
            "size": logged_size,
        })
        return self._generator.normal(loc=loc, scale=scale, size=size)

    def __getattr__(self, name):
        return getattr(self._generator, name)

def _audited_default_rng(seed=None):
    return _AuditedGenerator(_original_default_rng(seed), seed)

np.random.default_rng = _audited_default_rng
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
from pathlib import Path

OUTPUT_FILE = '/home/user/model_fit.json'
AUDIT_LOG = '/tmp/verifier_mc_audit.jsonl'
AUDIT_DIR = '/tmp/verifier_audit'


def find_scripts():
    roots = ['/home/user', '/tmp', '/workspace']
    candidates = []
    seen = set()
    import_pattern = re.compile(r'(^|\n)\s*(?:import\s+multiprocessing\b|from\s+multiprocessing\s+import\b)')

    for root in roots:
        if not os.path.isdir(root):
            continue
        for path in Path(root).rglob('*.py'):
            absolute = str(path.resolve())
            if absolute in seen:
                continue
            seen.add(absolute)
            if absolute == '/tmp/test_final_state.py' or absolute.startswith(AUDIT_DIR + '/'):
                continue
            try:
                source = path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            if import_pattern.search(source) and any(token in source for token in (
                'noisy_signal', 'model_fit', 'default_rng', '1000'
            )):
                rank = sum(token in source for token in (
                    'noisy_signal.csv', 'model_fit.json', 'default_rng', '1000',
                    'root_scalar', 'fft'
                ))
                candidates.append((-rank, absolute))

    return [path for _, path in sorted(candidates)]


def read_audit():
    records = []
    if not os.path.isfile(AUDIT_LOG):
        return records
    with open(AUDIT_LOG, 'r', encoding='utf-8') as handle:
        for line in handle:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return records


def audit_is_valid(records, n):
    relevant = [
        record for record in records
        if record.get('event') == 'normal'
        and record.get('loc') == 0.0
        and record.get('scale') == 0.5
        and record.get('size') == n
    ]

    expected_seeds = list(range(42, 1042))
    observed_seeds = sorted(record.get('seed') for record in relevant if isinstance(record.get('seed'), int))
    if len(relevant) != 1000 or observed_seeds != expected_seeds:
        return False

    # The requested Monte Carlo work must actually occur in at least four
    # separate multiprocessing workers, rather than in one sequential process.
    worker_pids = {record.get('pid') for record in relevant}
    return len(worker_pids) >= 4


def execute_automation_script():
    scripts = find_scripts()
    assert scripts, 'No Python automation script using the multiprocessing module was found.'

    with open('/home/user/noisy_signal.csv', 'r', encoding='utf-8') as handle:
        n = sum(1 for _ in handle) - 1

    failures = []
    for script in scripts:
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)

        env = os.environ.copy()
        env['MC_AUDIT_LOG'] = AUDIT_LOG
        old_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = AUDIT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')

        try:
            result = subprocess.run(
                ['python3', script],
                cwd=os.path.dirname(script) or '/home/user',
                env=env,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue

        if result.returncode != 0:
            failures.append(f'{script}: exited with status {result.returncode}')
            continue
        if not os.path.isfile(OUTPUT_FILE):
            failures.append(f'{script}: did not create {OUTPUT_FILE}')
            continue
        if not audit_is_valid(read_audit(), n):
            failures.append(f'{script}: did not perform exactly 1000 reproducible simulations across at least four worker processes')
            continue
        return script

    assert False, 'No submitted automation script satisfied the execution requirements. ' + '; '.join(failures)


def test_model_fit_output():
    execute_automation_script()

    output_file = OUTPUT_FILE
    assert os.path.isfile(output_file), f"The expected output file was not found at {output_file}."

    with open(output_file, 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {output_file} is not valid JSON."

    expected_keys = {"f0", "A_estimate", "A_ci_lower", "A_ci_upper"}
    actual_keys = set(student_data.keys())
    assert actual_keys == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, found {actual_keys}."

    for key in expected_keys:
        assert isinstance(student_data[key], (int, float)), f"Value for '{key}' must be a float."

    truth_script = r'''
import numpy as np
import pandas as pd
from scipy.fft import fft, fftfreq
from scipy.optimize import root_scalar
import json

def estimate_A(y, N):
    yf = np.abs(fft(y))
    yf[0] = 0
    idx = np.argmax(yf[:N//2])
    P_max = yf[idx]
    C_est = P_max / (N / 2)
    def func(A):
        return A * np.exp(A) - C_est
    res = root_scalar(func, bracket=[0, 10])
    return idx, res.root

def main():
    df = pd.read_csv('/home/user/noisy_signal.csv')
    y = df['y'].values
    N = len(y)
    fs = 100.0

    idx, A_est = estimate_A(y, N)
    freqs = fftfreq(N, 1/fs)
    f0 = freqs[idx]

    A_sims = []
    for i in range(1000):
        rng = np.random.default_rng(42 + i)
        noise = rng.normal(loc=0.0, scale=0.5, size=N)
        y_noisy = y + noise
        _, A_sim = estimate_A(y_noisy, N)
        A_sims.append(A_sim)

    A_ci_lower = np.percentile(A_sims, 2.5)
    A_ci_upper = np.percentile(A_sims, 97.5)

    truth = {
        "f0": round(float(f0), 3),
        "A_estimate": round(float(A_est), 3),
        "A_ci_lower": round(float(A_ci_lower), 3),
        "A_ci_upper": round(float(A_ci_upper), 3)
    }
    print(json.dumps(truth))

if __name__ == '__main__':
    main()
'''
    script_path = '/tmp/compute_truth.py'
    with open(script_path, 'w') as f:
        f.write(truth_script)

    clean_env = os.environ.copy()
    clean_env.pop('MC_AUDIT_LOG', None)
    clean_env.pop('PYTHONPATH', None)
    try:
        result = subprocess.run(
            ['python3', script_path], capture_output=True, text=True,
            check=True, env=clean_env
        )
        truth_data = json.loads(result.stdout.strip())
    except subprocess.CalledProcessError:
        assert abs(student_data["f0"] - 3.0) < 0.1, "f0 is incorrect."
        assert 1.1 < student_data["A_estimate"] < 1.3, "A_estimate is out of expected bounds."
        assert student_data["A_ci_lower"] < student_data["A_estimate"] < student_data["A_ci_upper"], "Invalid confidence interval bounds."
        return
    finally:
        if os.path.exists(script_path):
            os.remove(script_path)

    for key in expected_keys:
        expected_val = truth_data[key]
        student_val = student_data[key]
        assert abs(student_val - expected_val) <= 0.001, (
            f"Value for '{key}' is incorrect. "
            f"Expected approximately {expected_val}, got {student_val}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
