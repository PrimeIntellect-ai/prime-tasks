#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/backup_repo/backup_manager.sh"
EXPECTED_LINE = "Total bytes: 10000000000000000000"


def run_script(path, *, env=None, trace=False):
    command = ["/bin/bash", "-x", path] if trace else [path]
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script timed out, indicating the infinite loop was not fixed.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed with error: {e.stderr}")


def nonempty_lines(output):
    return [line.strip() for line in output.splitlines() if line.strip()]


def test_api_key_recovered():
    api_key_path = "/home/user/api_key.txt"
    assert os.path.isfile(api_key_path), f"{api_key_path} does not exist"

    with open(api_key_path, "r") as f:
        content = f.read().strip()

    expected_key = "sk_live_8f7d6c5b4a392817"
    assert content == expected_key, f"API key recovered is incorrect. Expected {expected_key}, got {content}"


def test_output_file_correct():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, f"{output_path} is empty"
    assert lines[-1] == EXPECTED_LINE, f"Final output line is incorrect. Expected '{EXPECTED_LINE}', got '{lines[-1]}'"


def test_script_execution():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"

    result = run_script(SCRIPT_PATH)
    lines = nonempty_lines(result.stdout)
    assert len(lines) > 0, "Script produced no output"
    assert lines[-1] == EXPECTED_LINE, f"Script output is incorrect. Expected '{EXPECTED_LINE}', got '{lines[-1]}'"


def test_output_matches_fresh_execution():
    result = run_script(SCRIPT_PATH)
    with open("/home/user/output.txt", "r") as f:
        saved_lines = [line.strip() for line in f if line.strip()]
    actual_lines = nonempty_lines(result.stdout)
    assert saved_lines, "/home/user/output.txt is empty"
    assert actual_lines, "Script produced no output"
    assert saved_lines[-1] == actual_lines[-1], "output.txt does not contain the fixed script's result"


def test_script_uses_bc_or_awk():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "bc" in content or "awk" in content, "Script must use 'bc' or 'awk' to fix numerical instability."


def test_script_processes_unseen_large_node_values_with_bc_or_awk():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    rng = secrets.SystemRandom()
    values = [rng.randrange(2_500_000_000_000_000_000, 8_500_000_000_000_000_000) for _ in range(5)]
    expected = f"Total bytes: {sum(values)}"
    replacement = "nodes=(" + " ".join(f'\"{value}\"' for value in values) + ")"
    modified, count = re.subn(
        r"(?m)^[ \t]*nodes=\([^\n]*\)[ \t]*$",
        replacement,
        content,
    )
    assert count == 1, "Could not identify the script's node-value array for behavioral testing"

    with tempfile.TemporaryDirectory() as temp_dir:
        candidate = os.path.join(temp_dir, "backup_manager.sh")
        with open(candidate, "w") as f:
            f.write(modified)
        os.chmod(candidate, 0o755)

        tool_dir = os.path.join(temp_dir, "tools")
        os.mkdir(tool_dir)
        log_path = os.path.join(temp_dir, "arithmetic-tools.log")
        for tool, real_tool in (("bc", "/usr/bin/bc"), ("awk", "/usr/bin/awk"), ("gawk", "/usr/bin/gawk")):
            if not os.path.exists(real_tool):
                continue
            wrapper = os.path.join(tool_dir, tool)
            with open(wrapper, "w") as f:
                f.write("#!/bin/sh\n")
                f.write(f"printf '%s\\n' '{tool}' >> \"$ARITH_TOOL_LOG\"\n")
                f.write(f"exec {real_tool} \"$@\"\n")
            os.chmod(wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = tool_dir + os.pathsep + env.get("PATH", "")
        env["ARITH_TOOL_LOG"] = log_path
        result = run_script(candidate, env=env, trace=True)
        lines = nonempty_lines(result.stdout)
        assert lines, "Script produced no output for unseen node values"
        assert lines[-1] == expected, f"Script did not correctly sum unseen large node values. Expected '{expected}', got '{lines[-1]}'"

        invoked = ""
        if os.path.exists(log_path):
            with open(log_path, "r") as f:
                invoked = f.read()
        traced_tool = re.search(r"(?m)^\++\s+(?:/[^\s]*/)?(?:bc|g?awk)(?:\s|$)", result.stderr)
        assert invoked.strip() or traced_tool, "The working arithmetic path did not execute bc or awk"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
