#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_FILE = '/home/user/analyze_logs.sh'


def test_threat_count_accuracy():
    """
    Check that the numerical count in /home/user/threat_count.txt
    is within the acceptable threshold (<= 5) of the ground truth (42).
    """
    count_file = '/home/user/threat_count.txt'
    assert os.path.exists(count_file), f"File {count_file} does not exist."

    with open(count_file, 'r') as f:
        content = f.read().strip()

    try:
        agent_val = int(content)
    except ValueError:
        pytest.fail(f"Content of {count_file} is not a valid integer: '{content}'")

    truth_val = 42
    diff = abs(agent_val - truth_val)

    assert diff <= 5, f"Expected count close to {truth_val}, but got {agent_val}. Difference {diff} exceeds threshold of 5."


def test_analyze_logs_script_exists():
    """
    Check that the script /home/user/analyze_logs.sh exists.
    """
    assert os.path.exists(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a regular file."


def test_analyze_logs_on_hidden_logs():
    """Run the submitted Bash script on randomized hidden logs and verify its count."""
    assert os.path.exists(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} is not a regular file."

    rng = random.SystemRandom()
    for case_num in range(2):
        nonce = secrets.token_hex(8)
        confirmed_count = rng.randrange(7, 24)
        lines = []

        for i in range(confirmed_count):
            scheme = rng.choice(['http', 'https'])
            host = f"{nonce}-{case_num}-{i}.evil.test"
            if i % 2:
                lines.append(f"10.0.0.{i % 250 + 1} GET /login?next=/home&redirect={scheme}://{host}/landing bypassing CSP")
            else:
                lines.append(f"bypassing CSP 172.16.0.{i % 250 + 1} POST /auth?redirect={scheme}://{host}/steal")

        false_count = rng.randrange(10, 27)
        for i in range(false_count):
            host = f"safe-{nonce}-{case_num}-{i}.test"
            lines.extend(rng.sample([
                f"192.0.2.{i % 250 + 1} GET /login?redirect=http://{host}/ no CSP bypass marker",
                f"198.51.100.{i % 250 + 1} GET /login?redirect=ftp://{host}/ bypassing CSP",
                f"203.0.113.{i % 250 + 1} GET /index.html 200 bypassing CSP",
                f"127.0.0.1 GET /login?redirected=http://{host}/ bypassing CSP",
                f"127.0.0.1 GET /login?REDIRECT=https://{host}/ bypassing CSP",
            ], 1))

        rng.shuffle(lines)
        fd, log_path = tempfile.mkstemp(prefix='hidden_access_', suffix='.log', text=True)
        try:
            with os.fdopen(fd, 'w') as hidden_log:
                hidden_log.write('\n'.join(lines) + '\n')

            result = subprocess.run(
                ['/bin/bash', SCRIPT_FILE, log_path],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Script failed on hidden log with exit code {result.returncode}: {result.stderr}"
            )
            output = result.stdout.strip()
            assert re.fullmatch(r'[+-]?\d+', output), (
                f"Script output must be a single integer, got: {result.stdout!r}"
            )
            assert int(output) == confirmed_count, (
                f"Expected {confirmed_count} confirmed attempts on hidden log, got {output}."
            )
        finally:
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
