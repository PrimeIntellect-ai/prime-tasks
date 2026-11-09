#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

EXTRACTOR = '/app/bash-ops-etl-0.1.0/bin/extract_valid_metrics.sh'
PIPELINE = '/home/user/run_etl.sh'
OUTPUT = '/home/user/posterior_mean.txt'
RAW_DIR = '/home/user/data/raw_logs'


def posterior(values):
    prior_var = 0.1
    prior_mean = 0.5
    lik_var = 0.05
    n = len(values)
    sum_x = sum(values)
    post_var = 1.0 / ((1.0 / prior_var) + (n / lik_var))
    return post_var * ((prior_mean / prior_var) + (sum_x / lik_var))


def test_posterior_mean_accuracy():
    """Recompute the true posterior from the raw logs and compare the output."""
    n = 0
    sum_x = 0.0
    log_files = glob.glob('/home/user/data/raw_logs/*.csv')
    assert len(log_files) > 0, 'No raw log files found in /home/user/data/raw_logs/'

    for file in log_files:
        with open(file, 'r') as f:
            lines = f.readlines()[1:]
            for line in lines:
                parts = line.strip().split(',')
                if len(parts) >= 3 and parts[1] == 'SUCCESS' and parts[2] != '':
                    n += 1
                    sum_x += float(parts[2])

    prior_var = 0.1
    prior_mean = 0.5
    lik_var = 0.05
    post_var = 1.0 / ((1.0 / prior_var) + (n / lik_var))
    post_mean = post_var * ((prior_mean / prior_var) + (sum_x / lik_var))

    assert os.path.exists(OUTPUT), f'Output file {OUTPUT} does not exist.'
    try:
        with open(OUTPUT, 'r') as f:
            agent_val_str = f.read().strip()
            agent_val = float(agent_val_str)
    except ValueError:
        pytest.fail(f"Failed to parse the contents of {OUTPUT} as a float. Found: '{agent_val_str}'")
    except Exception as e:
        pytest.fail(f'Failed to read {OUTPUT}: {e}')

    err = abs(agent_val - post_mean)
    threshold = 0.001
    assert err <= threshold, (
        f'Posterior mean absolute error {err:.6f} exceeds threshold {threshold}. '
        f'Agent value: {agent_val}, True value: {post_mean}'
    )


def test_extract_script_fixed():
    """Check both the original buggy text and the extractor's actual behavior."""
    assert os.path.exists(EXTRACTOR), f'Script {EXTRACTOR} does not exist.'
    assert os.path.isfile(EXTRACTOR), f'{EXTRACTOR} is not a regular file.'
    assert os.access(EXTRACTOR, os.X_OK), f'Script {EXTRACTOR} is not executable.'

    with open(EXTRACTOR, 'r') as f:
        content = f.read()

    buggy_condition = '&& $3 {'
    assert buggy_condition not in content, (
        f'The script {EXTRACTOR} still contains the buggy awk condition '
        "that drops valid '0.0' values."
    )

    fixture = tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False)
    try:
        fixture.write('experiment_id,run_status,val_loss\n')
        fixture.write('a,SUCCESS,0.0\n')
        fixture.write('b,SUCCESS,0\n')
        fixture.write('c,SUCCESS,0.25\n')
        fixture.write('d,SUCCESS,\n')
        fixture.write('e,FAILED,0.75\n')
        fixture.close()
        result = subprocess.run(
            [EXTRACTOR, fixture.name], text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.splitlines() == ['0.0', '0', '0.25'], (
            'Extractor must retain zero-valued SUCCESS metrics while excluding '
            'empty metrics and failed runs.'
        )
    finally:
        try:
            os.unlink(fixture.name)
        except FileNotFoundError:
            pass


def test_run_etl_exists_is_executable_and_uses_extractor():
    assert os.path.exists(PIPELINE), f'Required pipeline {PIPELINE} does not exist.'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is not a regular file.'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable.'

    pid = os.getpid()
    raw_backup = f'/home/user/data/raw_logs.verifier_backup_{pid}'
    extractor_backup = f'/tmp/extract_valid_metrics.verifier_real_{pid}'
    call_log = f'/tmp/extractor_calls_{pid}.log'
    output_existed = os.path.exists(OUTPUT)
    output_bytes = None
    if output_existed:
        with open(OUTPUT, 'rb') as f:
            output_bytes = f.read()

    if os.path.exists(raw_backup):
        shutil.rmtree(raw_backup)
    shutil.copy2(EXTRACTOR, extractor_backup)

    fixtures = {
        'exp_01.csv': [
            ['experiment_id', 'run_status', 'val_loss'],
            ['a', 'SUCCESS', '0.0'],
            ['b', 'SUCCESS', '0.2'],
            ['c', 'SUCCESS', ''],
            ['d', 'FAILED', '0.9'],
        ],
        'exp_02.csv': [
            ['experiment_id', 'run_status', 'val_loss'],
            ['e', 'SUCCESS', '0.8'],
            ['f', 'FAILED', '0.1'],
        ],
        'exp_03.csv': [
            ['experiment_id', 'run_status', 'val_loss'],
            ['g', 'SUCCESS', ''],
            ['h', 'SUCCESS', '0.5'],
        ],
    }
    canary = 0.137

    try:
        os.rename(RAW_DIR, raw_backup)
        os.mkdir(RAW_DIR)
        for name, rows in fixtures.items():
            with open(os.path.join(RAW_DIR, name), 'w', newline='') as f:
                csv.writer(f, lineterminator='\n').writerows(rows)

        # Instrument the required vendored path. The extra numeric record makes
        # direct recomputation from CSV differ from processing extractor output.
        with open(EXTRACTOR, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write(f'basename -- "$1" >> {call_log!r}\n')
            f.write(f'{extractor_backup!r} "$@"\n')
            f.write(f"printf '%s\\n' '{canary}'\n")
        os.chmod(EXTRACTOR, 0o755)

        result = subprocess.run(
            [PIPELINE], text=True, capture_output=True, timeout=30
        )
        assert result.returncode == 0, (
            f'{PIPELINE} failed with exit code {result.returncode}. '
            f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
        )
        assert os.path.exists(call_log), (
            f'{PIPELINE} did not invoke the required vendored extractor.'
        )
        with open(call_log) as f:
            calls = [line.strip() for line in f if line.strip()]
        for name in fixtures:
            assert name in calls, (
                f'{PIPELINE} did not use the vendored extractor for {name}.'
            )

        extracted = []
        for rows in fixtures.values():
            for row in rows[1:]:
                if row[1] == 'SUCCESS' and row[2] != '':
                    extracted.append(float(row[2]))
            extracted.append(canary)
        expected = posterior(extracted)

        assert os.path.exists(OUTPUT), f'{PIPELINE} did not create {OUTPUT}.'
        with open(OUTPUT) as f:
            text = f.read().strip()
        try:
            actual = float(text)
        except ValueError:
            pytest.fail(f"Failed to parse {OUTPUT} as a float. Found: '{text}'")
        assert abs(actual - expected) <= 0.001, (
            'Pipeline output does not match the posterior calculated from the '
            f'vendored extractor output. Agent value: {actual}, expected: {expected}'
        )
    finally:
        if os.path.exists(EXTRACTOR):
            os.unlink(EXTRACTOR)
        if os.path.exists(extractor_backup):
            shutil.copy2(extractor_backup, EXTRACTOR)
            os.unlink(extractor_backup)
        if os.path.exists(RAW_DIR):
            shutil.rmtree(RAW_DIR)
        if os.path.exists(raw_backup):
            os.rename(raw_backup, RAW_DIR)
        if output_existed:
            with open(OUTPUT, 'wb') as f:
                f.write(output_bytes)
        else:
            try:
                os.unlink(OUTPUT)
            except FileNotFoundError:
                pass
        try:
            os.unlink(call_log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
