#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

DEPLOY_SCRIPT = "/home/user/deploy_update.py"
RUN_SCRIPT = "/home/user/run_deployment.sh"
ROUTE_CONFIG = "/home/user/route_config.cmds"

EXPECTED_CONTENT = (
    "ip link add name deploy0 type dummy\n"
    "ip link set deploy0 up\n"
    "ip route add 10.150.0.0/16 dev deploy0\n"
)
PROMPT = "Region detected. Confirm deployment? [Y/n]: "


def remove_config():
    if os.path.exists(ROUTE_CONFIG):
        os.remove(ROUTE_CONFIG)


def assert_expected_config():
    assert os.path.isfile(ROUTE_CONFIG), f"{ROUTE_CONFIG} was not created."
    with open(ROUTE_CONFIG, "r") as f:
        actual_content = f.read()
    assert actual_content.strip() == EXPECTED_CONTENT.strip(), (
        f"Contents of {ROUTE_CONFIG} do not match the expected output.\n"
        f"Expected:\n{EXPECTED_CONTENT}\nActual:\n{actual_content}"
    )


def test_scripts_exist_and_executable():
    """Verify that both scripts exist and the bash wrapper is executable."""
    assert os.path.isfile(DEPLOY_SCRIPT), f"{DEPLOY_SCRIPT} does not exist."
    assert os.path.isfile(RUN_SCRIPT), f"{RUN_SCRIPT} does not exist."
    assert os.access(RUN_SCRIPT, os.X_OK), f"{RUN_SCRIPT} is not executable."


def test_run_deployment_creates_config():
    """Verify that running the bash wrapper creates the expected route config file."""
    remove_config()
    result = subprocess.run([RUN_SCRIPT], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"{RUN_SCRIPT} failed with exit code {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(ROUTE_CONFIG), f"{ROUTE_CONFIG} was not created by {RUN_SCRIPT}."
    assert_expected_config()


def test_deploy_update_success_directly():
    """Exercise deploy_update.py's required successful interactive path directly."""
    remove_config()
    env = os.environ.copy()
    env["TZ"] = "America/New_York"
    env["LC_ALL"] = "fr_CA.UTF-8"

    result = subprocess.run(
        ["python3", DEPLOY_SCRIPT],
        env=env,
        input="Y\n",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{DEPLOY_SCRIPT} should succeed for the required environment and input Y, "
        f"but exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert PROMPT in result.stdout or PROMPT in result.stderr, (
        "The script did not emit the exact required prompt."
    )
    assert_expected_config()


def test_deploy_update_wrong_env():
    """Verify that deploy_update.py exits with 1 and creates no file for a wrong environment."""
    remove_config()
    env = os.environ.copy()
    env["TZ"] = "UTC"
    env["LC_ALL"] = "en_US.UTF-8"

    result = subprocess.run(
        ["python3", DEPLOY_SCRIPT], env=env, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 1, (
        f"{DEPLOY_SCRIPT} should exit with code 1 when TZ and LC_ALL do not match, "
        f"but exited with {result.returncode}."
    )
    assert not os.path.exists(ROUTE_CONFIG), (
        f"{DEPLOY_SCRIPT} created {ROUTE_CONFIG} despite a mismatched environment."
    )


def test_deploy_update_wrong_input():
    """Verify that deploy_update.py exits with 1 and creates no file for non-Y input."""
    remove_config()
    env = os.environ.copy()
    env["TZ"] = "America/New_York"
    env["LC_ALL"] = "fr_CA.UTF-8"

    result = subprocess.run(
        ["python3", DEPLOY_SCRIPT],
        env=env,
        input="n\n",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 1, (
        f"{DEPLOY_SCRIPT} should exit with code 1 when input is not 'Y', "
        f"but exited with {result.returncode}."
    )
    assert "Region detected. Confirm deployment? [Y/n]:" in result.stdout or \
        "Region detected. Confirm deployment? [Y/n]:" in result.stderr, \
        "The script did not prompt with the exact required string."
    assert not os.path.exists(ROUTE_CONFIG), (
        f"{DEPLOY_SCRIPT} created {ROUTE_CONFIG} despite receiving non-Y input."
    )


def test_wrapper_invokes_deploy_script_with_required_env_and_input():
    """Instrument the required path to verify the wrapper actually invokes it correctly."""
    marker = f"/tmp/deployment_probe_{secrets.token_hex(16)}.json"
    with open(DEPLOY_SCRIPT, "rb") as f:
        original = f.read()
    original_mode = os.stat(DEPLOY_SCRIPT).st_mode

    probe = f'''#!/usr/bin/env python3
import json
import os
import sys

marker = {marker!r}
route_config = {ROUTE_CONFIG!r}
expected = {EXPECTED_CONTENT!r}
sys.stdout.write({PROMPT!r})
sys.stdout.flush()
answer = sys.stdin.readline().rstrip("\\r\\n")
with open(marker, "w") as f:
    json.dump({{"TZ": os.environ.get("TZ"), "LC_ALL": os.environ.get("LC_ALL"), "input": answer}}, f)
if os.environ.get("TZ") != "America/New_York" or os.environ.get("LC_ALL") != "fr_CA.UTF-8" or answer != "Y":
    sys.exit(1)
with open(route_config, "w") as f:
    f.write(expected)
'''

    try:
        with open(DEPLOY_SCRIPT, "w") as f:
            f.write(probe)
        os.chmod(DEPLOY_SCRIPT, original_mode)
        remove_config()

        result = subprocess.run([RUN_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (
            f"{RUN_SCRIPT} failed while invoking the deployment script: {result.stderr}"
        )
        assert os.path.isfile(marker), (
            f"{RUN_SCRIPT} did not invoke {DEPLOY_SCRIPT}."
        )
        with open(marker, "r") as f:
            observed = json.load(f)
        assert observed == {
            "TZ": "America/New_York",
            "LC_ALL": "fr_CA.UTF-8",
            "input": "Y",
        }, f"Wrapper invoked deploy_update.py incorrectly: {observed}"
        assert_expected_config()
    finally:
        with open(DEPLOY_SCRIPT, "wb") as f:
            f.write(original)
        os.chmod(DEPLOY_SCRIPT, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
