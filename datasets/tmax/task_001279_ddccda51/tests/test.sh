#!/bin/bash
mkdir -p /logs/verifier

# Preserve the original oracle availability assertions, then remove the oracle
# before exercising the submitted script so it cannot delegate to the binary.
if [[ ! -f /app/auth_validator || ! -x /app/auth_validator ]]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
if ! rm -f /app/auth_validator; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

AGENT_PATH = "/home/user/check_perm.sh"
N_TESTS = 500
PRINTABLE_ASCII = "".join(chr(i) for i in range(32, 127))


def expected_output(value):
    return "".join(f"{((ord(c) ^ 0x3A) + 5) & 0xff:02x}" for c in value) + "\n"


def run_agent(args):
    return subprocess.run(
        [AGENT_PATH, *args],
        capture_output=True,
        text=True,
        timeout=5,
    )


def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."

    with open(AGENT_PATH, "rb") as script_file:
        contents = script_file.read()
    assert not contents.startswith(b"\x7fELF"), "Submission must be a Bash script, not an executable binary."
    first_line = contents.splitlines()[0] if contents else b""
    assert first_line.startswith(b"#!") and b"bash" in first_line, "Submission must use a Bash shebang."


def test_oracle_is_unavailable_during_execution():
    assert not os.path.exists("/app/auth_validator"), "Oracle must not be available to the submitted script."


def test_exact_argument_count_behavior():
    no_arg = run_agent([])
    assert no_arg.returncode == 1
    assert no_arg.stdout == ""

    two_args = run_agent(["a", "b"])
    assert two_args.returncode == 1
    assert two_args.stdout == ""


def test_printable_ascii_equivalence():
    directed_inputs = [
        "",
        PRINTABLE_ASCII,
        PRINTABLE_ASCII[::-1],
        *list(PRINTABLE_ASCII),
    ]

    rng = secrets.SystemRandom()
    random_inputs = [
        "".join(rng.choice(PRINTABLE_ASCII) for _ in range(rng.randint(1, 128)))
        for _ in range(N_TESTS)
    ]

    for test_input in directed_inputs + random_inputs:
        agent_proc = run_agent([test_input])
        assert agent_proc.returncode == 0, (
            f"Agent script failed on input {test_input!r}. "
            f"Stderr: {agent_proc.stderr!r}"
        )
        assert agent_proc.stdout == expected_output(test_input), (
            f"Mismatch on input {test_input!r}.\n"
            f"Expected: {expected_output(test_input)!r}\n"
            f"Got: {agent_proc.stdout!r}"
        )

    assert not os.path.exists("/app/auth_validator"), "Submission recreated the oracle path."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
