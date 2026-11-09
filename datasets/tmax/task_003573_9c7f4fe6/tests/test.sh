#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import shlex
import stat
import subprocess
import tempfile
import pytest


def test_compromised_ip():
    path = "/home/user/compromised_ip.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        ip = f.read().strip()
    assert ip == "203.0.113.42", f"Expected IP '203.0.113.42' in {path}, but got '{ip}'."


def test_exploit_test_sh():
    exploit_path = "/home/user/exploit_test.sh"
    rotator_path = "/home/user/legacy_rotator.sh"

    assert os.path.isfile(exploit_path), f"File {exploit_path} is missing."
    st = os.stat(exploit_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {exploit_path} is not executable."

    fd, audit_path = tempfile.mkstemp(prefix="rotator_audit_")
    os.close(fd)
    os.unlink(audit_path)

    # Recreate an instrumented version of the original rotator. It records the
    # actual arguments while retaining the original password check and eval.
    rotator_content = f'''#!/bin/bash
{{
    echo "$#"
    printf %s "$1" | base64 -w0
    echo
    printf %s "$2" | base64 -w0
    echo
}} > {shlex.quote(audit_path)}
INPUT=$1
CMD=$2
B64_KEY="czNjcjN0X2I0Y2tkMDBy"
SECRET=$(echo "$B64_KEY" | base64 -d)
if [ "$INPUT" == "$SECRET" ]; then
    eval "$CMD"
    exit 0
fi
echo "Rotating credentials..."
'''
    with open(rotator_path, "w") as f:
        f.write(rotator_content)
    os.chmod(rotator_path, 0o755)

    result = subprocess.run([exploit_path], capture_output=True, text=True, timeout=10)
    output = result.stdout.strip()
    assert output == "SYSTEM_COMPROMISED", f"Expected output 'SYSTEM_COMPROMISED', but got '{output}'."

    assert os.path.isfile(audit_path), "exploit_test.sh did not execute /home/user/legacy_rotator.sh."
    with open(audit_path, "r") as f:
        recorded = f.read().splitlines()
    assert len(recorded) == 3, "Could not validate the arguments supplied to legacy_rotator.sh."
    assert recorded[0] == "2", "legacy_rotator.sh must be called with the password and payload."

    supplied_password = base64.b64decode(recorded[1]).decode()
    payload = base64.b64decode(recorded[2]).decode()
    expected_password = base64.b64decode("czNjcjN0X2I0Y2tkMDBy").decode()
    assert supplied_password == expected_password, "The correct hidden backdoor password was not supplied."

    payload_result = subprocess.run(["bash", "-c", payload], capture_output=True, text=True, timeout=10)
    assert payload_result.returncode == 0, "The supplied payload failed when executed."
    assert payload_result.stdout.strip() == "SYSTEM_COMPROMISED", "The supplied payload does not print SYSTEM_COMPROMISED."
    os.unlink(audit_path)


INITIAL_CONFIG = {
    "service": "auth_backend",
    "port": 8080,
    "password": "old_password_123"
}


def prepare_rotation_files():
    config_path = "/home/user/config.json"
    rotator_path = "/home/user/legacy_rotator.sh"
    with open(config_path, "w") as f:
        json.dump(INITIAL_CONFIG, f, indent=2)
    with open(rotator_path, "w") as f:
        f.write("# dummy script\n")


def assert_successful_rotation(rotate_path, new_password):
    config_path = "/home/user/config.json"
    rotator_path = "/home/user/legacy_rotator.sh"
    prepare_rotation_files()

    result = subprocess.run([rotate_path, new_password], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Rotation failed for a valid single password argument: {result.stderr}"

    assert os.path.isfile(config_path), f"File {config_path} is missing after rotation."
    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {config_path} does not contain valid JSON after rotation.")

    assert data.get("password") == new_password, f"Password in {config_path} was not updated correctly."
    assert data.get("service") == "auth_backend", f"Other JSON fields in {config_path} were altered."
    assert data.get("port") == 8080, f"Other JSON fields in {config_path} were altered."
    assert set(data.keys()) == set(INITIAL_CONFIG.keys()), f"Other JSON fields in {config_path} were altered."
    assert not os.path.exists(rotator_path), f"File {rotator_path} was not deleted by {rotate_path}."


def assert_rejected_arguments(rotate_path, args):
    config_path = "/home/user/config.json"
    rotator_path = "/home/user/legacy_rotator.sh"
    prepare_rotation_files()
    with open(config_path, "rb") as f:
        original_config = f.read()
    with open(rotator_path, "rb") as f:
        original_rotator = f.read()

    result = subprocess.run([rotate_path] + args, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, "rotate.sh must reject calls that do not contain exactly one argument."
    assert os.path.isfile(config_path), "Rejected invocation removed config.json."
    assert os.path.isfile(rotator_path), "Rejected invocation deleted legacy_rotator.sh."
    with open(config_path, "rb") as f:
        assert f.read() == original_config, "Rejected invocation modified config.json."
    with open(rotator_path, "rb") as f:
        assert f.read() == original_rotator, "Rejected invocation modified legacy_rotator.sh."


def test_rotate_sh():
    rotate_path = "/home/user/rotate.sh"
    assert os.path.isfile(rotate_path), f"File {rotate_path} is missing."
    st = os.stat(rotate_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {rotate_path} is not executable."

    # Retain the original fixed-password check.
    assert_successful_rotation(rotate_path, "new_secure_pass_999")

    # A verifier-generated password prevents hardcoding the known test value.
    dynamic_password = "generated_" + secrets.token_urlsafe(24)
    assert_successful_rotation(rotate_path, dynamic_password)

    # The script must accept exactly one argument and leave state untouched otherwise.
    assert_rejected_arguments(rotate_path, [])
    assert_rejected_arguments(rotate_path, ["first_password", "second_password"])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
