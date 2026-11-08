#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest


def test_panic_code_extracted():
    """Check if the panic code was correctly extracted from the video."""
    panic_code_path = "/home/user/panic_code.txt"
    assert os.path.isfile(panic_code_path), f"File {panic_code_path} is missing."

    with open(panic_code_path, "r") as f:
        content = f.read().strip()

    assert content == "0x8BADF00D", f"Expected panic code '0x8BADF00D', but got '{content}'"


def test_log_parser_compiled_and_executable():
    """Check if the log parser was compiled to the correct location."""
    compiled_parser_path = "/home/user/log_parser"
    assert os.path.isfile(compiled_parser_path), f"Compiled binary {compiled_parser_path} is missing."
    assert os.access(compiled_parser_path, os.X_OK), f"File {compiled_parser_path} is not executable."


def generate_fuzz_lines(n=10000):
    """Generate random log lines for fuzzing."""
    random.seed(42)
    lines = []
    chars = string.ascii_letters + string.digits + " !@#$%^&*()_+-=[]{}|;':\",./<>?"

    for _ in range(n):
        choice = random.random()
        if choice < 0.2:
            ts = "".join(random.choices(chars.replace("]", ""), k=random.randint(1, 20)))
            lvl = "".join(random.choices(chars.replace(":", ""), k=random.randint(1, 10)))
            msg = "".join(random.choices(chars, k=random.randint(1, 100)))
            lines.append(f"[{ts}] {lvl}: {msg}")
        elif choice < 0.4:
            ts = "".join(random.choices(chars.replace("]", ""), k=random.randint(1, 20)))
            lvl = "".join(random.choices(chars.replace(":", ""), k=random.randint(1, 10)))
            msg = "".join(random.choices(chars, k=random.randint(1, 100)))
            lines.append(f"[{ts} {lvl}: {msg}")
        elif choice < 0.6:
            ts = "".join(random.choices(chars.replace("]", ""), k=random.randint(1, 20)))
            lvl = "".join(random.choices(chars.replace(":", ""), k=random.randint(1, 10)))
            msg = "".join(random.choices(chars, k=random.randint(1, 100)))
            lines.append(f"[{ts}] {lvl} {msg}")
        elif choice < 0.8:
            lines.append("".join(random.choices(chars, k=random.randint(1025, 2048))))
        else:
            lines.append("".join(random.choices(chars, k=random.randint(0, 500))))

    # Explicitly exercise the 1024-byte boundary and logical lines larger than
    # common fixed input buffers. The prefix is 7 bytes long.
    lines.extend([
        "[t] L: " + "x" * 1017,
        "[t] L: " + "x" * 1018,
        "[t] L: " + "x" * 5000,
        "[] : ",
    ])
    return "\n".join(lines).encode("utf-8") + b"\n"


def reference_output(data):
    """Derive output directly from the format specified in the instruction."""
    raw_lines = data.split(b"\n")
    if raw_lines and raw_lines[-1] == b"":
        raw_lines.pop()

    output = []
    for line in raw_lines:
        if len(line) > 1024 or not line.startswith(b"["):
            output.append(b"INVALID")
            continue

        end_bracket = line.find(b"]", 1)
        if end_bracket < 0 or end_bracket + 1 >= len(line) or line[end_bracket + 1:end_bracket + 2] != b" ":
            output.append(b"INVALID")
            continue

        level_start = end_bracket + 2
        colon = line.find(b":", level_start)
        if colon < 0 or colon + 1 >= len(line) or line[colon + 1:colon + 2] != b" ":
            output.append(b"INVALID")
            continue

        level = line[level_start:colon]
        message = line[colon + 2:]
        output.append(b"Parsed: " + level + b" | " + message)

    return b"\n".join(output) + (b"\n" if output else b"")


def test_log_parser_fuzz_equivalence():
    """Fuzz the agent parser against answers derived from the specification."""
    agent_path = "/home/user/log_parser"
    fuzz_input = generate_fuzz_lines(10000)
    expected_stdout = reference_output(fuzz_input)

    try:
        agent_proc = subprocess.run(
            [agent_path], input=fuzz_input, capture_output=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent program timed out on fuzz inputs. It might be stuck in an infinite loop.")

    if agent_proc.returncode != 0:
        pytest.fail(f"Agent returned {agent_proc.returncode}. It may have crashed.")

    if agent_proc.stdout != expected_stdout:
        expected_lines = expected_stdout.split(b"\n")
        agent_lines = agent_proc.stdout.split(b"\n")
        input_lines = fuzz_input.split(b"\n")

        for i, (expected, actual) in enumerate(zip(expected_lines, agent_lines)):
            if expected != actual:
                inp = input_lines[i].decode("utf-8", errors="replace") if i < len(input_lines) else "<missing>"
                pytest.fail(
                    f"Output mismatch on input line {i + 1}.\n"
                    f"Input: {inp}\n"
                    f"Expected: {expected.decode('utf-8', errors='replace')}\n"
                    f"Got: {actual.decode('utf-8', errors='replace')}"
                )

        pytest.fail(
            f"Output line count mismatch. Expected lines: {len(expected_lines)}, "
            f"Agent lines: {len(agent_lines)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
