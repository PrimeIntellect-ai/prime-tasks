#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import configparser
import json
import os
import runpy
import secrets
import subprocess
from unittest.mock import patch

repo = '/home/user/billing_service'
status_file = '/home/user/billing_status.json'
required_files = ['build.sh', 'setup.py', 'ingest.py', 'config.ini', 'payload.dat']

for name in required_files:
    path = os.path.join(repo, name)
    assert os.path.isfile(path), f'{path} is missing or is not a regular file'
    assert not os.path.islink(path), f'{path} must not be a symbolic link'

# The payload was explicitly required to remain unmodified.
expected_payload = json.dumps({'customer': 'AcmeCorp', 'amount': 10500}).encode('utf-16-le')
with open(os.path.join(repo, 'payload.dat'), 'rb') as f:
    assert f.read() == expected_payload, 'payload.dat was modified'

# Verify the recovered configuration value.
config = configparser.ConfigParser()
assert config.read(os.path.join(repo, 'config.ini')), 'config.ini could not be read'
assert config['DEFAULT'].get('API_SECRET', '') == 'zk99_fX82_legacy_auth_key', 'API_SECRET was not restored correctly'

# Execute setup.py with setup() intercepted so its dependency configuration can
# be checked directly, including the missing-comma failure mode.
captured = []
def capture_setup(*args, **kwargs):
    captured.append((args, kwargs))

old_cwd = os.getcwd()
try:
    os.chdir(repo)
    with patch('setuptools.setup', capture_setup):
        runpy.run_path(os.path.join(repo, 'setup.py'), run_name='__main__')
finally:
    os.chdir(old_cwd)

assert len(captured) == 1, 'setup.py must invoke setuptools.setup exactly once'
requirements = captured[0][1].get('install_requires')
assert isinstance(requirements, (list, tuple)), 'setup.py install_requires must be a dependency list'
assert list(requirements) == ['requests', 'urllib3'], f'Incorrect install_requires: {requirements!r}'

def run_command(command):
    result = subprocess.run(
        command,
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Command {command!r} failed:\n{result.stdout}"

# Run both the demanded build entry point and setup.py's actual build command.
run_command(['bash', 'build.sh'])
run_command(['python3', 'setup.py', 'build'])

def remove_status():
    if os.path.lexists(status_file):
        assert not os.path.isdir(status_file), f'{status_file} is a directory'
        os.unlink(status_file)

def run_ingest_and_check(expected):
    remove_status()
    run_command(['python3', 'ingest.py'])
    assert os.path.isfile(status_file), 'ingest.py did not generate billing_status.json'
    assert not os.path.islink(status_file), 'billing_status.json must not be a symbolic link'
    try:
        with open(status_file, 'r', encoding='utf-8') as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError('billing_status.json is not valid JSON') from exc
    assert actual == expected, f'Incorrect billing report. Found: {actual!r}'

# Exercise ingest.py with unpredictable UTF-16LE input and configuration so a
# prewritten hardcoded report cannot pass.
config_path = os.path.join(repo, 'config.ini')
payload_path = os.path.join(repo, 'payload.dat')
with open(config_path, 'rb') as f:
    saved_config = f.read()
with open(payload_path, 'rb') as f:
    saved_payload = f.read()

probe_secret = 'probe_' + secrets.token_hex(16)
probe_customer = 'Verifier-' + secrets.token_hex(8) + '-\u2603'
probe_amount = int.from_bytes(secrets.token_bytes(4), 'big')
probe_data = {'customer': probe_customer, 'amount': probe_amount}

try:
    with open(config_path, 'w', encoding='utf-8') as f:
        f.write('[DEFAULT]\nAPI_SECRET=' + probe_secret + '\n')
    with open(payload_path, 'wb') as f:
        f.write(json.dumps(probe_data, ensure_ascii=False).encode('utf-16-le'))

    run_ingest_and_check({
        'status': 'success',
        'secret_used': probe_secret,
        'customer': probe_customer,
        'amount': probe_amount,
    })
finally:
    with open(config_path, 'wb') as f:
        f.write(saved_config)
    with open(payload_path, 'wb') as f:
        f.write(saved_payload)

# Re-run against the real pending payload and retain the original exact final
# report assertion.
run_ingest_and_check({
    'status': 'success',
    'secret_used': 'zk99_fX82_legacy_auth_key',
    'customer': 'AcmeCorp',
    'amount': 10500,
})
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
