#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess

FSTAB = '/home/user/edge_fstab'
LOGGER = '/home/user/sensor_logger.py'
DEPLOY = '/home/user/deploy.sh'
STATUS = '/home/user/deploy_status.log'
EXPECTED_LINE = 'UUID=EDGE_SENSOR_DRIVE /home/user/sensor_mnt ext4 defaults,noatime 0 2'


def run_as_user(command, timeout=20):
    return subprocess.run(
        ['runuser', '-u', 'user', '--'] + command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def write_fstab(mount_point):
    with open(FSTAB, 'w') as f:
        f.write(f'UUID=EDGE_SENSOR_DRIVE {mount_point} ext4 defaults,noatime 0 2\n')


def assert_file_text(path, expected):
    assert os.path.exists(path), f'{path} does not exist.'
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == expected, f"Expected '{expected}' in {path}, got '{content}'."


def test_complete_deployment_behavior():
    # Preserve all original existence, regular-file, executable, and final-state checks.
    assert os.path.exists(FSTAB), f'File {FSTAB} does not exist.'
    with open(FSTAB, 'r') as f:
        fstab_content = f.read()
    assert fstab_content.splitlines() == [EXPECTED_LINE], \
        f'File {FSTAB} must contain exactly the required mount configuration line.'

    assert os.path.exists(LOGGER), f'File {LOGGER} does not exist.'
    assert os.path.isfile(LOGGER), f'{LOGGER} is not a regular file.'
    assert os.path.exists(DEPLOY), f'File {DEPLOY} does not exist.'
    assert os.path.isfile(DEPLOY), f'{DEPLOY} is not a regular file.'
    assert os.access(DEPLOY, os.X_OK), f'File {DEPLOY} is not executable.'

    assert_file_text('/home/user/sensor_mnt/telemetry.log', 'EDGE_DATA_ACTIVE')
    assert_file_text(STATUS, 'DEPLOYMENT_SUCCESS')

    with open(LOGGER, 'rb') as f:
        original_logger = f.read()
    logger_mode = stat.S_IMODE(os.stat(LOGGER).st_mode)
    original_fstab = fstab_content

    token = secrets.token_hex(12)
    logger_mount = f'/home/user/logger_test_{token}'
    deploy_mount = f'/home/user/deploy_test_{token}'
    failure_mount = f'/home/user/failure_test_{token}'
    marker = f'/home/user/.deploy_marker_{token}'

    try:
        # Execute the submitted Python program against a verifier-chosen mount point.
        os.mkdir(logger_mount)
        write_fstab(logger_mount)
        result = run_as_user(['python3', LOGGER])
        assert result.returncode == 0, \
            f'sensor_logger.py failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        assert_file_text(os.path.join(logger_mount, 'telemetry.log'), 'EDGE_DATA_ACTIVE')

        # Replace the logger temporarily with a probe. This proves deploy.sh reads the
        # dynamic mount, creates it, and executes /home/user/sensor_logger.py.
        probe = f'''#!/usr/bin/env python3
import os
import sys
mount = None
with open({FSTAB!r}, 'r') as f:
    for line in f:
        fields = line.split()
        if fields and fields[0] == "UUID=EDGE_SENSOR_DRIVE":
            mount = fields[1]
            break
if not mount or not os.path.isdir(mount):
    sys.exit(23)
with open({marker!r}, 'w') as f:
    f.write("executed")
with open(os.path.join(mount, "telemetry.log"), "w") as f:
    f.write("EDGE_DATA_ACTIVE")
'''
        with open(LOGGER, 'w') as f:
            f.write(probe)
        os.chmod(LOGGER, 0o755)
        write_fstab(deploy_mount)
        if os.path.exists(STATUS):
            os.remove(STATUS)
        result = run_as_user([DEPLOY])
        assert result.returncode == 0, \
            f'deploy.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        assert os.path.isdir(deploy_mount), 'deploy.sh did not create the parsed mount directory.'
        assert_file_text(marker, 'executed')
        assert_file_text(os.path.join(deploy_mount, 'telemetry.log'), 'EDGE_DATA_ACTIVE')
        assert_file_text(STATUS, 'DEPLOYMENT_SUCCESS')

        # Verify the required failure status when the Python application fails and
        # does not create telemetry.log.
        failure_probe = f'''#!/usr/bin/env python3
with open({marker!r}, "w") as f:
    f.write("failure-executed")
raise SystemExit(9)
'''
        with open(LOGGER, 'w') as f:
            f.write(failure_probe)
        os.chmod(LOGGER, 0o755)
        write_fstab(failure_mount)
        if os.path.exists(marker):
            os.remove(marker)
        if os.path.exists(STATUS):
            os.remove(STATUS)
        result = run_as_user([DEPLOY])
        assert_file_text(marker, 'failure-executed')
        assert not os.path.exists(os.path.join(failure_mount, 'telemetry.log'))
        assert_file_text(STATUS, 'DEPLOYMENT_FAILED')
    finally:
        with open(LOGGER, 'wb') as f:
            f.write(original_logger)
        os.chmod(LOGGER, logger_mode)
        with open(FSTAB, 'w') as f:
            f.write(original_fstab)
        for path in (logger_mount, deploy_mount, failure_mount):
            shutil.rmtree(path, ignore_errors=True)
        if os.path.exists(marker):
            os.remove(marker)

    # Execute the restored submitted deployment to produce and validate the requested final state.
    shutil.rmtree('/home/user/sensor_mnt', ignore_errors=True)
    if os.path.exists(STATUS):
        os.remove(STATUS)
    result = run_as_user([DEPLOY])
    assert result.returncode == 0, \
        f'Final deploy.sh execution failed: stdout={result.stdout!r}, stderr={result.stderr!r}'

    with open(FSTAB, 'r') as f:
        assert f.read().splitlines() == [EXPECTED_LINE]
    assert_file_text('/home/user/sensor_mnt/telemetry.log', 'EDGE_DATA_ACTIVE')
    assert_file_text(STATUS, 'DEPLOYMENT_SUCCESS')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
