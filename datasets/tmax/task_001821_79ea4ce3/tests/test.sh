#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess

MASTER_PIN = 7392
AGENT_PATH = "/home/user/check_auth"
ULL_MAX = (1 << 64) - 1


def generate_test_cases(n=5000):
    random.seed(42)
    cases = []

    # 50% valid
    for _ in range(n // 2):
        userid = random.randint(1, 1000000)
        timestamp = random.randint(1, 1000000)
        signature = (userid * 3) + timestamp + MASTER_PIN
        cases.append(f"{userid}-{timestamp}-{signature}")

    # 50% invalid / malformed
    for _ in range(n - (n // 2)):
        choice = random.randint(0, 5)
        if choice == 0:
            userid = random.randint(1, 1000000)
            timestamp = random.randint(1, 1000000)
            signature = (userid * 3) + timestamp + MASTER_PIN + random.choice([-1, 1]) * random.randint(1, 100)
            cases.append(f"{userid}-{timestamp}-{signature}")
        elif choice == 1:
            userid = random.randint(-1000, -1)
            timestamp = random.randint(1, 1000)
            signature = (userid * 3) + timestamp + MASTER_PIN
            cases.append(f"{userid}-{timestamp}-{signature}")
        elif choice == 2:
            cases.append("".join(random.choices(string.ascii_letters + string.digits + "-", k=random.randint(5, 50))))
        elif choice == 3:
            cases.append("9" * random.randint(100, 500))
        elif choice == 4:
            cases.append(f"{random.randint(1,100)}-ABC-{random.randint(1,100)}")
        else:
            cases.append("10-20-30-40")

    random.shuffle(cases)
    return cases


def expected_output(token):
    match = re.fullmatch(r"([0-9]+)-([0-9]+)-([0-9]+)", token, flags=re.ASCII)
    if not match:
        return "INVALID"

    values = [int(part) for part in match.groups()]
    if any(value > ULL_MAX for value in values):
        return "INVALID"

    userid, timestamp, signature = values
    expected_signature = (userid * 3 + timestamp + MASTER_PIN) & ULL_MAX
    if userid > 0 and timestamp > 0 and signature == expected_signature:
        return "VALID"
    return "INVALID"


def run_executable(path, arg):
    try:
        result = subprocess.run(
            [path, arg],
            capture_output=True,
            text=True,
            timeout=1
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT", ""
    except Exception as exc:
        return -1, f"ERROR: {exc}", ""


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Expected executable at {AGENT_PATH} is missing."
    assert os.access(AGENT_PATH, os.X_OK), f"Expected file at {AGENT_PATH} to be executable."


def test_fuzz_equivalence():
    test_cases = generate_test_cases(5000)

    for i, case in enumerate(test_cases):
        expected = expected_output(case)
        agent_code, agent_out, _ = run_executable(AGENT_PATH, case)

        assert agent_out == expected, (
            f"Mismatch on test case {i+1}/{len(test_cases)}.\n"
            f"Input: {case!r}\n"
            f"Expected output: {expected!r}\n"
            f"Agent output: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
