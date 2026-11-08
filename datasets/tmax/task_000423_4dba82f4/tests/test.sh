#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import sys
import random
import string
import pytest


def test_fping_build():
    source_dir = '/app/fping-5.1'
    binary_path = source_dir + '/src/fping'
    configure_path = source_dir + '/configure'
    makefile_am_path = source_dir + '/src/Makefile.am'

    assert os.path.isfile(configure_path), f"configure script not found at {configure_path}"
    assert os.access(configure_path, os.X_OK), "configure script is not executable."

    with open(makefile_am_path, encoding='utf-8') as source_file:
        makefile_am = source_file.read()
    assert not re.search(r'^\s*CC_BROKEN\s*=', makefile_am, re.MULTILINE), \
        "The injected CC_BROKEN assignment is still present in src/Makefile.am."

    assert os.path.isfile(source_dir + '/Makefile'), "Top-level Makefile was not generated."
    assert os.path.isfile(source_dir + '/src/Makefile'), "src/Makefile was not generated."
    assert os.path.isfile(binary_path), f"fping binary not found at {binary_path}. Did you compile it?"
    assert os.access(binary_path, os.X_OK), f"fping binary at {binary_path} is not executable."

    with open(binary_path, 'rb') as binary_file:
        assert binary_file.read(4) == b'\x7fELF', \
            "The fping artifact is not a compiled ELF binary."

    make_status = subprocess.run(
        ['make', '-q'], cwd=source_dir, capture_output=True, text=True
    )
    assert make_status.returncode == 0, \
        f"The fping build is missing or out of date. make -q returned {make_status.returncode}.\n{make_status.stdout}{make_status.stderr}"

    result = subprocess.run([binary_path, '-v'], capture_output=True, text=True)
    assert result.returncode == 0, f"fping -v failed with exit code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout + result.stderr
    assert "fping: Version 5.1" in output, f"Output does not contain 'fping: Version 5.1'. Output was:\n{output}"

    probe = subprocess.run(
        [binary_path, '-c', '1', '-t', '1000', '127.0.0.1'],
        capture_output=True,
        text=True,
        timeout=10,
    )
    probe_output = probe.stdout + probe.stderr
    assert probe.returncode == 0, \
        f"Compiled fping failed to ping localhost. Output was:\n{probe_output}"
    assert re.search(r'127\.0\.0\.1\s*:\s*xmt/rcv/%loss\s*=\s*1/1/0%', probe_output), \
        f"Compiled fping did not produce a valid localhost summary. Output was:\n{probe_output}"


def generate_fuzz_input():
    lines = []
    num_lines = random.randint(10, 500)
    for _ in range(num_lines):
        choice = random.choice(['garbage', 'valid_ipv4', 'valid_ipv6', 'interactive', 'ansi'])
        if choice == 'garbage':
            lines.append(''.join(random.choices(string.ascii_letters + string.digits + ' \t', k=random.randint(5, 50))) + '\n')
        elif choice == 'interactive':
            prefix = ''.join(random.choices(string.ascii_letters, k=5))
            lines.append(f"{prefix}interactive-prompt> " + ''.join(random.choices(string.ascii_letters, k=10)) + '\n')
        elif choice == 'valid_ipv4':
            ip = f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,255)}"
            loss = random.randint(0, 100)
            xmt = random.randint(10, 100)
            rcv = xmt - int(xmt * loss / 100)
            lines.append(f"{ip} : xmt/rcv/%loss = {xmt}/{rcv}/{loss}%\n")
        elif choice == 'valid_ipv6':
            ip = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
            loss = random.randint(0, 100)
            lines.append(f"{ip} : xmt/rcv/%loss = 100/100/{loss}%\n")
        elif choice == 'ansi':
            ip = f"10.0.0.{random.randint(1,255)}"
            loss = random.randint(0, 100)
            line = f"{ip} : xmt/rcv/%loss = 50/50/{loss}%\n"
            lines.append(f"\033[31m{line}\033[0m")
    return "".join(lines)


def test_uptime_parser_fuzz_equivalence():
    agent_path = '/home/user/uptime_parser'
    oracle_path = '/tests/uptime_parser_oracle.py'

    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent script at {agent_path} is not executable."
    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}."

    with open(agent_path, 'rb') as agent_file, open(oracle_path, 'rb') as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent parser must not be a byte-identical copy of the reference implementation."

    random.seed(42)

    for i in range(500):
        input_data = generate_fuzz_input()

        oracle_result = subprocess.run(
            [sys.executable, oracle_path], input=input_data, capture_output=True, text=True
        )
        assert oracle_result.returncode == 0, "Oracle script failed unexpectedly."

        agent_result = subprocess.run([agent_path], input=input_data, capture_output=True, text=True)

        assert agent_result.returncode == 0, f"Agent script failed with exit code {agent_result.returncode} on fuzz input {i}.\nStderr: {agent_result.stderr}"

        if agent_result.stdout != oracle_result.stdout:
            pytest.fail(
                f"Mismatch on fuzz input stream {i}.\n"
                f"--- Input ---\n{input_data}\n"
                f"--- Expected Output (Oracle) ---\n{oracle_result.stdout}\n"
                f"--- Actual Output (Agent) ---\n{agent_result.stdout}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
