#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import secrets
import stat
import subprocess
import time
from pathlib import Path

RUNNER = "/home/user/runner.sh"
LOG = Path("/home/user/execution.log")


def invoke(args, env=None, timeout=12):
    return subprocess.run(
        [RUNNER, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout,
        check=False,
    )


def make_payload(raw_script, checksum=None):
    raw = raw_script.encode("utf-8")
    key = secrets.token_hex(32)
    iv = secrets.token_hex(16)
    encoded_script = base64.b64encode(raw)
    encrypted = subprocess.run(
        [
            "openssl", "enc", "-aes-256-cbc",
            "-K", key, "-iv", iv, "-a", "-A",
        ],
        input=encoded_script,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.decode("ascii").strip()
    expected_checksum = checksum or hashlib.sha256(raw).hexdigest()
    path = Path("/tmp") / ("payload-" + secrets.token_hex(12) + ".dat")
    path.write_text(f"{key}\n{iv}\n{encrypted}\n{expected_checksum}\n")
    return str(path)


def test_runner_script_exists_and_executable():
    """Check that /home/user/runner.sh exists and is executable."""
    script_path = "/home/user/runner.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_execution_log_content():
    """Check that /home/user/execution.log contains the expected output."""
    log_path = "/home/user/execution.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did the script run successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "Strict Policy Enforced: Target Delta"
    assert content == expected_content, f"Expected '{expected_content}' in {log_path}, got '{content}'"


def test_runner_script_contains_security_constraints():
    """Verify that runner.sh uses env -i and timeout 5 to isolate and constrain the process."""
    script_path = "/home/user/runner.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "env -i" in content, "The script does not appear to use 'env -i' for environment isolation."
    assert "timeout 5" in content, "The script does not appear to use 'timeout 5' for execution constraint."


def test_executes_provided_payload():
    result = invoke(["/home/user/payload.dat"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert LOG.read_text().strip() == "Strict Policy Enforced: Target Delta"


def test_decrypts_decodes_and_executes_fresh_payload():
    token = "FRESH_" + secrets.token_hex(16)
    payload = make_payload(f"printf '%s\\n' '{token}'")
    result = invoke([payload])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert LOG.read_text() == token + "\n"


def test_checksum_mismatch_is_enforced():
    payload = make_payload("echo SHOULD_NOT_EXECUTE", checksum="0" * 64)
    result = invoke([payload])
    assert result.returncode == 1
    assert LOG.read_text().strip() == "POLICY_VIOLATION: CHECKSUM_MISMATCH"


def test_requires_exactly_one_argument():
    no_args = invoke([], timeout=3)
    assert no_args.returncode != 0

    token = "MUST_NOT_RUN_" + secrets.token_hex(12)
    payload = make_payload(f"echo '{token}'")
    LOG.write_text("argument-sentinel\n")
    two_args = invoke([payload, payload], timeout=3)
    assert two_args.returncode != 0
    assert LOG.read_text() == "argument-sentinel\n"


def test_payload_environment_is_isolated():
    variable = "SECRET_" + secrets.token_hex(8).upper()
    token = "ISOLATED_" + secrets.token_hex(12)
    raw = (
        f"if [ -n \"${{{variable}+present}}\" ]; then "
        f"echo ENVIRONMENT_LEAK; exit 23; fi; printf '%s\\n' '{token}'"
    )
    payload = make_payload(raw)
    child_env = os.environ.copy()
    child_env[variable] = "must-not-be-passed-to-payload"
    result = invoke([payload], env=child_env)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert LOG.read_text() == token + "\n"


def test_payload_is_terminated_by_five_second_timeout():
    token = "AFTER_TIMEOUT_" + secrets.token_hex(12)
    payload = make_payload(f"/bin/sleep 10; echo '{token}'")
    started = time.monotonic()
    result = invoke([payload], timeout=8)
    elapsed = time.monotonic() - started
    assert elapsed >= 4.0, f"Payload was not allowed to run under the specified timeout: {elapsed:.2f}s"
    assert elapsed < 7.5, f"Payload was not terminated near the five-second limit: {elapsed:.2f}s"
    if LOG.exists():
        assert token not in LOG.read_text()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
