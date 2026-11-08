#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile

import matplotlib.image as mpimg
import pandas as pd
import pytest
import scipy.stats as stats

SCRIPT_PATH = '/home/user/analytics.py'
RESULTS_PATH = '/home/user/results.json'
REPORT_PATH = '/home/user/report.png'


def run_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"Expected pipeline script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} must be a regular file."

    for path in (RESULTS_PATH, REPORT_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    account = pwd.getpwnam('user')
    mpl_config = tempfile.mkdtemp(prefix='verifier-mpl-')
    os.chown(mpl_config, account.pw_uid, account.pw_gid)

    env = os.environ.copy()
    env['HOME'] = account.pw_dir
    env['MPLCONFIGDIR'] = mpl_config
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
            preexec_fn=demote,
        )
    finally:
        shutil.rmtree(mpl_config, ignore_errors=True)

    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} failed when executed headlessly (exit {completed.returncode}):\n"
        f"{completed.stdout}"
    )


def read_results():
    assert os.path.isfile(RESULTS_PATH), f"Expected output file {RESULTS_PATH} does not exist. Did the script run successfully?"
    assert stat.S_ISREG(os.lstat(RESULTS_PATH).st_mode), f"{RESULTS_PATH} must be a regular file."

    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    assert 't_stat' in results, f"Key 't_stat' missing in {RESULTS_PATH}"
    assert 'p_value' in results, f"Key 'p_value' missing in {RESULTS_PATH}"
    assert set(results) == {'t_stat', 'p_value'}, (
        f"{RESULTS_PATH} must contain exactly the keys 't_stat' and 'p_value'."
    )

    t_stat = results['t_stat']
    p_value = results['p_value']
    assert isinstance(t_stat, (int, float)) and not isinstance(t_stat, bool), "t_stat must be a float"
    assert isinstance(p_value, (int, float)) and not isinstance(p_value, bool), "p_value must be a float"
    assert math.isfinite(t_stat), "t_stat must be finite"
    assert math.isfinite(p_value), "p_value must be finite"
    return results


def independently_calculate_expected():
    frames = [pd.read_csv(path) for path in glob.glob('/home/user/data/*.csv')]
    assert frames, "No input CSV files were found."
    data = pd.concat(frames, ignore_index=True)
    numeric = pd.to_numeric(data['response_time'], errors='coerce')
    data = data.assign(response_time=numeric).dropna(subset=['response_time'])
    server_a = data.loc[data['server'] == 'Server_A', 'response_time']
    server_b = data.loc[data['server'] == 'Server_B', 'response_time']
    return stats.ttest_ind(server_a, server_b)


def validate_png():
    assert os.path.isfile(REPORT_PATH), f"Expected plot file {REPORT_PATH} does not exist. Did the script crash due to the matplotlib backend?"
    assert stat.S_ISREG(os.lstat(REPORT_PATH).st_mode), f"{REPORT_PATH} must be a regular file."
    assert os.path.getsize(REPORT_PATH) > 0, f"Plot file {REPORT_PATH} is empty."
    with open(REPORT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"{REPORT_PATH} is not a PNG file."
    try:
        image = mpimg.imread(REPORT_PATH)
    except Exception as exc:
        pytest.fail(f"{REPORT_PATH} is not a readable PNG image: {exc}")
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, "Plot image has invalid dimensions."
    assert float(image.std()) > 0.005, "Plot image appears blank rather than containing a histogram."


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_pipeline():
    run_pipeline()


def test_results_json_exists_and_correct():
    results = read_results()

    expected_t = -7.067332308696338
    expected_p = 0.00010915609460298918
    t_stat = results['t_stat']
    p_value = results['p_value']

    assert math.isclose(t_stat, expected_t, rel_tol=1e-3), f"t_stat {t_stat} does not match expected value {expected_t}. Was the invalid data dropped correctly?"
    assert math.isclose(p_value, expected_p, rel_tol=1e-3), f"p_value {p_value} does not match expected value {expected_p}. Was the invalid data dropped correctly?"

    derived_t, derived_p = independently_calculate_expected()
    assert math.isclose(t_stat, float(derived_t), rel_tol=1e-10, abs_tol=1e-12)
    assert math.isclose(p_value, float(derived_p), rel_tol=1e-10, abs_tol=1e-12)


def test_report_png_exists():
    validate_png()


def test_pipeline_processes_additional_input_instead_of_using_hardcoded_results():
    challenge_path = f"/home/user/data/.verifier_{secrets.token_hex(12)}.csv"
    offset_a = secrets.randbelow(17)
    offset_b = secrets.randbelow(19)
    rows = [
        'timestamp,server,response_time',
        f'2024-01-01T00:00:00,Server_A,{135 + offset_a}',
        f'2024-01-01T00:01:00,Server_A,{141 + offset_a}',
        f'2024-01-01T00:02:00,Server_A,{148 + offset_a}',
        f'2024-01-01T00:03:00,Server_B,{72 + offset_b}',
        f'2024-01-01T00:04:00,Server_B,{78 + offset_b}',
        f'2024-01-01T00:05:00,Server_B,{83 + offset_b}',
    ]
    with open(challenge_path, 'w') as f:
        f.write('\n'.join(rows) + '\n')
    os.chmod(challenge_path, 0o644)

    try:
        expected_t, expected_p = independently_calculate_expected()
        run_pipeline()
        results = read_results()
        assert math.isclose(results['t_stat'], float(expected_t), rel_tol=1e-10, abs_tol=1e-12), (
            "Pipeline did not calculate the t-statistic from all current CSV inputs."
        )
        assert math.isclose(results['p_value'], float(expected_p), rel_tol=1e-10, abs_tol=1e-12), (
            "Pipeline did not calculate the p-value from all current CSV inputs."
        )
        validate_png()
    finally:
        try:
            os.unlink(challenge_path)
        finally:
            run_pipeline()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
