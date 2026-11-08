#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shlex
import stat
import subprocess
import tempfile


def test_recovered_token():
    secret_path = "/home/user/evidence/.secret_key"
    token_path = "/home/user/recovered_token.txt"

    assert os.path.isfile(secret_path), f"Secret key file {secret_path} is missing."
    with open(secret_path, "r") as f:
        secret = f.read().strip()

    expected_string = f"forensic_admin:1715000000:{secret}"
    expected_token = hashlib.sha256(expected_string.encode("utf-8")).hexdigest()

    assert os.path.isfile(token_path), f"Recovered token file {token_path} is missing."
    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token == expected_token, f"The token in {token_path} is incorrect. Expected {expected_token}, got {actual_token}."


def test_exploited_binary():
    binary_path = "/home/user/exploited_binary.txt"
    assert os.path.isfile(binary_path), f"Exploited binary file {binary_path} is missing."

    with open(binary_path, "r") as f:
        actual_binary = f.read().strip()

    expected_binary = "/opt/internal/sys_backup_mgr"
    assert actual_binary == expected_binary, f"The exploited binary in {binary_path} is incorrect. Expected {expected_binary}, got {actual_binary}."


def run_script(script_path, args):
    return subprocess.run(
        [script_path] + args,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_auth_flow_script():
    script_path = "/home/user/test_auth_flow.sh"
    mock_path = "/home/user/evidence/auth_service_mock.sh"

    assert os.path.isfile(script_path), f"Auth flow script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    # Preserve the original execution assertion.
    test_user = "testuser_123"
    test_timestamp = "9876543210"
    result = run_script(script_path, [test_user, test_timestamp])

    assert result.returncode == 0, f"Script {script_path} failed with exit code {result.returncode}. Output: {result.stdout}\nError: {result.stderr}"
    assert "AUTH SUCCESS" in result.stdout, f"Script {script_path} did not produce 'AUTH SUCCESS'. Output: {result.stdout}"

    # The script must accept exactly two arguments.
    for bad_args in ([], ["only_user"], ["user", "123", "extra"]):
        bad_result = run_script(script_path, bad_args)
        assert bad_result.returncode != 0, (
            f"Script {script_path} accepted {len(bad_args)} arguments; it must accept exactly two. "
            f"Output: {bad_result.stdout}\nError: {bad_result.stderr}"
        )

    assert os.path.isfile(mock_path), f"Mock service {mock_path} is missing."

    fd, log_path = tempfile.mkstemp(prefix="auth_mock_calls_", dir="/tmp")
    os.close(fd)
    backup_path = mock_path + ".verifier_backup_" + secrets.token_hex(8)

    wrapper = f'''#!/bin/bash
LOG_PATH={shlex.quote(log_path)}
if [ "$#" -ne 3 ]; then
    exit 90
fi
SECRET=$(cat /home/user/evidence/.secret_key)
EXPECTED=$(printf '%s' "$1:$2:$SECRET" | sha256sum | awk '{{print $1}}')
if [ "$EXPECTED" != "$3" ]; then
    echo "AUTH FAILED"
    exit 91
fi
printf '%s\\t%s\\t%s\\n' "$1" "$2" "$3" >> "$LOG_PATH"
echo "AUTH SUCCESS"
exit 37
'''

    os.replace(mock_path, backup_path)
    try:
        with open(mock_path, "w") as f:
            f.write(wrapper)
        os.chmod(mock_path, 0o755)

        with open("/home/user/evidence/.secret_key", "r") as f:
            secret = f.read().strip()

        expected_calls = []
        for _ in range(3):
            username = "audit_" + secrets.token_hex(10)
            timestamp = str(secrets.randbelow(8_000_000_000) + 1_000_000_000)
            expected_token = hashlib.sha256(
                f"{username}:{timestamp}:{secret}".encode("utf-8")
            ).hexdigest()

            dynamic_result = run_script(script_path, [username, timestamp])
            assert dynamic_result.returncode == 37, (
                f"Script {script_path} did not forward the mock service exit code 37; "
                f"got {dynamic_result.returncode}. Output: {dynamic_result.stdout}\n"
                f"Error: {dynamic_result.stderr}"
            )
            expected_calls.append((username, timestamp, expected_token))

        with open(log_path, "r") as f:
            calls = [tuple(line.rstrip("\n").split("\t")) for line in f if line.strip()]

        for expected_call in expected_calls:
            assert expected_call in calls, (
                "The script did not call auth_service_mock.sh with the dynamically supplied "
                f"username, timestamp, and correctly generated token: {expected_call}"
            )
    finally:
        if os.path.lexists(mock_path):
            os.remove(mock_path)
        os.replace(backup_path, mock_path)
        if os.path.exists(log_path):
            os.remove(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
