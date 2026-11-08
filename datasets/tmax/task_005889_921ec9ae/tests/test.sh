#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import stat
import subprocess
import uuid
import pytest


def run_as_user(argv, timeout=10):
    account = pwd.getpwnam('user')

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env['HOME'] = account.pw_dir
    env['USER'] = account.pw_name
    env['LOGNAME'] = account.pw_name
    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
        preexec_fn=demote,
    )


def test_expect_script_exists():
    """Check that the Expect script exists."""
    script_path = '/home/user/auto_deploy.exp'
    assert os.path.exists(script_path), f"Expect script '{script_path}' was not found."
    assert os.path.isfile(script_path), f"'{script_path}' is not a file."


def test_deployment_status_file():
    """Check that the deployment status file exists and contains 'READY'."""
    status_path = '/home/user/deploy_dir/status.txt'
    assert os.path.exists(status_path), f"Status file '{status_path}' was not created. Did the Expect script run successfully?"
    with open(status_path, 'r') as f:
        content = f.read().strip()
    assert "READY" in content, f"Status file '{status_path}' does not contain 'READY'."


def test_health_check_cpp_and_binary():
    """Check that the C++ source and compiled binary exist."""
    cpp_path = '/home/user/health_check.cpp'
    bin_path = '/home/user/health_check'
    assert os.path.exists(cpp_path), f"C++ source file '{cpp_path}' was not found."
    assert os.path.exists(bin_path), f"Compiled binary '{bin_path}' was not found."
    assert os.access(bin_path, os.X_OK), f"Compiled binary '{bin_path}' is not executable."


def test_health_log_file():
    """Check that the health log file exists and contains exactly 'HEALTHY\\n'."""
    log_path = '/home/user/deploy_dir/health_log.txt'
    assert os.path.exists(log_path), f"Health log file '{log_path}' was not created. Did you run the health_check binary?"
    with open(log_path, 'r') as f:
        content = f.read()
    assert content == "HEALTHY\n", f"Health log file '{log_path}' content is incorrect. Expected 'HEALTHY\\n', got {repr(content)}"


def test_acl_permissions():
    """Check that the ACL grants read permission to the daemon user on the health log file."""
    log_path = '/home/user/deploy_dir/health_log.txt'
    assert os.path.exists(log_path), f"Health log file '{log_path}' missing, cannot check ACLs."

    result = subprocess.run(['getfacl', log_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run getfacl on '{log_path}'."

    acl_output = result.stdout
    expected_acl = "user:daemon:r--"

    assert expected_acl in acl_output, f"ACL for daemon user is incorrect or missing. Expected '{expected_acl}' in getfacl output, got:\n{acl_output}"


def test_expect_script_actually_drives_legacy_deployment():
    """Execute the submitted Expect program against a fresh interactive deployment."""
    expect_path = '/home/user/auto_deploy.exp'
    legacy_path = '/home/user/legacy_deploy.sh'
    status_path = '/home/user/deploy_dir/status.txt'
    nonce = uuid.uuid4().hex
    marker_path = f'/tmp/legacy_deploy_verified_{nonce}'

    challenge = f'''#!/bin/bash
printf 'Enter migration token: '
IFS= read -r token
if [ "$token" = 'CloudMigrate2024!' ]; then
    echo 'Deployment successful.'
    mkdir -p /home/user/deploy_dir
    printf 'READY\\n' > /home/user/deploy_dir/status.txt
    printf '%s\\n' '{nonce}' > '{marker_path}'
else
    echo 'Auth failed. Token rejected.'
    exit 1
fi
'''

    assert os.path.isfile(legacy_path), f"Legacy deployment path '{legacy_path}' is not a file."
    os.unlink(legacy_path)
    with open(legacy_path, 'w') as f:
        f.write(challenge)
    os.chmod(legacy_path, 0o755)

    for path in (status_path, marker_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    result = run_as_user(['/usr/bin/expect', expect_path], timeout=15)
    assert result.returncode == 0, (
        f"Expect script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(marker_path), "The interactive legacy deployment did not authenticate successfully."
    with open(marker_path, 'r') as f:
        assert f.read() == nonce + '\n', "Legacy deployment completion marker is invalid."
    assert os.path.isfile(status_path), "Executing the Expect script did not create status.txt."
    with open(status_path, 'r') as f:
        assert f.read() == 'READY\n', "The executed deployment did not produce the expected READY status."


def test_health_check_binary_behavior():
    """Execute the submitted compiled monitor on unhealthy and healthy status inputs."""
    binary = '/home/user/health_check'
    status_path = '/home/user/deploy_dir/status.txt'
    log_path = '/home/user/deploy_dir/health_log.txt'

    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "health_check is not a compiled ELF executable."

    with open(status_path, 'w') as f:
        f.write('BROKEN\n')
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    result = run_as_user([binary], timeout=10)
    assert result.returncode == 0, (
        f"health_check failed on an unhealthy status with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    if os.path.exists(log_path):
        with open(log_path, 'r') as f:
            assert f.read() != 'HEALTHY\n', "health_check reported HEALTHY for a BROKEN status."

    with open(status_path, 'w') as f:
        f.write('READY\n')
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    result = run_as_user([binary], timeout=10)
    assert result.returncode == 0, (
        f"health_check failed on READY status with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(log_path), "Executing health_check on READY status did not create health_log.txt."
    with open(log_path, 'r') as f:
        assert f.read() == 'HEALTHY\n', "health_check did not write exactly 'HEALTHY\\n'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
