#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid


def test_exploit_script_exists_and_executable():
    exploit_path = "/home/user/exploit.sh"
    assert os.path.exists(exploit_path), f"Missing exploit script: {exploit_path}"
    assert os.path.isfile(exploit_path), f"Not a file: {exploit_path}"
    assert os.access(exploit_path, os.X_OK), f"Exploit script is not executable: {exploit_path}"


def test_exploit_execution_and_result():
    exploit_path = "/home/user/exploit.sh"
    binary_path = "/home/user/vulnerable_reporter"
    flag_path = "/home/user/hidden_flag.txt"
    success_path = "/home/user/success.txt"
    nonce = uuid.uuid4().hex
    real_binary = f"/tmp/vulnerable_reporter.real.{nonce}"
    event_path = f"/tmp/vulnerable_reporter.events.{nonce}"

    with open(flag_path, "rb") as f:
        expected_bytes = f.read()

    original_mode = stat.S_IMODE(os.stat(binary_path).st_mode)
    os.replace(binary_path, real_binary)

    wrapper = f'''#!/usr/bin/env python3
import json
import os
import subprocess
import sys

REAL_BINARY = {real_binary!r}
EVENT_PATH = {event_path!r}
FLAG_PATH = {flag_path!r}
SUCCESS_PATH = {success_path!r}

try:
    os.remove(SUCCESS_PATH)
except FileNotFoundError:
    pass

result = subprocess.run([REAL_BINARY] + sys.argv[1:], env=os.environ.copy())
produced_exact = False
try:
    with open(FLAG_PATH, "rb") as f:
        expected = f.read()
    with open(SUCCESS_PATH, "rb") as f:
        produced_exact = f.read() == expected
except OSError:
    pass

with open(EVENT_PATH, "a", encoding="utf-8") as f:
    f.write(json.dumps({{
        "auth_token": os.environ.get("AUTH_TOKEN"),
        "args": sys.argv[1:],
        "produced_exact_success": produced_exact,
    }}) + "\\n")

sys.exit(result.returncode)
'''

    with open(binary_path, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(binary_path, original_mode | stat.S_IXUSR)

    try:
        # Ensure the success.txt doesn't already exist or remove it to ensure the script creates it
        if os.path.exists(success_path):
            os.remove(success_path)

        # Run the exploit script
        result = subprocess.run([exploit_path], capture_output=True, text=True, cwd="/home/user")

        assert result.returncode == 0 or os.path.exists(success_path), (
            f"Execution of {exploit_path} failed or did not create {success_path}. "
            f"Stdout: {result.stdout}, Stderr: {result.stderr}"
        )

        assert os.path.exists(success_path), f"The file {success_path} was not created by the exploit script."

        # Read the original flag
        with open(flag_path, "r") as f:
            expected_flag = f.read().strip()

        # Read the success output
        with open(success_path, "r") as f:
            actual_flag = f.read().strip()

        assert actual_flag == expected_flag, (
            f"The content of {success_path} does not match {flag_path}. "
            f"Expected: {expected_flag}, Got: {actual_flag}"
        )

        with open(flag_path, "rb") as f:
            assert f.read() == expected_bytes, "The exploit modified hidden_flag.txt."
        with open(success_path, "rb") as f:
            assert f.read() == expected_bytes, "success.txt is not an exact byte-for-byte copy of the flag."

        assert os.path.exists(event_path), (
            "The exploit did not invoke /home/user/vulnerable_reporter."
        )
        with open(event_path, "r", encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]

        candidates = [
            event for event in events
            if event.get("auth_token") == "T0k3n_G3n!"
            and event.get("produced_exact_success") is True
            and isinstance(event.get("args"), list)
            and len(event["args"]) >= 1
        ]
        assert candidates, (
            "No invocation of vulnerable_reporter used the correct AUTH_TOKEN and "
            "created success.txt during that invocation."
        )

        # Replay observed reporter arguments directly against the real binary. This
        # proves the crafted argument itself exploits the reporter rather than the
        # script copying hidden_flag.txt separately.
        replay_succeeded = False
        for event in candidates:
            if os.path.exists(success_path):
                os.remove(success_path)
            replay_env = os.environ.copy()
            replay_env["AUTH_TOKEN"] = event["auth_token"]
            replay = subprocess.run(
                [real_binary] + event["args"],
                capture_output=True,
                text=True,
                cwd="/home/user",
                env=replay_env,
            )
            if os.path.exists(success_path):
                with open(success_path, "rb") as f:
                    if f.read() == expected_bytes:
                        replay_succeeded = True
                        break

        assert replay_succeeded, (
            "Replaying the argument supplied to vulnerable_reporter did not create "
            "the exact success.txt; the exploit must use the command injection."
        )
    finally:
        try:
            os.remove(binary_path)
        except FileNotFoundError:
            pass
        if os.path.exists(real_binary):
            os.replace(real_binary, binary_path)
        try:
            os.remove(event_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
