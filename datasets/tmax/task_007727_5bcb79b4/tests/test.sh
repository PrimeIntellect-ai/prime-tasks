#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

FIXED_SCRIPT = "/home/user/parse_pcap_fixed.sh"
ORIGINAL_LOG = "/home/user/traffic.log"


def run_script(log_path, timeout=5, restricted_path=False):
    env = os.environ.copy()
    if restricted_path:
        env["PATH"] = "/nonexistent"
    try:
        return subprocess.run(
            [FIXED_SCRIPT, log_path],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script {FIXED_SCRIPT} timed out, indicating an infinite loop.")


def test_bug_line():
    bug_line_path = "/home/user/bug_line.txt"
    assert os.path.exists(bug_line_path), f"File {bug_line_path} does not exist."
    with open(bug_line_path, "r") as f:
        content = f.read().strip()
    assert content == "432", f"Expected bug_line.txt to contain '432', got '{content}'."


def test_total_bytes():
    total_bytes_path = "/home/user/total_bytes.txt"
    assert os.path.exists(total_bytes_path), f"File {total_bytes_path} does not exist."
    with open(total_bytes_path, "r") as f:
        content = f.read().strip()
    assert content == "99850", f"Expected total_bytes.txt to contain '99850', got '{content}'."


def test_fixed_script():
    assert os.path.exists(FIXED_SCRIPT), f"File {FIXED_SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(FIXED_SCRIPT).st_mode), f"{FIXED_SCRIPT} is not a regular file."

    st = os.stat(FIXED_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {FIXED_SCRIPT} is not executable."

    with open(FIXED_SCRIPT, "rb") as f:
        raw = f.read()
    assert b"\x00" not in raw, "The fixed script must be a text Bash script."
    source = raw.decode("utf-8")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.fullmatch(r"#!\s*/(?:usr/)?bin/bash", first_line), \
        "The fixed parser must be implemented as a Bash script."
    for interpreter in ("python", "awk", "perl", "ruby", "node", "php"):
        assert not re.search(rf"\b{interpreter}\w*\b", source, re.IGNORECASE), \
            f"The parsing logic must remain in Bash, not {interpreter}."

    syntax = subprocess.run(["/bin/bash", "-n", FIXED_SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Bash syntax check failed: {syntax.stderr}"

    result = run_script(ORIGINAL_LOG)
    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()
    expected_output = "Total: 99850"
    assert expected_output in output, f"Expected output to contain '{expected_output}', got '{output}'."
    assert result.stderr.strip() == "", f"Expected no stderr output, got '{result.stderr}'"


def test_fixed_script_on_derived_inputs():
    rng = secrets.SystemRandom()
    cases = [
        [],
        [0],
        [37],
        [0, 12, 0, 9, 0],
        [5, 7, 11, 0],
    ]
    for _ in range(5):
        lengths = [rng.randrange(0, 100000) for _ in range(rng.randrange(20, 150))]
        lengths[rng.randrange(len(lengths))] = 0
        cases.append(lengths)

    with tempfile.TemporaryDirectory() as td:
        for case_number, lengths in enumerate(cases):
            log_path = os.path.join(td, f"capture_{case_number}_{rng.getrandbits(64):016x}.log")
            with open(log_path, "w") as f:
                for index, length in enumerate(lengths):
                    f.write(
                        f"2026-01-01T00:00:{index % 60:02d}Z "
                        f"192.0.2.{index % 250 + 1} 198.51.100.1 TCP {length}\n"
                    )

            result = run_script(log_path, restricted_path=True)
            expected = f"Total: {sum(lengths)}"
            assert result.returncode == 0, \
                f"Script failed on generated input with code {result.returncode}: {result.stderr}"
            assert result.stderr.strip() == "", \
                f"Script wrote an error on generated input: {result.stderr}"
            assert result.stdout.strip() == expected, \
                f"Expected '{expected}' for generated input, got '{result.stdout.strip()}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
