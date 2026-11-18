#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/net_monitor.cpp"
EXECUTABLE_PATH = "/home/user/net_monitor"
LOG_PATH = "/home/user/network_log.txt"
RX_PATH = "/sys/class/net/lo/statistics/rx_bytes"
TX_PATH = "/sys/class/net/lo/statistics/tx_bytes"
OUTPUT_PATTERN = re.compile(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] RX: (\d+) TX: (\d+)')
TOKYO = datetime.timezone(datetime.timedelta(hours=9))


def read_counter(path):
    with open(path, "r") as f:
        return int(f.read().strip())


def run_and_validate_monitor(path):
    rx_before = read_counter(RX_PATH)
    tx_before = read_counter(TX_PATH)
    started = datetime.datetime.now(datetime.timezone.utc)

    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    result = subprocess.run(
        [path],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )

    finished = datetime.datetime.now(datetime.timezone.utc)
    rx_after = read_counter(RX_PATH)
    tx_after = read_counter(TX_PATH)

    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert re.fullmatch(OUTPUT_PATTERN.pattern + r'\n?', result.stdout), (
        f"{path} did not print exactly the required format. Got: {result.stdout!r}"
    )

    match = OUTPUT_PATTERN.fullmatch(result.stdout.rstrip("\n"))
    timestamp_str, rx_str, tx_str = match.groups()
    rx = int(rx_str)
    tx = int(tx_str)

    assert rx_before <= rx <= rx_after, (
        f"Reported RX {rx} was not the loopback rx_bytes value observed during execution "
        f"({rx_before}..{rx_after})."
    )
    assert tx_before <= tx <= tx_after, (
        f"Reported TX {tx} was not the loopback tx_bytes value observed during execution "
        f"({tx_before}..{tx_after})."
    )

    logged_time = datetime.datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=TOKYO)
    assert started - datetime.timedelta(seconds=2) <= logged_time <= finished + datetime.timedelta(seconds=2), (
        f"Timestamp {timestamp_str} was not the current Asia/Tokyo time during execution."
    )


def test_cpp_file_exists():
    path = SOURCE_PATH
    assert os.path.isfile(path), f"The C++ source file {path} does not exist."


def test_executable_exists_and_executable():
    path = EXECUTABLE_PATH
    assert os.path.isfile(path), f"The executable {path} does not exist."
    assert os.access(path, os.X_OK), f"The file {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {path} is not a compiled ELF executable."


def test_log_file_format_and_values():
    log_path = LOG_PATH
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    # Check format exactly
    pattern = r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] RX: (\d+) TX: (\d+)$'
    match = re.match(pattern, content)
    assert match is not None, f"The content of {log_path} does not match the exact format required. Got: {content}"

    timestamp_str, rx_str, tx_str = match.groups()

    # Check that traffic was generated (RX and TX > 0)
    rx = int(rx_str)
    tx = int(tx_str)
    assert rx > 0, f"RX bytes must be strictly greater than 0, but got {rx}. Local traffic simulation may have failed."
    assert tx > 0, f"TX bytes must be strictly greater than 0, but got {tx}. Local traffic simulation may have failed."
    assert rx <= read_counter(RX_PATH), f"Logged RX value {rx} exceeds the current loopback rx_bytes counter."
    assert tx <= read_counter(TX_PATH), f"Logged TX value {tx} exceeds the current loopback tx_bytes counter."

    # Validate timezone (Asia/Tokyo is UTC+9)
    log_time = datetime.datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    log_time = log_time.replace(tzinfo=datetime.timezone(datetime.timedelta(hours=9)))

    mtime = os.path.getmtime(log_path)
    file_time = datetime.datetime.fromtimestamp(mtime, datetime.timezone.utc)

    # Allow a small difference (e.g., 60 seconds) between file creation and logged time
    diff = abs((log_time - file_time).total_seconds())
    assert diff <= 60, (
        f"Logged time '{timestamp_str}' does not match the file's modification time in Asia/Tokyo. "
        f"File modified at {file_time.strftime('%Y-%m-%d %H:%M:%S')} UTC."
    )


def test_submitted_executable_reads_live_sysfs_values():
    run_and_validate_monitor(EXECUTABLE_PATH)


def test_source_compiles_and_reads_live_sysfs_values():
    with tempfile.TemporaryDirectory(prefix="net-monitor-verify-") as directory:
        compiled_path = os.path.join(directory, "net_monitor")
        result = subprocess.run(
            ["g++", SOURCE_PATH, "-o", compiled_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        assert result.returncode == 0, f"The submitted C++ source did not compile with g++: {result.stderr}"
        run_and_validate_monitor(compiled_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
