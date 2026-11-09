#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import urllib.parse


def generate_fuzz_lines(n=500):
    random.seed(42)
    keywords = ["GANDALF", "VOLDEMORT", "SAURON", "SKYWALKER"]
    lines = []
    for _ in range(n):
        length = random.randint(50, 200)
        decoded_chars = []
        while len(decoded_chars) < length:
            if random.random() < 0.15:
                decoded_chars.extend(random.choice(keywords))
            else:
                decoded_chars.append(random.choice(string.ascii_letters + string.digits + " "))

        decoded_str = "".join(decoded_chars)[:length]
        lines.append(urllib.parse.quote_plus(decoded_str))
    return lines


def calculate_expected(lines, keywords):
    expected = []
    history = []

    for encoded_line in lines:
        decoded = urllib.parse.unquote_plus(encoded_line)
        replacements = 0

        for word in keywords:
            replacements += decoded.count(word)
            decoded = decoded.replace(word, "[REDACTED]")

        history.append(replacements)
        rolling_sum = sum(history[-3:])
        expected.append(f"{decoded}\t{rolling_sum}")

    return expected


def test_fuzz_equivalence():
    agent_bin = "/home/user/cleaner"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

    keywords = ["GANDALF", "VOLDEMORT", "SAURON", "SKYWALKER"]
    dict_content = "\n".join(keywords) + "\n"
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(dict_content)
        dict_path = f.name

    try:
        lines = generate_fuzz_lines(500)
        input_data = "\n".join(lines) + "\n"
        expected_lines = calculate_expected(lines, keywords)

        agent_proc = subprocess.run(
            [agent_bin, dict_path],
            input=input_data,
            text=True,
            capture_output=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent program failed to run or crashed: {agent_proc.stderr}"
        )

        agent_lines = agent_proc.stdout.splitlines()
        assert len(expected_lines) == len(agent_lines), (
            f"Output line count mismatch. Expected {len(expected_lines)}, "
            f"got {len(agent_lines)}"
        )

        for i, (expected_line, agent_line) in enumerate(zip(expected_lines, agent_lines)):
            assert expected_line == agent_line, (
                f"Mismatch on line {i + 1}.\n"
                f"Input:    {lines[i]}\n"
                f"Expected: {expected_line}\n"
                f"Agent:    {agent_line}"
            )
    finally:
        if os.path.exists(dict_path):
            os.remove(dict_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
