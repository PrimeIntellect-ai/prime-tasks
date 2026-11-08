#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
import pytest


def test_log_files_deleted():
    assert not os.path.exists('/home/user/app/data/app-01.log'), "app-01.log should have been deleted."
    assert not os.path.exists('/home/user/app/data/app-02.log'), "app-02.log should have been deleted."
    assert os.path.exists('/home/user/app/data/app-03.log'), "app-03.log should NOT have been deleted."


def test_registry_updated():
    registry_path = '/home/user/app/registry.txt'
    assert os.path.exists(registry_path), f"{registry_path} is missing."

    with open(registry_path, 'r') as f:
        lines = f.read().strip().split('\n')

    # Should only contain pending items
    for line in lines:
        if line.strip():
            assert "PROCESSED" not in line, f"Found PROCESSED entry in registry: {line}"

    # app-03.log should still be there
    assert any("app-03.log" in line for line in lines), "app-03.log entry is missing from registry.txt."


def test_cron_job_configured():
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed for the user?")

    # Look for the specific job
    # The requirement is exactly at the top of every hour: 0 * * * *
    expected_command = "/home/user/bin/cleanup.sh"

    found = False
    for line in crontab_output.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if expected_command in line:
            parts = line.split()
            if len(parts) >= 5 and parts[:5] == ['0', '*', '*', '*', '*']:
                found = True
                break

    assert found, f"Could not find cron job with expression '0 * * * *' executing {expected_command}"


def test_resolution_file():
    res_path = '/home/user/resolution.txt'
    assert os.path.exists(res_path), f"{res_path} is missing."

    with open(res_path, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert len(lines) == 2, f"resolution.txt should contain exactly 2 lines, found {len(lines)}."

    assert lines[0] == '/home/user/app/data/app-01.log', f"Line 1 incorrect. Expected '/home/user/app/data/app-01.log', got '{lines[0]}'"
    assert lines[1] == '0 * * * *', f"Line 2 incorrect. Expected '0 * * * *', got '{lines[1]}'"


def test_cleanup_script_functionally_processes_registry():
    cleanup_script = '/home/user/bin/cleanup.sh'
    registry_path = '/home/user/app/registry.txt'
    data_dir = '/home/user/app/data'

    assert os.path.isfile(cleanup_script), f"{cleanup_script} is missing or is not a regular file."
    assert os.access(cleanup_script, os.X_OK), f"{cleanup_script} is not executable."

    token = uuid.uuid4().hex
    processed_names = [f'audit-{token}-one.log', f'audit-{token}-two.log']
    pending_name = f'audit-{token}-pending.log'

    for index, name in enumerate(processed_names, start=1):
        with open(os.path.join(data_dir, name), 'wb') as f:
            f.write(bytes([index]) * (1000 + index))

    pending_path = os.path.join(data_dir, pending_name)
    with open(pending_path, 'wb') as f:
        f.write(b'pending audit data')

    records = [
        f'2099-01-01 | {processed_names[0]} | PROCESSED',
        f'2099-01-02 | {pending_name} | PENDING',
        f'2099-01-03 | {processed_names[1]} | PROCESSED',
    ]
    with open(registry_path, 'a+') as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        if end:
            f.seek(end - 1)
            if f.read(1) != '\n':
                f.write('\n')
        f.write('\n'.join(records) + '\n')

    result = subprocess.run([cleanup_script], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (
        f"cleanup.sh failed with exit code {result.returncode}. "
        f"Output: {result.stdout} {result.stderr}"
    )

    for name in processed_names:
        assert not os.path.exists(os.path.join(data_dir, name)), (
            f"cleanup.sh did not delete dynamically registered processed file {name}."
        )
    assert os.path.exists(pending_path), "cleanup.sh incorrectly deleted a dynamically registered pending file."

    with open(registry_path, 'r') as f:
        remaining_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert records[0] not in remaining_lines, "First dynamic PROCESSED registry entry was not removed."
    assert records[2] not in remaining_lines, "Second dynamic PROCESSED registry entry was not removed."
    assert records[1] in remaining_lines, "Dynamic PENDING registry entry was not preserved."


def test_deploy_script_succeeds():
    deploy_script = '/home/user/deploy.sh'
    assert os.path.exists(deploy_script), f"{deploy_script} is missing."
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable."

    result = subprocess.run([deploy_script], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.sh failed with exit code {result.returncode}. Output: {result.stdout} {result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
