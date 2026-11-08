#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import pytest


def generate_fuzz_input(seed):
    random.seed(seed)
    num_lines = random.randint(1, 50)
    lines = []

    # Avoid newlines and carriage returns in the base character set
    # to maintain the expected number of lines.
    chars = string.ascii_letters + string.digits + string.punctuation + ' \t'

    for _ in range(num_lines):
        length = random.randint(10, 500)
        line = "".join(random.choices(chars, k=length))

        # 20% chance to include a random 16-digit sequence
        if random.random() < 0.20:
            digits = "".join(random.choices(string.digits, k=16))
            insert_pos = random.randint(0, len(line))
            line = line[:insert_pos] + " " + digits + " " + line[insert_pos:]

        # 10% chance to include a 15-digit or 17-digit sequence
        if random.random() < 0.10:
            k = random.choice([15, 17])
            digits = "".join(random.choices(string.digits, k=k))
            insert_pos = random.randint(0, len(line))
            line = line[:insert_pos] + " " + digits + " " + line[insert_pos:]

        # 20% chance to include the project name
        if random.random() < 0.20:
            insert_pos = random.randint(0, len(line))
            line = line[:insert_pos] + "Hummingbird" + line[insert_pos:]

        # 20% chance to include the SQL injection payload
        if random.random() < 0.20:
            insert_pos = random.randint(0, len(line))
            line = line[:insert_pos] + "' OR 1=1 --" + line[insert_pos:]

        lines.append(line)

    result = "\n".join(lines)
    if random.random() < 0.5:
        result += "\n"

    return result


def expected_output(input_data):
    output = []
    for line in input_data.splitlines(keepends=True):
        has_newline = line.endswith('\n')
        clean_line = line[:-1] if has_newline else line
        clean_line = re.sub(r'(?<!\d)\d{16}(?!\d)', '[REDACTED_CC]', clean_line)
        clean_line = clean_line.replace('Hummingbird', '[REDACTED_PROJECT]')
        if "' OR 1=1 --" in clean_line:
            clean_line += " [CWE-89_DETECTED]"
        output.append(clean_line + ('\n' if has_newline else ''))
    return ''.join(output)


def test_fuzz_equivalence():
    agent_script = "/home/user/redactor.py"
    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(agent_script), f"Agent script is not a regular file: {agent_script}"

    # Run 1000 fuzz tests
    for i in range(1000):
        input_data = generate_fuzz_input(i)
        expected = expected_output(input_data)

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, (
            f"Agent script failed or crashed on input seed {i}.\n"
            f"Error output:\n{agent_proc.stderr}"
        )

        if expected != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on input seed {i}.\n\n"
                f"--- Input ---\n{input_data!r}\n\n"
                f"--- Expected Output ---\n{expected!r}\n\n"
                f"--- Actual Output (Agent) ---\n{agent_proc.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
