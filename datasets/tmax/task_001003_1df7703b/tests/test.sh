#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string

AGENT_PATH = '/home/user/process_stream'
NUM_TESTS = 1000


def generate_random_inputs(n):
    random.seed(42)
    inputs = []

    num_invalid = int(n * 0.10)
    num_empty = int(n * 0.05)
    num_valid = n - num_invalid - num_empty

    for _ in range(num_empty):
        inputs.append('' if random.choice([True, False]) else '\n')

    invalid_chars = string.ascii_lowercase + string.digits + ''.join(
        c for c in string.punctuation if c != '.'
    )
    for _ in range(num_invalid):
        length = random.randint(1, 100)
        s = ''.join(random.choices(string.ascii_uppercase + '.' + invalid_chars, k=length))
        if not any(c in invalid_chars for c in s):
            s = random.choice(invalid_chars) + s[1:]
        inputs.append(s)

    for _ in range(num_valid):
        length = random.randint(1, 100)
        s = []
        for _ in range(length):
            if random.random() < 0.6:
                s.append('.')
            else:
                s.append(random.choice(string.ascii_uppercase))
        inputs.append(''.join(s))

    random.shuffle(inputs)
    return inputs


def expected_result(input_str):
    # Match bufio.Reader.ReadString('\n') and the oracle's CR/LF stripping.
    text = input_str.partition('\n')[0]
    if text.endswith('\r'):
        text = text[:-1]

    if not text or any(c != '.' and c not in string.ascii_uppercase for c in text):
        return 1, 'INVALID'

    result = []
    last_char = None
    fill_count = 0

    for c in text:
        if c == '.':
            if last_char is not None and fill_count < 3:
                result.append(last_char)
                fill_count += 1
            else:
                result.append('*')
        else:
            result.append(c)
            last_char = c
            fill_count = 0

    return 0, ''.join(result)


def run_executable(executable_path, input_str):
    try:
        result = subprocess.run(
            [executable_path],
            input=input_str.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2
        )
        return result.returncode, result.stdout.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired:
        return -1, 'TIMEOUT'
    except Exception as exc:
        return -2, str(exc)


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f'Agent executable not found at {AGENT_PATH}'
    assert os.access(AGENT_PATH, os.X_OK), f'Agent file is not executable: {AGENT_PATH}'


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f'Agent executable not found at {AGENT_PATH}'

    for i, input_str in enumerate(generate_random_inputs(NUM_TESTS)):
        expected_code, expected_out = expected_result(input_str)
        agent_code, agent_out = run_executable(AGENT_PATH, input_str)

        error_msg = (
            f'Mismatch on input {i}:\n'
            f'Input (repr): {input_str!r}\n'
            f'Expected output: {expected_out!r} (exit code {expected_code})\n'
            f'Agent output: {agent_out!r} (exit code {agent_code})'
        )

        assert agent_code == expected_code, error_msg
        assert agent_out == expected_out, error_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
