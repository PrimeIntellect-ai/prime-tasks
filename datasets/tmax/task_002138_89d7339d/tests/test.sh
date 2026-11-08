#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = '/home/user/config_gate.py'
CLEAN_DIR = '/app/tests/clean'
EVIL_DIR = '/app/tests/evil'
LEGACY_PATH = '/app/legacy_checker'
ALLOWED_ACTION = re.compile(r'^[A-Za-z0-9 _./-]+$')
VALID_NODE = re.compile(r'^(prod|dev|staging)-[a-z]{2,4}-[0-9]{2}$')


def run_gate(path, timeout=2):
    return subprocess.run(
        ['python3', SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    ).returncode


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f'The script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'


def test_clean_corpus():
    assert os.path.exists(CLEAN_DIR), f'Clean corpus directory {CLEAN_DIR} is missing.'
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.cfg')]
    assert len(clean_files) > 0, 'No clean configuration files found.'

    failed_files = []
    for cfg_file in clean_files:
        result = subprocess.run(['python3', SCRIPT_PATH, cfg_file], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(cfg_file))

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0). Offending files: {", ".join(failed_files)}')


def test_evil_corpus():
    assert os.path.exists(EVIL_DIR), f'Evil corpus directory {EVIL_DIR} is missing.'
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.cfg')]
    assert len(evil_files) > 0, 'No evil configuration files found.'

    failed_files = []
    for cfg_file in evil_files:
        result = subprocess.run(['python3', SCRIPT_PATH, cfg_file], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(cfg_file))

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(evil_files)} evil files bypassed validation (exit code == 0). Offending files: {", ".join(failed_files)}')


def expected(timeout, retries, node, action):
    return (
        10 <= timeout <= 120
        and 1 <= retries <= 3
        and VALID_NODE.fullmatch(node) is not None
        and ALLOWED_ACTION.fullmatch(action) is not None
    )


def write_cfg(path, timeout, retries, node, action, rng):
    entries = [
        ('Timeout', str(timeout)),
        ('MaxRetries', str(retries)),
        ('NodeName', node),
        ('ActionCmd', action),
    ]
    rng.shuffle(entries)
    with open(path, 'w', encoding='utf-8') as f:
        for key, value in entries:
            left = ' ' * rng.randrange(0, 4)
            middle_left = ' ' * rng.randrange(0, 4)
            middle_right = ' ' * rng.randrange(0, 4)
            right = ' ' * rng.randrange(0, 4)
            f.write(f'{left}{key}{middle_left}:{middle_right}{value}{right}\n')


def test_dynamic_adversarial_corpus_and_independence():
    seed = int.from_bytes(secrets.token_bytes(16), 'big')
    rng = random.Random(seed)
    cases = []

    valid_nodes = [
        'prod-ab-00', 'prod-abcd-99', 'dev-xy-17',
        'staging-abc-42', 'staging-wxyz-08',
    ]
    valid_actions = [
        'run_script.sh', '/opt/tools/deploy-v2.1 --force_now',
        'python3 app/main.py', 'service_name restart', './bin/check-status',
    ]

    for timeout in (10, 11, 37, 119, 120):
        for retries in (1, 2, 3):
            cases.append((timeout, retries, rng.choice(valid_nodes), rng.choice(valid_actions)))

    for timeout in (-20, 0, 9, 121, 150):
        cases.append((timeout, 2, rng.choice(valid_nodes), rng.choice(valid_actions)))
    for retries in (-1, 0, 4, 5):
        cases.append((30, retries, rng.choice(valid_nodes), rng.choice(valid_actions)))

    invalid_nodes = [
        'prod-a-12', 'prod-abcde-12', 'qa-abc-12', 'Prod-abc-12',
        'prod-ABC-12', 'prod-abc-1', 'prod-abc-123', 'prod_abc_12',
        'prod-ab-0x', 'invalid-name',
    ]
    for node in invalid_nodes:
        cases.append((30, 2, node, rng.choice(valid_actions)))

    illegal_chars = [c for c in string.punctuation if c not in '-_/.']
    illegal_chars += ['\t', 'é', '中']
    for bad in illegal_chars:
        cases.append((30, 2, rng.choice(valid_nodes), f'safe{bad}command'))

    prefixes = ('prod', 'dev', 'staging')
    for _ in range(100):
        timeout = rng.randrange(-30, 161)
        retries = rng.randrange(-2, 7)
        if rng.random() < 0.65:
            letters = ''.join(rng.choice(string.ascii_lowercase) for _ in range(rng.randrange(2, 5)))
            node = f'{rng.choice(prefixes)}-{letters}-{rng.randrange(100):02d}'
        else:
            node = rng.choice(invalid_nodes)
        action = rng.choice(valid_actions)
        if rng.random() < 0.45:
            bad = rng.choice(illegal_chars)
            action = action + bad + 'payload'
        cases.append((timeout, retries, node, action))

    legacy_data = None
    legacy_mode = None
    if os.path.exists(LEGACY_PATH):
        legacy_mode = os.stat(LEGACY_PATH).st_mode
        with open(LEGACY_PATH, 'rb') as f:
            legacy_data = f.read()
        os.unlink(LEGACY_PATH)

    try:
        with tempfile.TemporaryDirectory(prefix='cfg-gate-adversarial-') as td:
            rng.shuffle(cases)
            valid_seen = invalid_seen = 0
            for values in cases:
                filename = secrets.token_hex(12) + '.cfg'
                path = os.path.join(td, filename)
                write_cfg(path, *values, rng)
                want_ok = expected(*values)
                valid_seen += int(want_ok)
                invalid_seen += int(not want_ok)
                rc = run_gate(path)
                wanted_rc = 0 if want_ok else 1
                assert rc == wanted_rc, f'classification mismatch for randomized case {values!r}: got {rc}, expected {wanted_rc}'

            assert valid_seen >= 10 and invalid_seen >= 30

            base = {
                'Timeout': '30',
                'MaxRetries': '2',
                'NodeName': 'dev-ab-12',
                'ActionCmd': 'bin/run-safe.sh',
            }
            for missing in base:
                path = os.path.join(td, secrets.token_hex(12) + '.cfg')
                with open(path, 'w', encoding='utf-8') as f:
                    for key, value in base.items():
                        if key != missing:
                            f.write(f'{key}: {value}\n')
                assert run_gate(path) == 1, f'missing {missing} was accepted'

            malformed = os.path.join(td, secrets.token_hex(12) + '.cfg')
            with open(malformed, 'w', encoding='utf-8') as f:
                f.write('Timeout: not-a-number\nMaxRetries: 2\nNodeName: dev-ab-12\nActionCmd: run.sh\n')
            assert run_gate(malformed) == 1

            assert run_gate(os.path.join(td, 'does-not-exist.cfg')) == 1
            no_arg = subprocess.run(['python3', SCRIPT_PATH], capture_output=True, timeout=2)
            extra_arg = subprocess.run(['python3', SCRIPT_PATH, malformed, malformed], capture_output=True, timeout=2)
            assert no_arg.returncode == 1
            assert extra_arg.returncode == 1
    finally:
        if legacy_data is not None:
            with open(LEGACY_PATH, 'wb') as f:
                f.write(legacy_data)
            os.chmod(LEGACY_PATH, legacy_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
