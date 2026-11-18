#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import stat
import subprocess
import tempfile
import pytest


def test_expect_script_executes_autonomous_workflow():
    """Execute the submitted Expect script against an instrumented appliance CLI."""
    script_file = "/home/user/auto_deploy.exp"
    cli_file = "/home/user/appliance_cli.sh"
    auth_file = "/home/user/appliance_fs/auth.conf"
    net_file = "/home/user/appliance_fs/network.conf"
    log_file = "/home/user/deploy.log"

    assert os.path.exists(script_file), f"Expect script {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} is not a regular file."
    assert os.path.getsize(script_file) > 0, f"{script_file} is empty."

    with open(auth_file, "r") as f:
        assert "auth_type=password" in f.read(), "Password authentication was not enabled before deployment."

    with open(cli_file, "rb") as f:
        original_cli = f.read()
    original_mode = stat.S_IMODE(os.stat(cli_file).st_mode)

    trace_fd, trace_path = tempfile.mkstemp(prefix="appliance_trace_", dir="/tmp")
    os.close(trace_fd)
    os.chmod(trace_path, 0o600)

    wrapper = f'''#!/bin/bash
TRACE={shlex.quote(trace_path)}
printf 'Login: '
IFS= read -r user || exit 40
printf 'login=%s\\n' "$user" >> "$TRACE"
[ "$user" = "admin" ] || exit 41

printf 'Password: '
IFS= read -r pass || exit 42
printf 'password=%s\\n' "$pass" >> "$TRACE"
[ "$pass" = "admin123" ] || exit 43

echo 'Welcome to ApplianceOS 4.2'
commands=(
  'set interface vlan20 192.168.100.1/24'
  'set route 10.0.0.0/8 192.168.100.254'
  'commit'
  'exit'
)
for expected in "${{commands[@]}}"; do
    printf 'appliance> '
    IFS= read -r line || exit 44
    line="${{line%$'\\r'}}"
    printf 'command=%s\\n' "$line" >> "$TRACE"
    [ "$line" = "$expected" ] || exit 45
    if [ "$line" = 'commit' ]; then
        printf '%s\\n' 'interface=vlan20 192.168.100.1/24' > /home/user/appliance_fs/network.conf
        printf '%s\\n' 'route=10.0.0.0/8 192.168.100.254' >> /home/user/appliance_fs/network.conf
        printf '%s\\n' 'DEPLOYMENT_SUCCESS' > /home/user/deploy.log
        echo 'Configuration committed.'
    fi
done
'''

    for path in (net_file, log_file):
        if os.path.lexists(path):
            os.unlink(path)

    result = None
    run_error = None
    try:
        with open(cli_file, "w") as f:
            f.write(wrapper)
        os.chmod(cli_file, 0o755)

        try:
            result = subprocess.run(
                ["expect", script_file],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except Exception as exc:
            run_error = exc

        with open(trace_path, "r") as f:
            trace = [line.rstrip("\n") for line in f]
    finally:
        with open(cli_file, "wb") as f:
            f.write(original_cli)
        os.chmod(cli_file, original_mode)
        if os.path.exists(trace_path):
            os.unlink(trace_path)

    assert run_error is None, f"Expect script did not complete autonomously: {run_error}"
    assert result.returncode == 0, (
        f"Expect script failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert trace == [
        "login=admin",
        "password=admin123",
        "command=set interface vlan20 192.168.100.1/24",
        "command=set route 10.0.0.0/8 192.168.100.254",
        "command=commit",
        "command=exit",
    ], f"Expect script did not perform the required CLI interaction. Trace: {trace!r}"


def test_auth_conf_updated():
    """Verify that auth.conf was updated to use password authentication."""
    auth_file = "/home/user/appliance_fs/auth.conf"
    assert os.path.exists(auth_file), f"{auth_file} does not exist."

    with open(auth_file, "r") as f:
        content = f.read()

    assert "auth_type=password" in content, "auth.conf does not contain 'auth_type=password'."


def test_network_conf_contents():
    """Verify that network.conf contains the correct interface and route configuration."""
    net_file = "/home/user/appliance_fs/network.conf"
    assert os.path.exists(net_file), f"{net_file} does not exist. Did the expect script run successfully?"

    with open(net_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "interface=vlan20 192.168.100.1/24",
        "route=10.0.0.0/8 192.168.100.254"
    ]

    for expected in expected_lines:
        assert expected in lines, f"network.conf is missing expected line: '{expected}'"


def test_deploy_log_success():
    """Verify that deploy.log contains the success message."""
    log_file = "/home/user/deploy.log"
    assert os.path.exists(log_file), f"{log_file} does not exist. The commit command may not have been executed."

    with open(log_file, "r") as f:
        content = f.read().strip()

    assert content == "DEPLOYMENT_SUCCESS", f"deploy.log does not contain the exact success message. Found: '{content}'"


def test_expect_script_exists():
    """Verify that the expect script was created."""
    script_file = "/home/user/auto_deploy.exp"
    assert os.path.exists(script_file), f"Expect script {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} is not a regular file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
