#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

SCRIPT = "/home/user/process_changes.sh"
INPUT = "/home/user/config_changes.log"
INVALID = "/home/user/invalid_lines.log"
SUMMARY = "/home/user/hourly_summary.csv"

ORIGINAL_INPUT = """2024-05-01 00:15:32,nginx,RELOAD,SUCCESS
2024-05-01 00:45:11,iptables,ADD,FAIL
2024-05-01 01:10:00,sshd,RESTART,SUCCESS
2024-05-01 01:22:10,sshd,UPDATE,SUCCESS
2024-05-01 03:05:01,docker,START,SUCCESS
2024-05-01 05:59:59,kubelet,STOP,SUCCESS
INVALID LINE 1
2024-05-01 06:00:00,nginx,RELOAD,SUCCESS
2024-05-01 02:XX:00,bad,BAD,SUCCESS
"""


def write_input(lines):
    with open(INPUT, "w", newline="") as f:
        f.write("\n".join(lines) + "\n")


def run_script():
    return subprocess.run(
        [SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )


def read_lines(path):
    with open(path, "r", newline="") as f:
        return f.read().splitlines()


def test_script_exists_and_executable():
    script_path = "/home/user/process_changes.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_script_runs_on_original_input():
    with open(INPUT, "w", newline="") as f:
        f.write(ORIGINAL_INPUT)
    for path in (INVALID, SUMMARY):
        if os.path.lexists(path):
            os.remove(path)
    result = run_script()
    assert result.returncode == 0, (
        f"Script failed on the supplied input: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )


def test_invalid_lines_log():
    log_path = "/home/user/invalid_lines.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the script run?"

    expected_lines = [
        "INVALID LINE 1",
        "2024-05-01 02:XX:00,bad,BAD,SUCCESS"
    ]

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {log_path} does not match expected invalid lines."


def test_hourly_summary_csv():
    csv_path = "/home/user/hourly_summary.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist. Did the script run?"

    expected_lines = [
        "2024-05-01 00:00,1",
        "2024-05-01 01:00,2",
        "2024-05-01 02:00,0",
        "2024-05-01 03:00,1",
        "2024-05-01 04:00,0",
        "2024-05-01 05:00,1"
    ]

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {csv_path} does not match the expected time-based bucketing and gap-filling."


def test_generated_input_validation_aggregation_and_five_invalid_boundary():
    token = secrets.token_hex(5)
    counts = [(int(token[i], 16) % 4) for i in range(6)]
    # Ensure the generated case cannot accidentally be all zero.
    counts[int(token[-1], 16) % 6] += 1

    lines = []
    for hour, count in enumerate(counts):
        for n in range(count):
            minute = (7 * n + int(token[0], 16)) % 60
            second = (11 * n + int(token[1], 16)) % 60
            lines.append(
                f"2024-05-01 {hour:02d}:{minute:02d}:{second:02d},svc_{token},UPDATE,SUCCESS"
            )
        # Valid FAIL records must not be counted.
        lines.append(f"2024-05-01 {hour:02d}:58:57,svc_{token},DELETE,FAIL")

    # Valid records outside the requested window must not be counted.
    lines.extend([
        f"2024-04-30 23:59:59,svc_{token},START,SUCCESS",
        f"2024-05-01 06:00:00,svc_{token},STOP,SUCCESS",
        f"2024-05-02 02:00:00,svc_{token},RELOAD,SUCCESS",
    ])

    # Exactly five invalid records must be logged but must not trigger the gate.
    invalid = [
        f"INVALID {token}",
        f"2024/05/01 02:10:00,svc_{token},UPDATE,SUCCESS",
        f"2024-05-01 02:10:00,svc-{token},UPDATE,SUCCESS",
        f"2024-05-01 02:10:00,svc_{token},Update,SUCCESS",
        f"2024-05-01 02:10:00,svc_{token},UPDATE,PENDING",
    ]
    # Interleave invalid records so validation cannot assume they are trailing.
    lines.insert(1, invalid[0])
    lines.insert(len(lines) // 2, invalid[1])
    lines.extend(invalid[2:])

    write_input(lines)
    for path in (INVALID, SUMMARY):
        if os.path.lexists(path):
            os.remove(path)

    result = run_script()
    assert result.returncode == 0, (
        f"Exactly five invalid lines must not fail the quality gate; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(INVALID)
    assert read_lines(INVALID) == invalid

    expected = [f"2024-05-01 {hour:02d}:00,{counts[hour]}" for hour in range(6)]
    assert os.path.isfile(SUMMARY)
    assert read_lines(SUMMARY) == expected


def test_quality_gate_exits_two_and_skips_summary_generation():
    token = secrets.token_hex(8)
    invalid = [f"BROKEN LINE {token} {i}" for i in range(6)]
    lines = [
        f"2024-05-01 00:00:00,svc_{token},START,SUCCESS",
        invalid[0],
        f"2024-05-01 03:00:00,svc_{token},UPDATE,SUCCESS",
        *invalid[1:],
    ]
    write_input(lines)

    sentinel = f"SUMMARY-MUST-REMAIN-UNTOUCHED-{token}\n"
    with open(SUMMARY, "w", newline="") as f:
        f.write(sentinel)
    if os.path.lexists(INVALID):
        os.remove(INVALID)

    result = run_script()
    assert result.returncode == 2, (
        f"More than five invalid lines must exit with status 2, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert "QUALITY GATE FAILED" in result.stdout.splitlines()
    assert os.path.isfile(INVALID)
    assert read_lines(INVALID) == invalid
    with open(SUMMARY, "r", newline="") as f:
        assert f.read() == sentinel, "Hourly aggregation was not skipped after gate failure"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
