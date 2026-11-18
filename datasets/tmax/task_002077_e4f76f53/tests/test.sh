#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/uptime-monitor/monitor.sh"
EXPECTED_KEY = "SRE_PROD_99382A"


def run_monitor(log_files, api_key=EXPECTED_KEY):
    env = os.environ.copy()
    env["API_KEY"] = api_key
    return subprocess.run(
        [SCRIPT_PATH] + log_files,
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_api_key_file():
    api_key_path = "/home/user/api_key.txt"
    assert os.path.isfile(api_key_path), f"The file {api_key_path} does not exist."

    with open(api_key_path, "r") as f:
        content = f.read()

    assert content in (EXPECTED_KEY, EXPECTED_KEY + "\n"), (
        f"The file {api_key_path} must contain exactly the correct API key."
    )


def test_final_score_file():
    final_score_path = "/home/user/final_score.txt"
    assert os.path.isfile(final_score_path), f"The file {final_score_path} does not exist."

    with open(final_score_path, "r") as f:
        content = f.read().strip()

    expected_score = "12750"
    assert content == expected_score, f"The file {final_score_path} contains '{content}', but expected '{expected_score}'."


def test_monitor_script_fixed_on_original_logs():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."

    log_files = [
        "/home/user/logs/server1.log",
        "/home/user/logs/server2.log",
    ]
    result = run_monitor(log_files)
    assert result.returncode == 0, f"The script crashed or returned a non-zero exit code. Error output: {result.stderr.strip()}"
    output = result.stdout.strip()
    assert output == "12750", f"The script output was '{output}', expected '12750'. The mathematical bug might not be fully fixed."


def test_monitor_handles_every_valid_day_and_dynamic_values():
    with tempfile.TemporaryDirectory(prefix="monitor-dynamic-") as temp_dir:
        # Exercise every possible day of a month independently, including all
        # leading-zero dates. Values are generated at verification time so the
        # expected output cannot be replaced by a fixed constant.
        for day in range(1, 32):
            uptime = secrets.randbelow(90000) + 1
            log_path = os.path.join(temp_dir, f"day-{day:02d}.log")
            with open(log_path, "w") as f:
                f.write(f"2024-01-{day:02d} {uptime}\n")

            result = run_monitor([log_path])
            assert result.returncode == 0, (
                f"The script failed for day {day:02d}: {result.stderr.strip()}"
            )
            expected = str(day * uptime)
            assert result.stdout.strip() == expected, (
                f"Incorrect score for day {day:02d}: got {result.stdout.strip()!r}, expected {expected!r}"
            )

        # Also verify accumulation across multiple independently generated logs.
        paths = []
        expected_total = 0
        for file_number in range(3):
            path = os.path.join(temp_dir, f"aggregate-{file_number}.log")
            paths.append(path)
            with open(path, "w") as f:
                for day in range(file_number + 1, 32, 3):
                    uptime = secrets.randbelow(50000) + 1
                    f.write(f"2024-01-{day:02d} {uptime}\n")
                    expected_total += day * uptime

        result = run_monitor(paths)
        assert result.returncode == 0, f"The script failed on dynamic logs: {result.stderr.strip()}"
        assert result.stdout.strip() == str(expected_total), (
            f"Incorrect aggregate score: got {result.stdout.strip()!r}, expected {expected_total!r}"
        )


def test_monitor_requires_correct_api_key():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".log") as log_file:
        log_file.write("2024-01-01 1\n")
        log_file.flush()
        result = run_monitor([log_file.name], api_key="WRONG_KEY")
    assert result.returncode != 0, "The script accepted an invalid API key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
