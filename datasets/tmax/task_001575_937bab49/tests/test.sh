#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE_PATH=/app/c2_decoder
ORACLE_MODE=$(stat -c '%a' "$ORACLE_PATH")
trap 'chmod "$ORACLE_MODE" "$ORACLE_PATH" 2>/dev/null || true' EXIT
# Keep the oracle available to the root verifier, but make it unavailable to the
# unprivileged account used to execute the submitted script.
chmod 700 "$ORACLE_PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import stat
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/c2_decoder"
AGENT_PATH = "/home/user/edge_decoder.sh"
N_TESTS = 500


def generate_random_hex(min_len=12, max_len=128):
    # Length must be even for valid hex strings
    length = random.choice(range(min_len, max_len + 1, 2))
    return ''.join(random.choice(string.hexdigits.lower()) for _ in range(length))


def allowed_tool_paths():
    allowed = set()
    packages = ("coreutils", "bash", "dash", "sed", "grep", "mawk", "findutils", "diffutils")
    for package in packages:
        result = subprocess.run(
            ["dpkg-query", "-L", package],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if result.returncode != 0:
            continue
        for path in result.stdout.splitlines():
            if path.startswith(("/bin/", "/usr/bin/")) and os.path.isfile(path) and os.access(path, os.X_OK):
                allowed.add(os.path.realpath(path))
    for path in ("/bin/bash", "/usr/bin/bash", "/bin/sh", "/usr/bin/sh"):
        if os.path.exists(path):
            allowed.add(os.path.realpath(path))
    return allowed


ALLOWED_TOOLS = allowed_tool_paths()
EXEC_RE = re.compile(r'(?:^|\s)execve\(("(?:[^"\\]|\\.)*")')


def assert_only_allowed_execs(trace_path):
    with open(trace_path, "r", encoding="utf-8", errors="replace") as trace:
        for line in trace:
            if "execve(" not in line or not re.search(r'\)\s+=\s+0\s*$', line):
                continue
            match = EXEC_RE.search(line)
            assert match, f"Could not parse executed command from trace: {line.rstrip()}"
            executed = ast.literal_eval(match.group(1))
            if executed == AGENT_PATH:
                continue
            resolved = os.path.realpath(executed)
            assert resolved in ALLOWED_TOOLS, (
                f"Submission executed a non-permitted helper: {executed}"
            )


def run_agent(payload):
    fd, trace_path = tempfile.mkstemp(prefix="edge_decoder_trace_", dir="/tmp")
    os.close(fd)
    try:
        result = subprocess.run(
            [
                "/usr/bin/strace", "-f", "-qq", "-e", "trace=execve",
                "-o", trace_path, "-u", "user", "--", AGENT_PATH, payload,
            ],
            capture_output=True,
            text=False,
            timeout=2,
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": "/home/user",
                "LANG": "C",
                "LC_ALL": "C",
            },
        )
        assert_only_allowed_execs(trace_path)
        return result
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."
    mode = os.stat(AGENT_PATH).st_mode
    assert stat.S_ISREG(mode), f"Agent artifact {AGENT_PATH} is not a regular file."
    with open(AGENT_PATH, "rb") as script:
        first_line = script.readline(512)
    assert not first_line.startswith(b"\x7fELF"), "Agent artifact must be a Bash script, not an ELF binary."
    assert re.match(
        rb'^#!(?:/bin/bash|/usr/bin/bash)(?:\s.*)?\r?\n?$', first_line
    ) or re.match(
        rb'^#!/usr/bin/env(?:\s+-S)?\s+bash(?:\s.*)?\r?\n?$', first_line
    ), "Agent artifact must use a Bash shebang."


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} is missing."

    random.seed(42)  # Fixed seed for reproducibility

    for _ in range(N_TESTS):
        fuzz_input = generate_random_hex()

        # The root verifier can execute the oracle, while the submitted script
        # is traced and run as the unprivileged user that cannot access it.
        oracle_result = subprocess.run(
            [ORACLE_PATH, fuzz_input],
            capture_output=True,
            text=False,
            timeout=2
        )

        agent_result = run_agent(fuzz_input)

        oracle_stdout = oracle_result.stdout
        agent_stdout = agent_result.stdout

        assert oracle_stdout == agent_stdout, (
            f"Output mismatch on input: {fuzz_input}\n"
            f"Oracle output (hex): {oracle_stdout.hex()}\n"
            f"Agent output (hex): {agent_stdout.hex()}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
