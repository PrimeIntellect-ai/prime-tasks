#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

import h5py
import numpy as np
from scipy.stats import ks_2samp

SCRIPT = '/home/user/verify_results.py'
DATA = '/home/user/profiling_data.h5'
REPORT = '/home/user/report.json'


def expected_from_hdf5(path):
    with h5py.File(path, 'r') as f:
        slow = [np.std(f['v1_slow'][f'run_{i}'][:]) for i in range(50)]
        fast = [np.std(f['v2_fast'][f'run_{i}'][:]) for i in range(50)]
    result = ks_2samp(slow, fast)
    return {
        'ks_statistic': round(float(result.statistic), 4),
        'p_value': round(float(result.pvalue), 4),
        'is_equivalent': bool(result.pvalue > 0.05),
    }


def run_script():
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        'verify_results.py failed with exit code '
        f'{completed.returncode}. stderr: {completed.stderr}'
    )
    assert os.path.isfile(REPORT), 'The file /home/user/report.json does not exist.'


def load_and_check_schema():
    with open(REPORT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, '/home/user/report.json is not a valid JSON file.'

    expected_keys = {'ks_statistic', 'p_value', 'is_equivalent'}
    assert set(data.keys()) == expected_keys, (
        f'JSON keys must be exactly {expected_keys}, found {set(data.keys())}.'
    )
    assert isinstance(data['ks_statistic'], (int, float)), 'ks_statistic must be a float.'
    assert isinstance(data['p_value'], (int, float)), 'p_value must be a float.'
    assert isinstance(data['is_equivalent'], bool), 'is_equivalent must be a boolean.'
    return data


def assert_matches(data, expected):
    assert math.isclose(data['ks_statistic'], expected['ks_statistic'], abs_tol=1e-12), (
        f"Expected ks_statistic {expected['ks_statistic']}, got {data['ks_statistic']}."
    )
    assert math.isclose(data['p_value'], expected['p_value'], abs_tol=1e-12), (
        f"Expected p_value {expected['p_value']}, got {data['p_value']}."
    )
    assert data['is_equivalent'] is expected['is_equivalent'], (
        f"Expected is_equivalent {expected['is_equivalent']}, got {data['is_equivalent']}."
    )


def write_random_challenge(path):
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'big'))
    with h5py.File(path, 'w') as f:
        g1 = f.create_group('v1_slow')
        g2 = f.create_group('v2_fast')
        slow_scales = rng.uniform(0.70, 1.30, size=50)
        fast_scales = rng.uniform(0.85, 1.45, size=50)
        for i in range(50):
            g1.create_dataset(f'run_{i}', data=rng.normal(0.0, slow_scales[i], 5000))
            g2.create_dataset(f'run_{i}', data=rng.normal(0.0, fast_scales[i], 5000))


def verify():
    # Preserve the original existence assertion.
    assert os.path.isfile(SCRIPT), 'The script /home/user/verify_results.py does not exist.'

    # Execute the submitted artifact and retain the original report assertions.
    original_expected = expected_from_hdf5(DATA)
    run_script()
    original = load_and_check_schema()
    assert math.isclose(original['ks_statistic'], 0.14, abs_tol=0.001), (
        f"Expected ks_statistic to be approx 0.1400, got {original['ks_statistic']}."
    )
    assert math.isclose(original['p_value'], 0.7166, abs_tol=0.001), (
        f"Expected p_value to be approx 0.7166, got {original['p_value']}."
    )
    assert original['is_equivalent'] is True, (
        f"Expected is_equivalent to be True, got {original['is_equivalent']}."
    )
    assert_matches(original, original_expected)

    # Replace the input temporarily with an unpredictable valid dataset. This
    # rejects scripts that merely emit the known report without reading the HDF5.
    challenge_expected = original_expected
    for _ in range(10):
        write_random_challenge(DATA)
        challenge_expected = expected_from_hdf5(DATA)
        if challenge_expected != original_expected:
            break
    assert challenge_expected != original_expected, 'Could not create a distinct challenge dataset.'

    run_script()
    challenge = load_and_check_schema()
    assert_matches(challenge, challenge_expected)


backup_fd, backup_path = tempfile.mkstemp(prefix='profiling_data_', suffix='.h5')
os.close(backup_fd)
shutil.copy2(DATA, backup_path)
ok = True
try:
    verify()
except Exception:
    traceback.print_exc()
    ok = False
finally:
    try:
        shutil.copy2(backup_path, DATA)
        os.unlink(backup_path)
        # Leave report.json generated from the instructed, original input.
        run_script()
        restored = load_and_check_schema()
        assert_matches(restored, expected_from_hdf5(DATA))
    except Exception:
        traceback.print_exc()
        ok = False

sys.exit(0 if ok else 1)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
