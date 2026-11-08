#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
from pathlib import Path

import pytest


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def test_submitted_workflow_behavior():
    legacy = Path('/home/user/legacy_metrics_cli')
    fetch = Path('/home/user/fetch.exp')
    aggregator = Path('/home/user/aggregator')
    pipeline = Path('/home/user/run_pipeline.sh')
    output = Path('/home/user/metrics_out.json')

    for path in (fetch, aggregator, pipeline):
        assert path.is_file(), f'{path} does not exist.'
    assert os.access(aggregator, os.X_OK), f'{aggregator} is not executable.'
    assert os.access(pipeline, os.X_OK), f'{pipeline} is not executable.'

    rng = random.SystemRandom()
    challenge_values = [rng.randint(301, 9000) for _ in range(4)]
    challenge_average = sum(challenge_values) // len(challenge_values)
    auth_marker = Path('/tmp/legacy_auth_succeeded')
    legacy_backup = Path('/tmp/legacy_metrics_cli.original')
    shutil.copy2(legacy, legacy_backup)

    challenge_lines = '\n'.join(f'echo "MEM_MB={value}"' for value in challenge_values)
    legacy.write_text(
        '#!/bin/bash\n'
        'read -p "Username: " user\n'
        '[ "$user" = "admin" ] || { echo "Access Denied"; exit 1; }\n'
        'read -p "PIN: " pin\n'
        '[ "$pin" = "1234" ] || { echo "Access Denied"; exit 1; }\n'
        f'touch {auth_marker}\n'
        'echo "--- METRICS START ---"\n'
        f'{challenge_lines}\n'
        'echo "--- METRICS END ---"\n'
    )
    legacy.chmod(0o755)

    try:
        auth_marker.unlink(missing_ok=True)
        fetched = run(['expect', str(fetch)])
        assert fetched.returncode == 0, fetched.stderr
        assert auth_marker.exists(), 'fetch.exp did not authenticate to legacy_metrics_cli'
        for value in challenge_values:
            assert f'MEM_MB={value}' in fetched.stdout, (
                f'fetch.exp did not print the CLI output; stdout was: {fetched.stdout!r}'
            )

        independent_values = [rng.randint(100, 12000) for _ in range(5)]
        raw = '\n'.join(
            ['CPU_LOAD=17']
            + [f'MEM_MB={value}' for value in independent_values]
            + ['DISK_IO=42']
        ) + '\n'
        aggregated = run([str(aggregator)], input=raw)
        expected = '{"avg_mem": ' + str(sum(independent_values) // len(independent_values)) + '}'
        assert aggregated.returncode == 0, aggregated.stderr
        assert aggregated.stdout.strip() == expected, (
            f'aggregator output must be exactly {expected!r}, got {aggregated.stdout!r}'
        )

        fetch_backup = Path('/tmp/submitted_fetch.exp')
        aggregator_backup = Path('/tmp/submitted_aggregator')
        fetch_marker = Path('/tmp/pipeline_called_fetch')
        aggregator_marker = Path('/tmp/pipeline_called_aggregator')
        shutil.copy2(fetch, fetch_backup)
        shutil.copy2(aggregator, aggregator_backup)
        fetch_marker.unlink(missing_ok=True)
        aggregator_marker.unlink(missing_ok=True)

        fetch.write_text(
            '#!/usr/bin/expect -f\n'
            f'set fd [open "{fetch_marker}" w]\n'
            'puts $fd "called"\n'
            'close $fd\n'
            'set timeout 15\n'
            f'spawn -noecho expect "{fetch_backup}"\n'
            'expect {\n'
            '  eof { catch wait result; exit [lindex $result 3] }\n'
            '  timeout { exit 124 }\n'
            '}\n'
        )
        fetch.chmod(0o755)
        aggregator.write_text(
            '#!/bin/bash\n'
            f'echo called > "{aggregator_marker}"\n'
            f'exec "{aggregator_backup}"\n'
        )
        aggregator.chmod(0o755)

        try:
            auth_marker.unlink(missing_ok=True)
            output.unlink(missing_ok=True)
            piped = run([str(pipeline)])
            assert piped.returncode == 0, piped.stderr
            assert fetch_marker.exists(), 'run_pipeline.sh did not run /home/user/fetch.exp'
            assert aggregator_marker.exists(), 'run_pipeline.sh did not run /home/user/aggregator'
            assert auth_marker.exists(), 'the pipeline did not authenticate to the legacy CLI'
            assert output.is_file(), 'run_pipeline.sh did not create metrics_out.json'
            expected_pipeline = '{"avg_mem": ' + str(challenge_average) + '}'
            assert output.read_text().strip() == expected_pipeline, (
                f'pipeline output must be exactly {expected_pipeline!r}'
            )
        finally:
            os.replace(fetch_backup, fetch)
            os.replace(aggregator_backup, aggregator)
    finally:
        os.replace(legacy_backup, legacy)

    output.unlink(missing_ok=True)
    final_run = run([str(pipeline)])
    assert final_run.returncode == 0, final_run.stderr
    assert output.is_file(), 'pipeline did not create metrics_out.json with the supplied CLI'
    assert output.read_text().strip() == '{"avg_mem": 1500}'


def test_metrics_out_json():
    out_file = '/home/user/metrics_out.json'
    assert os.path.isfile(out_file), f'{out_file} does not exist. Did you run the pipeline script?'

    with open(out_file, 'r') as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f'Content of {out_file} is not valid JSON: {content}')

    assert 'avg_mem' in data, f"JSON output missing 'avg_mem' key: {data}"
    assert data['avg_mem'] == 1500, f"Expected avg_mem to be 1500, got {data['avg_mem']}"


def test_dashboard_conf_content():
    conf_file = '/home/user/dashboard.conf'
    assert os.path.isfile(conf_file), f'{conf_file} does not exist.'

    with open(conf_file, 'r') as f:
        content = f.read()

    assert 'port=9090' in content, f"{conf_file} is missing 'port=9090'"
    assert 'mode=production' in content, f"{conf_file} is missing 'mode=production'"


def test_dashboard_conf_acl():
    conf_file = '/home/user/dashboard.conf'
    assert os.path.isfile(conf_file), f'{conf_file} does not exist.'

    result = subprocess.run(['getfacl', conf_file], capture_output=True, text=True)
    assert result.returncode == 0, f'Failed to run getfacl on {conf_file}'

    acl_lines = result.stdout.splitlines()
    expected_acl = 'user:nobody:r--'
    has_acl = any(line.startswith(expected_acl) for line in acl_lines)
    assert has_acl, f"ACL for 'nobody' is not set to read-only. getfacl output:\n{result.stdout}"


def test_tunnel_sh_content():
    tunnel_file = '/home/user/tunnel.sh'
    assert os.path.isfile(tunnel_file), f'{tunnel_file} does not exist.'

    with open(tunnel_file, 'r') as f:
        content = f.read()

    assert '-L' in content and '9090:localhost:8080' in content.replace(' ', ''), 'tunnel.sh missing correct -L port forwarding configuration'
    assert '-i' in content and '/home/user/.ssh/dashboard_key' in content, 'tunnel.sh missing correct -i identity file configuration'
    assert 'backend-server' in content, "tunnel.sh missing 'backend-server'"
    assert '-f' in content.split(), "tunnel.sh missing '-f' flag to run in background"
    assert '-N' in content.split(), "tunnel.sh missing '-N' flag to not execute a remote command"


def test_pipeline_script_exists_and_executable():
    pipeline_file = '/home/user/run_pipeline.sh'
    assert os.path.isfile(pipeline_file), f'{pipeline_file} does not exist.'
    assert os.access(pipeline_file, os.X_OK), f'{pipeline_file} is not executable.'


def test_aggregator_compiled():
    source = '/home/user/aggregator.cpp'
    aggregator_bin = '/home/user/aggregator'
    assert os.path.isfile(source), f'{source} does not exist.'
    assert os.path.isfile(aggregator_bin), f'{aggregator_bin} does not exist. Did you compile the C++ program?'
    assert os.access(aggregator_bin, os.X_OK), f'{aggregator_bin} is not executable.'
    with open(aggregator_bin, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{aggregator_bin} is not a compiled executable.'


def test_fetch_exp_exists_and_executable():
    fetch_file = '/home/user/fetch.exp'
    assert os.path.isfile(fetch_file), f'{fetch_file} does not exist.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
