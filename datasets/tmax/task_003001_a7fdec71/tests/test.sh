#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import datetime
import pytest

def test_extracted_logs():
    srt_path = "/home/user/extracted_logs.srt"
    txt_path = "/home/user/extracted_logs.txt"

    assert os.path.exists(srt_path), f"Missing file: {srt_path}"
    assert os.path.exists(txt_path), f"Missing file: {txt_path}"

    with open(txt_path, "r") as f:
        content = f.read()

    # Check that it contains the expected log lines and not SRT metadata
    assert "[2023-10-01 10:00:00]" in content, "Missing expected log line in extracted_logs.txt"
    assert "-->" not in content, "extracted_logs.txt should not contain SRT timing arrows"

def test_run_processor_script():
    script_path = "/home/user/run_processor.sh"
    assert os.path.exists(script_path), f"Missing file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read().strip()

    expected_command = "/bin/bash /home/user/process_changes.sh < /var/log/config.log >> /var/log/config_stats.log"
    assert expected_command in content, f"Script does not contain the exact expected command. Found: {content}"

def test_cron_job():
    try:
        output = subprocess.check_output(["crontab", "-l", "-u", "user"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for user 'user'")

    assert "*/5" in output or "0,5,10" in output or "5 * * * *" in output, "Cron job does not appear to run every 5 minutes"
    assert "/home/user/run_processor.sh" in output, "Cron job does not execute /home/user/run_processor.sh"

def test_video_stats():
    stats_path = "/home/user/video_stats.txt"
    assert os.path.exists(stats_path), f"Missing file: {stats_path}"

    txt_path = "/home/user/extracted_logs.txt"
    oracle_path = "/tests/oracle_processor"

    if os.path.exists(oracle_path) and os.path.exists(txt_path):
        with open(txt_path, "r") as f:
            input_data = f.read()

        oracle_proc = subprocess.run([oracle_path], input=input_data, text=True, capture_output=True)
        expected_output = oracle_proc.stdout.strip()

        with open(stats_path, "r") as f:
            actual_output = f.read().strip()

        assert actual_output == expected_output, f"Output in {stats_path} does not match oracle output for {txt_path}"

def generate_log_stream():
    num_lines = random.randint(10, 500)
    start_time = datetime.datetime(2020, 1, 1)
    end_time = datetime.datetime(2025, 1, 1)

    current_time = start_time + datetime.timedelta(seconds=random.randint(0, int((end_time - start_time).total_seconds())))

    keys = ['db_port', 'ui_theme_パス', 'max_connections', 'timeout_é']
    users = ['alice', 'bob', 'charlie', 'dave']
    langs = ['en', 'fr', 'es', 'de']

    lines = []
    for _ in range(num_lines):
        dt_str = current_time.strftime("%Y-%m-%d %H:%M:%S")
        user = random.choice(users)
        lang = random.choice(langs)
        changes = random.randint(1, 100)
        key = random.choice(keys)
        lines.append(f"[{dt_str}] USER={user} LANG={lang} CHANGES={changes} KEY={key}")
        # Increment time to keep it chronologically sorted
        current_time += datetime.timedelta(seconds=random.randint(1, 3600))
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/process_changes.sh"
    oracle_path = "/tests/oracle_processor"

    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.exists(oracle_path), f"Oracle missing: {oracle_path}"

    random.seed(42)

    for i in range(50):
        input_data = generate_log_stream()

        oracle_proc = subprocess.run([oracle_path], input=input_data, text=True, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on run {i}"

        agent_proc = subprocess.run(["/bin/bash", agent_script], input=input_data, text=True, capture_output=True)

        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Mismatch on run {i}.\n"
                f"Input:\n{input_data[:200]}...\n"
                f"Expected (Oracle):\n{oracle_proc.stdout[:200]}...\n"
                f"Actual (Agent):\n{agent_proc.stdout[:200]}...\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
