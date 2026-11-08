#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import uuid

import pytest


def test_problem_file_contents():
    problem_file = "/home/user/problem_file.txt"
    expected = "/home/user/logs/system_metrics.log"
    assert os.path.exists(problem_file), f"File {problem_file} does not exist."
    with open(problem_file, "r") as f:
        raw = f.read()
    content = raw.strip()
    assert content == expected, f"Incorrect content in {problem_file}: {content}"
    assert raw in (expected, expected + "\n"), f"{problem_file} must contain exactly one line with the absolute path."


def test_repro_go_behavior():
    repro_script = "/home/user/repro.go"
    assert os.path.exists(repro_script), f"File {repro_script} does not exist."

    compile_cmd = ["go", "build", "-o", "/tmp/repro", repro_script]
    compile_result = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_result.returncode == 0, f"Failed to compile {repro_script}:\n{compile_result.stderr}"

    # Preserve the original assertion against the known problematic file.
    run_cmd = ["/tmp/repro", "/home/user/logs/system_metrics.log"]
    try:
        subprocess.run(run_cmd, timeout=2, capture_output=True)
        pytest.fail(f"The script {repro_script} did not hang when run against the problematic file. It should block indefinitely.")
    except subprocess.TimeoutExpired:
        pass

    # It must not simply block for every argument.
    with tempfile.TemporaryDirectory(prefix="repro_check_") as td:
        regular = os.path.join(td, "regular_" + uuid.uuid4().hex)
        with open(regular, "wb") as f:
            f.write(os.urandom(97))
        regular_result = subprocess.run(["/tmp/repro", regular], timeout=2, capture_output=True)
        assert regular_result.returncode == 0, "repro.go must terminate successfully for a regular file."

        # Use an unpredictable FIFO and verify with strace that the reproduced
        # hang is specifically the blocking open of the supplied path.
        fifo = os.path.join(td, "fifo_" + uuid.uuid4().hex)
        os.mkfifo(fifo)
        trace_base = os.path.join(td, "trace")
        proc = subprocess.Popen(
            ["strace", "-ff", "-e", "trace=openat", "-o", trace_base, "/tmp/repro", fifo],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            time.sleep(1.5)
            assert proc.poll() is None, "repro.go did not block on a dynamically created FIFO."
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate(timeout=2)

        trace = ""
        for path in glob.glob(trace_base + "*"):
            with open(path, "r", errors="replace") as f:
                trace += f.read()
        matching = [line for line in trace.splitlines() if fifo in line and "openat(" in line]
        assert matching, "repro.go hung without attempting to open the supplied FIFO path."


def test_output_log_contents():
    output_log = "/home/user/output.log"
    assert os.path.exists(output_log), f"File {output_log} does not exist."
    with open(output_log, "r") as f:
        content = f.read()
    assert "All logs processed successfully." in content, f"Expected success message not found in {output_log}."
    for i in range(1, 4):
        expected = f"Processed 11 bytes from app_{i}.log"
        assert expected in content, f"Expected processed-log metric missing from {output_log}: {expected}"
    assert "system_metrics.log" not in content, "output.log claims the FIFO was processed."


def test_log_processor_go_behavior():
    script_path = "/home/user/log_processor.go"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    # Preserve the original run and timeout assertions.
    run_cmd = ["go", "run", script_path]
    try:
        result = subprocess.run(run_cmd, timeout=3, capture_output=True, text=True)
        assert result.returncode == 0, f"Script {script_path} failed with return code {result.returncode}:\n{result.stderr}"
        assert "All logs processed successfully." in result.stdout, "Script did not print the expected success message."
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script {script_path} timed out. It is still hanging on the FIFO.")


def test_log_processor_processes_regular_files_and_filters_nonregular_files():
    script_path = "/home/user/log_processor.go"
    binary = "/tmp/log_processor_checked"
    build = subprocess.run(["go", "build", "-o", binary, script_path], capture_output=True, text=True)
    assert build.returncode == 0, f"Failed to compile {script_path}:\n{build.stderr}"

    logs = "/home/user/logs"
    backup = "/home/user/logs.verifier_backup_" + uuid.uuid4().hex
    os.rename(logs, backup)
    os.mkdir(logs)
    sock = None
    try:
        token = uuid.uuid4().hex
        regular_data = {
            f"regular_a_{token}.log": os.urandom(113),
            f"regular_b_{token}.data": os.urandom(257),
        }
        for name, data in regular_data.items():
            with open(os.path.join(logs, name), "wb") as f:
                f.write(data)

        directory_name = f"directory_{token}.log"
        symlink_name = f"symlink_{token}.log"
        fifo_name = f"fifo_{token}.log"
        socket_name = f"socket_{token}.log"
        device_name = f"character_device_{token}.log"

        os.mkdir(os.path.join(logs, directory_name))
        os.symlink(os.path.join(logs, next(iter(regular_data))), os.path.join(logs, symlink_name))
        os.mkfifo(os.path.join(logs, fifo_name))
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(os.path.join(logs, socket_name))
        # A zero-length character device makes an attempted read observable as
        # a bogus "Processed 0 bytes" line without risking an unbounded read.
        os.mknod(os.path.join(logs, device_name), 0o666 | 0o020000, os.makedev(1, 3))

        try:
            result = subprocess.run([binary], timeout=3, capture_output=True, text=True)
        except subprocess.TimeoutExpired:
            pytest.fail("log_processor.go hung when the directory contained a FIFO and other non-regular files.")

        assert result.returncode == 0, f"Patched processor failed:\n{result.stderr}"
        assert "All logs processed successfully." in result.stdout

        for name, data in regular_data.items():
            expected = f"Processed {len(data)} bytes from {name}"
            assert expected in result.stdout, f"Regular file was not processed correctly: {expected}"

        for name in (directory_name, symlink_name, fifo_name, socket_name, device_name):
            assert name not in result.stdout, f"Non-regular file was processed instead of skipped: {name}"
    finally:
        if sock is not None:
            sock.close()
        if os.path.lexists(logs):
            shutil.rmtree(logs)
        os.rename(backup, logs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
