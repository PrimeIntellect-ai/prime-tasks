#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re

def test_go_script_exists():
    assert os.path.exists('/home/user/rolling_stats.go'), "/home/user/rolling_stats.go does not exist"

def test_stats_log_content():
    stats_log_path = '/home/user/stats.log'
    assert os.path.exists(stats_log_path), f"{stats_log_path} does not exist"

    with open(stats_log_path, 'r') as f:
        content = f.read().strip()

    expected = "45.00,78.00,111.00,144.00,177.00"
    assert content == expected, f"Expected {stats_log_path} to contain '{expected}', but got '{content}'"

def test_pipeline_log_content():
    pipeline_log_path = '/home/user/pipeline.log'
    assert os.path.exists(pipeline_log_path), f"{pipeline_log_path} does not exist"

    with open(pipeline_log_path, 'r') as f:
        content = f.read().strip()

    # It should end with the exact success message, or contain it.
    expected_msg = "SUCCESS: Processed 7 records"
    assert expected_msg in content, f"Expected {pipeline_log_path} to contain '{expected_msg}'"

def test_cron_file_content():
    cron_path = '/home/user/stats_cron'
    assert os.path.exists(cron_path), f"{cron_path} does not exist"

    with open(cron_path, 'r') as f:
        content = f.read().strip()

    # Check for */5 * * * *
    cron_regex = re.compile(r'^\*/5\s+\*\s+\*\s+\*\s+\*')
    assert cron_regex.search(content), f"{cron_path} does not contain a valid cron schedule for every 5 minutes (e.g. '*/5 * * * *')"

    assert "go run" in content and "/home/user/rolling_stats.go" in content, f"{cron_path} does not contain the correct command to execute the Go script"
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import os
import pwd
import secrets
import subprocess

source = '/home/user/rolling_stats.go'
input_path = '/home/user/input_data.bin'
stats_path = '/home/user/stats.log'
pipeline_path = '/home/user/pipeline.log'

assert os.path.isfile(source), f"{source} is not a regular file"

user = pwd.getpwnam('user')
cache = '/tmp/verifier-go-cache'
os.makedirs(cache, exist_ok=True)
os.chown(cache, user.pw_uid, user.pw_gid)
os.chmod(cache, 0o700)

def run_case(values):
    encoded = ','.join(str(v) for v in values).encode('utf-16le')
    with open(input_path, 'wb') as f:
        f.write(encoded)
    os.chmod(input_path, 0o666)

    if os.path.lexists(stats_path):
        os.unlink(stats_path)

    sentinel = b'PREEXISTING LOG ENTRY\n'
    with open(pipeline_path, 'wb') as f:
        f.write(sentinel)
    os.chmod(pipeline_path, 0o666)

    env = os.environ.copy()
    env.update({'HOME': '/home/user', 'GOCACHE': cache})
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', '/usr/bin/go', 'run', source],
        cwd='/home/user', env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"go run failed with status {result.returncode}: {result.stderr}"
    )

    assert os.path.isfile(stats_path), f"{stats_path} was not generated"
    with open(stats_path, 'r', encoding='utf-8') as f:
        actual_stats = f.read().strip()
    expected_stats = ','.join(
        f'{sum(values[i:i+3]) / 3:.2f}' for i in range(len(values) - 2)
    )
    assert actual_stats == expected_stats, (
        f"For input {values}, expected rolling averages {expected_stats!r}, "
        f"got {actual_stats!r}"
    )

    with open(pipeline_path, 'rb') as f:
        actual_log = f.read()
    message = f'SUCCESS: Processed {len(values)} records'.encode()
    assert actual_log.startswith(sentinel), "The program did not append to pipeline.log"
    appended = actual_log[len(sentinel):]
    assert appended in (message, message + b'\n'), (
        f"Expected exactly one appended success entry {message!r}, got {appended!r}"
    )

# Multiples of three avoid rounding ambiguities while randomized values prevent
# hardcoded output from satisfying the behavioral checks.
for length in (6, 9):
    values = [3 * secrets.randbelow(2001) - 3000 for _ in range(length)]
    run_case(values)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
