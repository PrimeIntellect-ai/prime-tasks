#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import select
import stat
import string
import subprocess
import time

PROXY_SCRIPT = "/home/user/secure_proxy.sh"
BACKEND = "/home/user/legacy_backend"


def wait_for_start_of_second():
    while time.time() % 1.0 > 0.08:
        time.sleep(0.01)


def test_proxy_exists_and_executable():
    assert os.path.exists(PROXY_SCRIPT), f"The script {PROXY_SCRIPT} does not exist."
    assert os.path.isfile(PROXY_SCRIPT), f"{PROXY_SCRIPT} is not a file."
    assert os.access(PROXY_SCRIPT, os.X_OK), f"{PROXY_SCRIPT} is not executable."
    with open(PROXY_SCRIPT, "rb") as f:
        first_line = f.readline(256).lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, \
        f"{PROXY_SCRIPT} must be a Bash script."


def test_proxy_functionality():
    wait_for_start_of_second()

    input_data = (
        "PING\n"
        "EXEC short\n"
        "EXEC this_is_a_very_long_payload_that_will_crash\n"
        "EXEC a\n"
        "PING\n"
        "EXEC b\n"
        "EXEC c\n"
    )

    expected_output = (
        "PONG\n"
        "SUCCESS: short\n"
        "ERR: MEM_SAFETY\n"
        "ERR: RATE_LIMIT\n"
        "ERR: RATE_LIMIT\n"
        "ERR: RATE_LIMIT\n"
        "ERR: RATE_LIMIT\n"
    )

    process = subprocess.Popen(
        [PROXY_SCRIPT],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = process.communicate(input=input_data, timeout=5)
    assert stdout == expected_output, f"Output mismatch.\nExpected:\n{expected_output}\nGot:\n{stdout}"


def test_proxy_invalid_and_edge_cases():
    wait_for_start_of_second()

    input_data = (
        "UNKNOWN\n"
        "EXEC 12345678901234567890\n"
        "EXEC 123456789012345678901\n"
    )

    expected_output = (
        "ERR: INVALID_REQ\n"
        "SUCCESS: 12345678901234567890\n"
        "ERR: MEM_SAFETY\n"
    )

    process = subprocess.Popen(
        [PROXY_SCRIPT],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = process.communicate(input=input_data, timeout=5)
    assert stdout == expected_output, f"Output mismatch for edge cases.\nExpected:\n{expected_output}\nGot:\n{stdout}"


def install_backend_probe(log_path, token):
    probe = f'''#!/usr/bin/env python3
import json
import os
import sys
with open({log_path!r}, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:], separators=(",", ":")) + "\\n")
print("BACKEND_OK:" + os.environ["BACKEND_TOKEN"] + ":" + json.dumps(sys.argv[1:], separators=(",", ":")))
'''
    if os.path.lexists(BACKEND):
        os.unlink(BACKEND)
    with open(BACKEND, "w", encoding="utf-8") as f:
        f.write(probe)
    os.chmod(BACKEND, 0o755)


def backend_output(token, line):
    return "BACKEND_OK:" + token + ":" + json.dumps([line], separators=(",", ":")) + "\n"


def run_proxy(lines, env):
    result = subprocess.run(
        [PROXY_SCRIPT],
        input="".join(line + "\n" for line in lines),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=5,
    )
    assert result.returncode == 0, f"Proxy exited with {result.returncode}: {result.stderr}"
    return result.stdout


def read_one_line(process):
    ready, _, _ = select.select([process.stdout], [], [], 2.0)
    assert ready, "Proxy did not produce a response within two seconds"
    line = process.stdout.readline()
    assert line != "", "Proxy terminated before producing a response"
    return line


def test_randomized_validation_passthrough_and_timestamp_rate_limit():
    with open(BACKEND, "rb") as f:
        original_backend = f.read()
    original_mode = stat.S_IMODE(os.stat(BACKEND).st_mode)

    token = secrets.token_hex(16)
    log_path = "/tmp/backend_calls_" + secrets.token_hex(12) + ".jsonl"
    env = os.environ.copy()
    env["BACKEND_TOKEN"] = token

    try:
        install_backend_probe(log_path, token)

        alphabet = string.ascii_letters + string.digits + " _-;*$?[]{}()'\\\""
        short_lengths = [0, 1, 2, 7, 19, 20]
        long_lengths = [21, 22, 27, 39]
        cases = [("PING", "PONG\n", None)]

        for n in short_lengths:
            payload = "".join(secrets.choice(alphabet) for _ in range(n))
            line = "EXEC " + payload
            cases.append((line, backend_output(token, line), line))

        for n in long_lengths:
            payload = "".join(secrets.choice(alphabet) for _ in range(n))
            cases.append(("EXEC " + payload, "ERR: MEM_SAFETY\n", None))

        for _ in range(5):
            unknown = "BAD_" + secrets.token_hex(random.randint(3, 9))
            cases.append((unknown, "ERR: INVALID_REQ\n", None))
        cases.extend([
            ("EXEC", "ERR: INVALID_REQ\n", None),
            (" PING", "ERR: INVALID_REQ\n", None),
            ("PING ", "ERR: INVALID_REQ\n", None),
        ])

        random.SystemRandom().shuffle(cases)
        expected_calls = []
        for offset in range(0, len(cases), 3):
            group = cases[offset:offset + 3]
            actual = run_proxy([case[0] for case in group], env)
            expected = "".join(case[1] for case in group)
            assert actual == expected, f"Randomized output mismatch. Expected {expected!r}, got {actual!r}"
            expected_calls.extend(case[2] for case in group if case[2] is not None)

        with open(log_path, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls == [[line] for line in expected_calls], \
            f"Backend received wrong, unsafe, or extra requests: {calls!r}"

        unsafe = "EXEC " + secrets.token_hex(16)
        blocked_safe = "EXEC " + secrets.token_hex(5)
        rollover_safe = "EXEC " + secrets.token_hex(6)
        first_three = [
            ("NOPE_" + secrets.token_hex(4), "ERR: INVALID_REQ\n"),
            (unsafe, "ERR: MEM_SAFETY\n"),
            ("PING", "PONG\n"),
        ]
        random.SystemRandom().shuffle(first_three)

        wait_for_start_of_second()
        process = subprocess.Popen(
            [PROXY_SCRIPT], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=env, bufsize=1
        )
        try:
            for line, expected in first_three:
                process.stdin.write(line + "\n")
                process.stdin.flush()
                assert read_one_line(process) == expected

            process.stdin.write(blocked_safe + "\n")
            process.stdin.flush()
            assert read_one_line(process) == "ERR: RATE_LIMIT\n"

            current_second = int(time.time())
            while int(time.time()) == current_second:
                time.sleep(0.01)

            process.stdin.write(rollover_safe + "\n")
            process.stdin.flush()
            assert read_one_line(process) == backend_output(token, rollover_safe)
            process.stdin.close()
            assert process.wait(timeout=5) == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

        expected_calls.append(rollover_safe)
        with open(log_path, encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls == [[line] for line in expected_calls], \
            "Rate-limited, invalid, or oversized requests were incorrectly sent to the backend"
    finally:
        if os.path.lexists(BACKEND):
            os.unlink(BACKEND)
        with open(BACKEND, "wb") as f:
            f.write(original_backend)
        os.chmod(BACKEND, original_mode)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
