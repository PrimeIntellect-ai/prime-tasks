#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import glob
import hashlib
import math
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest

HOME = '/home/user'
SCRIPT = f'{HOME}/process.sh'
DATA = f'{HOME}/data'
PARAMS = f'{HOME}/model_params.txt'
METRICS = f'{HOME}/metrics.txt'
REPRO = f'{HOME}/reproducibility.txt'

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_NONBLOCK = 0x00000800
IN_CLOEXEC = 0x00080000


def expected_metrics():
    assert os.path.isfile(PARAMS), f'Missing {PARAMS}'
    params = {}
    with open(PARAMS) as f:
        for raw in f:
            if '=' in raw:
                key, value = raw.strip().split('=', 1)
                params[key] = float(value)

    w_a = params.get('weight_A', 1.5)
    w_b = params.get('weight_B', -0.5)
    bias = params.get('bias', 2.0)
    predictions = []
    actuals = []

    files = glob.glob(f'{DATA}/*.csv')
    assert files, f'No CSV files found in {DATA}'
    for filename in files:
        with open(filename) as f:
            next(f, None)
            for raw in f:
                if not raw.strip():
                    continue
                fields = raw.strip().split(',')
                a, b, actual = map(float, fields[:3])
                predictions.append(a * w_a + b * w_b + bias)
                actuals.append(actual)

    n = len(predictions)
    assert n >= 2, 'Not enough data to calculate statistics'
    mean_p = sum(predictions) / n
    mean_a = sum(actuals) / n
    cross = sum((p - mean_p) * (a - mean_a)
                for p, a in zip(predictions, actuals))
    ss_p = sum((p - mean_p) ** 2 for p in predictions)
    ss_a = sum((a - mean_a) ** 2 for a in actuals)
    assert ss_p > 0 and ss_a > 0, 'Degenerate test data'

    # The instruction does not specify sample versus population covariance.
    sample_covariance = cross / (n - 1)
    population_covariance = cross / n
    correlation = cross / math.sqrt(ss_p * ss_a)
    return sample_covariance, population_covariance, correlation


def remove_outputs():
    for path in (METRICS, REPRO):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def run_and_count_metric_publications():
    remove_outputs()
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
    assert fd >= 0, f'inotify_init1 failed: errno {ctypes.get_errno()}'
    try:
        wd = libc.inotify_add_watch(fd, HOME.encode(), IN_CLOSE_WRITE | IN_MOVED_TO)
        assert wd >= 0, f'inotify_add_watch failed: errno {ctypes.get_errno()}'
        try:
            result = subprocess.run(
                [SCRIPT], cwd=HOME, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=30
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f'{SCRIPT} timed out')

        assert result.returncode == 0, (
            f'{SCRIPT} exited with {result.returncode}\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )

        event_data = bytearray()
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                event_data.extend(chunk)
            except BlockingIOError:
                break
            except OSError as exc:
                if exc.errno == errno.EAGAIN:
                    break
                raise

        publications = 0
        offset = 0
        header_size = struct.calcsize('iIII')
        while offset + header_size <= len(event_data):
            _, mask, _, name_len = struct.unpack_from('iIII', event_data, offset)
            offset += header_size
            name = bytes(event_data[offset:offset + name_len]).split(b'\0', 1)[0]
            offset += name_len
            if name == b'metrics.txt' and mask & (IN_CLOSE_WRITE | IN_MOVED_TO):
                publications += 1

        assert publications >= 2, (
            'process.sh must run and save the inference/statistics pipeline '
            f'twice; observed only {publications} completed metrics.txt publication(s)'
        )
    finally:
        os.close(fd)


def validate_outputs():
    assert os.path.isfile(METRICS), f'Metrics file {METRICS} does not exist'
    assert os.path.isfile(REPRO), f'Reproducibility file {REPRO} does not exist'

    sample_cov, population_cov, corr = expected_metrics()
    with open(METRICS, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f'{METRICS} must contain exactly two lines; got {lines!r}'
    valid_covariances = {
        f'Covariance: {sample_cov:.4f}',
        f'Covariance: {population_cov:.4f}',
    }
    assert lines[0] in valid_covariances, (
        f'Expected one of {sorted(valid_covariances)!r}; got {lines[0]!r}'
    )
    expected_correlation = f'Correlation: {corr:.4f}'
    assert lines[1] == expected_correlation, (
        f'Expected {expected_correlation!r}; got {lines[1]!r}'
    )

    with open(METRICS, 'rb') as f:
        expected_md5 = hashlib.md5(f.read()).hexdigest()
    with open(REPRO, 'r') as f:
        repro = f.read().strip()

    match = re.fullmatch(r'([0-9a-fA-F]{32})[ \t]+\*?(.+)', repro)
    assert match, f'{REPRO} is not a single standard md5sum output line: {repro!r}'
    assert match.group(1).lower() == expected_md5, (
        f'MD5 hash {expected_md5} not found in {REPRO}. Content: {repro!r}'
    )
    assert os.path.basename(match.group(2).strip()) == 'metrics.txt', (
        f'{REPRO} must name metrics.txt. Content: {repro!r}'
    )
    return open(METRICS, 'rb').read(), open(REPRO, 'rb').read()


def install_unpredictable_challenge():
    rng = secrets.SystemRandom()
    os.makedirs(DATA, exist_ok=True)
    for entry in os.listdir(DATA):
        path = os.path.join(DATA, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    w_a = rng.uniform(-3.5, -0.7)
    w_b = rng.uniform(0.4, 2.8)
    bias = rng.uniform(-4.0, 4.0)
    with open(PARAMS, 'w') as f:
        f.write(f'weight_A={w_a:.8f}\nweight_B={w_b:.8f}\nbias={bias:.8f}\n')

    for batch, count in ((1, 11), (2, 8)):
        with open(f'{DATA}/challenge_{batch}.csv', 'w') as f:
            f.write('sensor_A,sensor_B,actual_output\n')
            for index in range(count):
                a = rng.uniform(-8.0, 13.0)
                b = rng.uniform(-5.0, 11.0)
                actual = 1.2 * a - 0.35 * b + (index % 4) * 0.73 + rng.uniform(-0.2, 0.2)
                f.write(f'{a:.7f},{b:.7f},{actual:.7f}\n')


def test_process_pipeline_and_final_state():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable'

    backup_root = tempfile.mkdtemp(prefix='pipeline-backup-')
    backup_data = os.path.join(backup_root, 'data')
    params_existed = os.path.isfile(PARAMS)
    if os.path.isdir(DATA):
        shutil.copytree(DATA, backup_data)
    if params_existed:
        shutil.copy2(PARAMS, os.path.join(backup_root, 'model_params.txt'))

    try:
        install_unpredictable_challenge()
        run_and_count_metric_publications()
        first_metrics, first_repro = validate_outputs()
        run_and_count_metric_publications()
        second_metrics, second_repro = validate_outputs()
        assert first_metrics == second_metrics, 'Repeated executions produced different metrics.txt files'
        assert first_repro == second_repro, 'Repeated executions produced different reproducibility.txt files'
    finally:
        if os.path.lexists(DATA):
            shutil.rmtree(DATA)
        if os.path.isdir(backup_data):
            shutil.copytree(backup_data, DATA)
        else:
            os.makedirs(DATA, exist_ok=True)
        if os.path.lexists(PARAMS):
            os.unlink(PARAMS)
        if params_existed:
            shutil.copy2(os.path.join(backup_root, 'model_params.txt'), PARAMS)
        shutil.rmtree(backup_root)

    # Preserve the original final-state assertions on the restored task inputs.
    run_and_count_metric_publications()
    validate_outputs()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
