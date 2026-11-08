#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import signal
import subprocess
import pytest

SCRIPT_PATH = "/home/user/data_pipeline/process.sh"
LOG_PATH = "/home/user/data_pipeline/events.log"
OUTPUT_PATH = "/home/user/data_pipeline/output.txt"

EXPECTED_ORIGINAL = [
    "101 cycle detected",
    "102 cycle detected",
    "103 cycle detected",
    "201 terminates normally",
    "202 terminates normally",
    "301 cycle detected",
    "401 terminates normally",
    "402 terminates normally",
    "403 terminates normally",
]


def run_script(timeout=5):
    proc = subprocess.Popen(
        ["/bin/bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        pytest.fail(f"{SCRIPT_PATH} did not terminate within {timeout} seconds")
    assert proc.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {proc.returncode}.\n"
        f"stderr:\n{stderr}"
    )
    return stdout


def expected_for_graph(order, refs):
    result = []
    for start in order:
        visited = set()
        current = start
        while True:
            if current in visited:
                result.append(f"{start} cycle detected")
                break
            visited.add(current)
            next_ref = refs[current]
            if next_ref is None:
                result.append(f"{start} terminates normally")
                break
            current = next_ref
    return result


def test_output_file_exists():
    output_path = "/home/user/data_pipeline/output.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist. Did you run the script and redirect the output?"


def test_output_file_content():
    output_path = "/home/user/data_pipeline/output.txt"
    assert os.path.isfile(output_path), "Output file missing."

    expected_lines = EXPECTED_ORIGINAL

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, (
        f"The content of {output_path} does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(lines)}"
    )


def test_process_script_is_bash():
    script_path = "/home/user/data_pipeline/process.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    # Check that it's not a python or perl script
    assert "import " not in content or "python" not in content.splitlines()[0].lower(), "The script appears to be written in Python. It must be written in Bash."
    assert "perl" not in content.splitlines()[0].lower(), "The script appears to be written in Perl. It must be written in Bash."


def test_script_executes_on_original_log():
    stdout = run_script()
    assert stdout.splitlines() == EXPECTED_ORIGINAL, (
        "Running process.sh on the supplied events.log did not produce the required output.\n"
        f"Got:\n{stdout}"
    )


def test_script_detects_cycles_on_generated_logs():
    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    try:
        for _ in range(2):
            ids = []
            while len(ids) < 12:
                candidate = str(100000 + secrets.randbelow(900000))
                if candidate not in ids:
                    ids.append(candidate)

            # Includes a three-node cycle, a terminating chain, a self-cycle,
            # another terminating chain, and a chain entering a two-node cycle.
            ref_indexes = [1, 2, 0, 4, None, 5, 7, 8, None, 10, 11, 10]
            refs = {
                ids[i]: (None if target is None else ids[target])
                for i, target in enumerate(ref_indexes)
            }
            order = list(ids)
            random.SystemRandom().shuffle(order)

            with open(LOG_PATH, "w") as f:
                for event_id in order:
                    ref = "NONE" if refs[event_id] is None else refs[event_id]
                    f.write(f"EVENT: {event_id}, REF: {ref}\n")

            expected = expected_for_graph(order, refs)
            stdout = run_script()
            actual = stdout.splitlines()
            assert actual == expected, (
                "process.sh failed on a generated event graph.\n"
                f"Expected:\n{chr(10).join(expected)}\n"
                f"Got:\n{chr(10).join(actual)}"
            )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
