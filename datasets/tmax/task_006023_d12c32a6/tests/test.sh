#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import shlex
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/optimize.sh"
INPUT_PATH = "/home/user/metrics.jsonl"
OUTPUT_PATH = "/home/user/top_metrics.csv"


def test_optimize_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, \
        "optimize.sh must be an executable Bash script."


def expected_rows(records):
    expected = {}
    for record in records:
        host = record["host"]
        process = record["process"]
        memory = float(record["memory_mb"])
        if host not in expected or memory > expected[host][0]:
            expected[host] = (memory, process)
    return [(host, expected[host][1], expected[host][0]) for host in sorted(expected)]


def commands_from_trace(trace):
    commands = []
    for line in trace.splitlines():
        try:
            tokens = shlex.split(line)
        except ValueError:
            continue
        if tokens:
            commands.append(tokens)
    return commands


def command_occurrences(commands, names):
    matches = []
    for tokens in commands:
        for index, token in enumerate(tokens):
            if os.path.basename(token) in names:
                matches.append(tokens[index:])
                break
    return matches


def run_case(records):
    input_bytes = b"".join(
        (json.dumps(record, separators=(",", ":")) + "\n").encode("utf-8")
        for record in records
    )
    with open(INPUT_PATH, "wb") as f:
        f.write(input_bytes)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    trace_fd, trace_path = tempfile.mkstemp(prefix="optimize-trace-")
    os.close(trace_fd)
    env_fd, env_path = tempfile.mkstemp(prefix="bash-env-")
    with os.fdopen(env_fd, "w") as f:
        f.write("set -o functrace\n")
        f.write("trap 'printf \"%s\\n\" \"$BASH_COMMAND\" >> \"$OPTIMIZE_TRACE\"' DEBUG\n")

    env = os.environ.copy()
    env["BASH_ENV"] = env_path
    env["OPTIMIZE_TRACE"] = trace_path
    try:
        result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, env=env, timeout=30
        )
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
    finally:
        for path in (trace_path, env_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not created."

    with open(INPUT_PATH, "rb") as f:
        assert f.read() == input_bytes, "optimize.sh must read, not truncate or modify, metrics.jsonl."

    with open(OUTPUT_PATH, "r", newline="") as f:
        actual = list(csv.reader(f))
    assert all(len(row) == 3 for row in actual), \
        "Every output row must contain exactly host, process, and memory_mb."

    expected = expected_rows(records)
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} rows, but got {len(actual)}."
    for i, (row, wanted) in enumerate(zip(actual, expected), 1):
        host, process, memory_text = row
        expected_host, expected_process, expected_memory = wanted
        assert host == expected_host, \
            f"Host mismatch on line {i}: expected {expected_host}, got {host}"
        assert process == expected_process, \
            f"Process mismatch on line {i}: expected {expected_process}, got {process}"
        try:
            actual_memory = float(memory_text)
        except ValueError:
            raise AssertionError(f"Invalid memory value on line {i}: {memory_text!r}")
        assert abs(actual_memory - expected_memory) < 1e-6, \
            f"Memory mismatch on line {i}: expected {expected_memory}, got {actual_memory}"

    return commands_from_trace(trace)


def test_optimize_script_produces_correct_output_and_streams_with_required_tools():
    fixed = [
        {"host": "web03", "process": "small", "memory_mb": 99.9},
        {"host": "web01", "process": "old", "memory_mb": 12.25},
        {"host": "web02", "process": "worker", "memory_mb": 100.0},
        {"host": "web01", "process": "winner", "memory_mb": 4096.75},
        {"host": "web03", "process": "large", "memory_mb": 1000.01},
        {"host": "web02", "process": "tiny", "memory_mb": 9.0},
    ]

    rng = random.Random(secrets.randbits(128))
    hosts = [f"host{i:03d}" for i in range(41)]
    processes = [f"proc{i:02d}" for i in range(17)]
    random_records = []
    order = list(range(7000))
    rng.shuffle(order)
    for unique_value in order:
        random_records.append({
            "host": rng.choice(hosts),
            "process": rng.choice(processes),
            "memory_mb": unique_value + rng.randrange(1, 100) / 100.0,
        })

    commands = run_case(fixed) + run_case(random_records)

    jq_commands = command_occurrences(commands, {"jq"})
    sort_commands = command_occurrences(commands, {"sort"})
    awk_commands = command_occurrences(commands, {"awk", "gawk", "mawk"})
    assert jq_commands, "The executed Bash script must stream records through jq."
    assert sort_commands, "The executed Bash script must use sort for ordering."
    assert awk_commands, "The executed Bash script must use awk (or a compatible awk)."

    forbidden = command_occurrences(commands, {"python", "python3", "perl", "ruby", "node"})
    assert not forbidden, "The aggregation must be implemented with the required Bash streaming tools."

    for command in jq_commands:
        for arg in command[1:]:
            if arg == "--slurp" or (arg.startswith("-") and not arg.startswith("--") and "s" in arg[1:]):
                raise AssertionError("jq slurp mode (-s/--slurp) is not allowed.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
