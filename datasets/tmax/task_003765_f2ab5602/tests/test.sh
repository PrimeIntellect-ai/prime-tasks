#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_pipeline_behavior.py
import json
import os
import random
import re
import shutil
import subprocess
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_configs'
QUARANTINE = HOME / 'quarantine'
OUTPUT = HOME / 'reconstructed_configs'
LOG = HOME / 'pipeline.log'
RUNNER = HOME / 'run_pipeline.sh'
KEYS = {'max_memory', 'timeout', 'log_level', 'feature_flags'}
LEVELS = {'DEBUG', 'INFO', 'WARN', 'ERROR'}


def reset_fixture(files):
    for directory in (RAW, QUARANTINE, OUTPUT):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True, mode=0o777)
        directory.chmod(0o777)
    if LOG.exists():
        LOG.unlink()

    invalid_bytes = {}
    for name, value in files.items():
        path = RAW / name
        if isinstance(value, bytes):
            path.write_bytes(value)
            invalid_bytes[name] = value
        else:
            path.write_text(json.dumps(value) + '\n')
        path.chmod(0o666)
    return invalid_bytes


def run_pipeline():
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'bash', str(RUNNER)],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, (
        f'run_pipeline.sh failed with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def assert_complete_output(expected, invalid, expected_imputations):
    assert OUTPUT.is_dir(), 'reconstructed_configs directory is missing'
    assert QUARANTINE.is_dir(), 'quarantine directory is missing'

    assert sorted(p.name for p in OUTPUT.iterdir()) == sorted(expected), (
        'Reconstructed output must contain exactly the valid input filenames'
    )
    assert sorted(p.name for p in QUARANTINE.iterdir()) == sorted(invalid), (
        'Quarantine must contain exactly the invalid input filenames'
    )

    for name, original_bytes in invalid.items():
        quarantined = QUARANTINE / name
        assert quarantined.is_file(), f'Expected invalid file to be moved to {quarantined}'
        assert not (RAW / name).exists(), f'{name} was copied, not moved, to quarantine'
        assert quarantined.read_bytes() == original_bytes, f'{name} changed while quarantined'

    for name, wanted in expected.items():
        path = OUTPUT / name
        assert path.is_file(), f'Reconstructed file {path} is missing.'
        with path.open() as f:
            actual = json.load(f)
        assert isinstance(actual, dict), f'{name} must contain a JSON object'
        assert set(actual) == KEYS, f'{name} does not have exactly the required schema'
        assert actual == wanted, f'{name} was not completely reconstructed correctly'
        assert type(actual['max_memory']) is int, f'{name}: max_memory must be an integer'
        assert type(actual['timeout']) is float, f'{name}: timeout must be a float'
        assert type(actual['log_level']) is str and actual['log_level'] in LEVELS
        assert type(actual['feature_flags']) is dict
        assert all(value is not None for value in actual.values()), f'{name} still contains nulls'

    assert LOG.is_file(), f'Log file {LOG} is missing.'
    log_content = LOG.read_text()
    expected_logs = [
        f'[STAGE: VALIDATION] Quarantined {len(invalid)} invalid files.',
        f'[STAGE: IMPUTATION] Imputed {expected_imputations} missing values across all files.',
        f'[STAGE: LOAD] Successfully wrote {len(expected)} reconstructed configs.'
    ]
    for message in expected_logs:
        assert message in log_content, f"Expected log string '{message}' not found in {LOG}"


def test_pipeline_end_to_end():
    assert RUNNER.is_file(), '/home/user/run_pipeline.sh is missing'
    runner_text = RUNNER.read_text(errors='replace')
    assert re.search(r'python(?:3)?', runner_text), 'run_pipeline.sh must run Python'
    assert '.py' in runner_text, 'run_pipeline.sh must invoke a Python pipeline script'
    python_files = [
        p for p in HOME.rglob('*.py')
        if RAW not in p.parents and QUARANTINE not in p.parents and OUTPUT not in p.parents
    ]
    assert any(p.is_file() for p in python_files), 'The required Python pipeline script is missing'

    # Preserve and strengthen all checks against the original fixture.
    static_files = {
        'config_10.json': {'max_memory': 1024, 'timeout': 1.0, 'log_level': 'INFO', 'feature_flags': {}},
        'config_20.json': {'max_memory': None, 'timeout': 2.0, 'log_level': None, 'feature_flags': {}},
        'config_25.json': b'{THIS IS INVALID JSON DATA\n',
        'config_30.json': {'max_memory': 3072, 'timeout': None, 'log_level': 'DEBUG', 'feature_flags': {}},
        'config_40.json': {'max_memory': 4096, 'timeout': 4.0, 'log_level': None, 'feature_flags': {}},
        'config_50.json': {'max_memory': 5120, 'timeout': 5.0, 'log_level': 'WARN', 'feature_flags': {}}
    }
    static_expected = {
        'config_10.json': {'max_memory': 1024, 'timeout': 1.0, 'log_level': 'INFO', 'feature_flags': {}},
        'config_20.json': {'max_memory': 2048, 'timeout': 2.0, 'log_level': 'INFO', 'feature_flags': {}},
        'config_30.json': {'max_memory': 3072, 'timeout': 3.0, 'log_level': 'DEBUG', 'feature_flags': {}},
        'config_40.json': {'max_memory': 4096, 'timeout': 4.0, 'log_level': 'DEBUG', 'feature_flags': {}},
        'config_50.json': {'max_memory': 5120, 'timeout': 5.0, 'log_level': 'WARN', 'feature_flags': {}}
    }
    invalid = reset_fixture(static_files)
    run_pipeline()
    assert_complete_output(static_expected, invalid, 4)

    # Run the submitted orchestration again on unpredictable data so fixed files
    # and prewritten logs cannot satisfy the verifier.
    offset = random.SystemRandom().randint(1000, 9000)
    seed = random.SystemRandom().randint(1, 50)
    token = os.urandom(8).hex()
    t0, t1, t2, t3 = offset, offset + 10, offset + 20, offset + 40
    dynamic_files = {
        f'config_{t0}.json': {
            'max_memory': 1000 + seed * 100, 'timeout': float(seed) + 0.25,
            'log_level': None, 'feature_flags': {'token': token, 'first': True}},
        f'config_{t1}.json': {
            'max_memory': None, 'timeout': float(seed) + 1.25,
            'log_level': 'ERROR', 'feature_flags': {'nested': {'value': seed}}},
        f'config_{t2}.json': {
            'max_memory': 3000 + seed * 100, 'timeout': None,
            'log_level': None, 'feature_flags': {'items': [token, seed]}},
        f'config_{t3}.json': {
            'max_memory': 5000 + seed * 100, 'timeout': float(seed) + 4.25,
            'log_level': 'WARN', 'feature_flags': {'last': False}},
        f'config_{offset + 13}.json': b'not json: ' + os.urandom(12) + b'\n',
        f'config_{offset + 31}.json': b'{"broken": [1, 2,}\n'
    }
    dynamic_expected = {
        f'config_{t0}.json': {
            'max_memory': 1000 + seed * 100, 'timeout': float(seed) + 0.25,
            'log_level': 'INFO', 'feature_flags': {'token': token, 'first': True}},
        f'config_{t1}.json': {
            'max_memory': 2000 + seed * 100, 'timeout': float(seed) + 1.25,
            'log_level': 'ERROR', 'feature_flags': {'nested': {'value': seed}}},
        f'config_{t2}.json': {
            'max_memory': 3000 + seed * 100, 'timeout': float(seed) + 2.25,
            'log_level': 'ERROR', 'feature_flags': {'items': [token, seed]}},
        f'config_{t3}.json': {
            'max_memory': 5000 + seed * 100, 'timeout': float(seed) + 4.25,
            'log_level': 'WARN', 'feature_flags': {'last': False}}
    }
    invalid = reset_fixture(dynamic_files)
    run_pipeline()
    assert_complete_output(dynamic_expected, invalid, 4)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_pipeline_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
