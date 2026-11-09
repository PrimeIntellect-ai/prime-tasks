#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import stat
import subprocess
import tempfile

import pytest


@pytest.fixture(scope="session", autouse=True)
def run_real_deployment():
    """Run deploy.sh from a clean state and verify its real socket operations."""
    deploy_path = "/home/user/deploy.sh"
    config_path = "/home/user/config.env"
    log_path = "/home/user/deployment.log"

    assert os.path.isfile(deploy_path), f"{deploy_path} is missing or is not a regular file."
    mode = os.stat(deploy_path).st_mode
    assert mode & stat.S_IXUSR, f"{deploy_path} is not executable."

    # Source config.env as the deployment user and inspect the resulting active
    # environment, rather than trusting text that could be inside a comment.
    config_result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "bash", "-c",
            'source "$1" && env -0', "bash", config_path,
        ],
        capture_output=True,
        check=False,
    )
    assert config_result.returncode == 0, (
        f"Could not source {config_path}: "
        f"{config_result.stderr.decode(errors='replace')}"
    )
    active_env = {}
    for entry in config_result.stdout.split(b"\0"):
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            active_env[key.decode(errors="replace")] = value.decode(errors="replace")

    expected_socket = "/home/user/vm_sockets/vnc.sock"
    assert active_env.get("UPSTREAM_SOCKET") == expected_socket, (
        "The active UPSTREAM_SOCKET value is incorrect."
    )
    assert active_env.get("DOWNSTREAM_TARGET") == expected_socket, (
        "The active DOWNSTREAM_TARGET value is incorrect."
    )

    # A previous or manually created success log must not satisfy verification.
    if os.path.lexists(log_path):
        assert not os.path.isdir(log_path), f"{log_path} must be a file, not a directory."
        os.unlink(log_path)

    # Wrap socat only to record the real listener and connection arguments; all
    # operations are still delegated to the system socat implementation.
    with tempfile.TemporaryDirectory(prefix="verifier-socat-") as wrapper_dir:
        trace_path = os.path.join(wrapper_dir, "socat.trace")
        wrapper_path = os.path.join(wrapper_dir, "socat")
        with open(trace_path, "w"):
            pass
        os.chmod(trace_path, 0o666)

        with open(wrapper_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s\\n' \"$@\" >> " + repr(trace_path) + "\n")
            f.write("exec /usr/bin/socat \"$@\"\n")
        os.chmod(wrapper_path, 0o755)
        os.chmod(wrapper_dir, 0o755)

        result = subprocess.run(
            [
                "runuser", "-u", "user", "--", "/usr/bin/env",
                f"PATH={wrapper_dir}:/usr/bin:/bin",
                deploy_path,
            ],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )

        assert result.returncode == 0, (
            f"{deploy_path} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        with open(trace_path, "r") as f:
            traced_args = [line.strip() for line in f if line.strip()]

        assert any(arg.startswith(f"UNIX-LISTEN:{expected_socket},") for arg in traced_args), (
            "deploy.sh did not start the VNC service on the configured Unix socket."
        )
        assert f"UNIX-CONNECT:{expected_socket}" in traced_args, (
            "deploy.sh did not perform the downstream health-check through the configured Unix socket."
        )


def test_deployment_log_exists_and_content():
    """Verify that deployment.log was generated with the expected success message."""
    log_path = "/home/user/deployment.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run deploy.sh successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "VNC_HEALTH_CHECK_PASSED", f"Expected 'VNC_HEALTH_CHECK_PASSED' in {log_path}, got '{content}'"


def test_config_env_fixed():
    """Verify that DOWNSTREAM_TARGET was corrected in config.env."""
    config_path = "/home/user/config.env"
    assert os.path.isfile(config_path), f"{config_path} is missing."

    with open(config_path, "r") as f:
        content = f.read()

    assert 'export DOWNSTREAM_TARGET="/home/user/vm_sockets/vnc.sock"' in content, \
        "DOWNSTREAM_TARGET in config.env was not corrected to match UPSTREAM_SOCKET."


def test_acl_permissions():
    """Verify that the correct ACL permissions were applied to /home/user/vm_sockets."""
    dir_path = "/home/user/vm_sockets"
    assert os.path.isdir(dir_path), f"{dir_path} directory is missing."

    try:
        result = subprocess.run(
            ["getfacl", dir_path],
            capture_output=True,
            text=True,
            check=True,
        )
        output = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run getfacl on {dir_path}: {e.stderr}")

    assert "group:users:rwx" in output, \
        f"ACL permissions for group 'users' are missing or incorrect on {dir_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
