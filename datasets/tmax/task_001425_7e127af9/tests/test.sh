#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import resource
import secrets
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/profiler.py"
TRACE_DIR = "/home/user/traces"
CORRUPT_LOG = "/home/user/corrupt_files.txt"
MISSING_LOG = "/home/user/missing_keys.txt"


def limited_fds():
    resource.setrlimit(resource.RLIMIT_NOFILE, (48, 48))


def run_profiler():
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=20,
        preexec_fn=limited_fds,
    )


def read_lines(path):
    with open(path, "r") as f:
        return f.read().splitlines()


def parse_total(stdout):
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    assert lines, "Profiler produced no output."
    match = re.fullmatch(
        r"Total CPU processed:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)",
        lines[-1],
    )
    assert match, f"Final output line was not the expected total: {lines[-1]!r}"
    return float(match.group(1))


def test_profiler_execution():
    """Test that the profiler script runs successfully with exit code 0."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    for path in (CORRUPT_LOG, MISSING_LOG):
        if os.path.exists(path):
            os.remove(path)

    result = run_profiler()
    assert result.returncode == 0, f"Profiler script failed to run. Stderr: {result.stderr}"
    assert "Total CPU processed:" in result.stdout, "Profiler script did not print the expected output."
    assert parse_total(result.stdout) == pytest.approx(9980.0)


def test_corrupt_files_log():
    """Test that the corrupt files log contains the correct filename."""
    assert os.path.isfile(CORRUPT_LOG), f"Log file {CORRUPT_LOG} was not created."

    with open(CORRUPT_LOG, "r") as f:
        content = f.read()

    assert "trace_542.json" in content, f"Expected 'trace_542.json' in {CORRUPT_LOG}, but got: {content}"
    assert content.splitlines() == ["trace_542.json"], \
        f"Corrupt log must contain exactly one filename per line, but got: {content!r}"


def test_missing_keys_log():
    """Test that the missing keys log contains the correct filename."""
    assert os.path.isfile(MISSING_LOG), f"Log file {MISSING_LOG} was not created."

    with open(MISSING_LOG, "r") as f:
        content = f.read()

    assert "trace_888.json" in content, f"Expected 'trace_888.json' in {MISSING_LOG}, but got: {content}"
    assert content.splitlines() == ["trace_888.json"], \
        f"Missing-key log must contain exactly one filename per line, but got: {content!r}"


def test_required_assertion_is_present():
    with open(SCRIPT_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assert) or not isinstance(node.test, ast.Compare):
            continue
        test = node.test
        if (
            isinstance(test.left, ast.Constant)
            and test.left.value == "cpu_util"
            and len(test.ops) == 1
            and isinstance(test.ops[0], ast.In)
            and len(test.comparators) == 1
            and isinstance(test.comparators[0], ast.Name)
            and test.comparators[0].id == "data"
        ):
            message_text = ast.unparse(node.msg) if node.msg is not None else ""
            if "Missing cpu_util in" in message_text and "filepath" in message_text:
                found = True
                break

    assert found, 'Required assertion `assert "cpu_util" in data, f"Missing cpu_util in {filepath}"` was not found.'


def test_profiler_on_unseen_traces_and_under_fd_limit():
    token = secrets.token_hex(8)
    backup_dir = f"/home/user/traces.verifier-backup-{token}"
    saved_logs = {}
    for path in (CORRUPT_LOG, MISSING_LOG):
        saved_logs[path] = open(path, "rb").read() if os.path.exists(path) else None

    os.rename(TRACE_DIR, backup_dir)
    os.makedirs(TRACE_DIR)

    corrupt_names = [f"sample_{secrets.token_hex(6)}.json" for _ in range(2)]
    missing_names = [f"sample_{secrets.token_hex(6)}.json" for _ in range(2)]
    expected_total = 0.0

    try:
        # More files than the imposed descriptor limit ensure leaked handles fail.
        for i in range(160):
            name = f"sample_{secrets.token_hex(6)}.json"
            value = (secrets.randbelow(200000) - 50000) / 1000.0
            expected_total += value
            with open(os.path.join(TRACE_DIR, name), "w") as f:
                json.dump({"timestamp": i, "cpu_util": value, "extra": token}, f)

        for name in corrupt_names:
            with open(os.path.join(TRACE_DIR, name), "w") as f:
                f.write('{"cpu_util": 12.5, "broken": [1, 2')

        for name in missing_names:
            with open(os.path.join(TRACE_DIR, name), "w") as f:
                json.dump({"timestamp": secrets.randbelow(1000000), "mem_util": 7.5}, f)

        for path in (CORRUPT_LOG, MISSING_LOG):
            if os.path.exists(path):
                os.remove(path)

        result = run_profiler()
        assert result.returncode == 0, f"Profiler failed on generated traces. Stderr: {result.stderr}"
        assert "Total CPU processed:" in result.stdout, "Profiler script did not print the expected output."
        assert parse_total(result.stdout) == pytest.approx(expected_total, rel=1e-10, abs=1e-7)

        assert os.path.isfile(CORRUPT_LOG), f"Log file {CORRUPT_LOG} was not created."
        assert os.path.isfile(MISSING_LOG), f"Log file {MISSING_LOG} was not created."
        corrupt_lines = read_lines(CORRUPT_LOG)
        missing_lines = read_lines(MISSING_LOG)
        assert len(corrupt_lines) == len(corrupt_names) and sorted(corrupt_lines) == sorted(corrupt_names), \
            f"Incorrect corrupt-file log: {corrupt_lines!r}"
        assert len(missing_lines) == len(missing_names) and sorted(missing_lines) == sorted(missing_names), \
            f"Incorrect missing-key log: {missing_lines!r}"
    finally:
        shutil.rmtree(TRACE_DIR, ignore_errors=True)
        os.rename(backup_dir, TRACE_DIR)
        for path, content in saved_logs.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
