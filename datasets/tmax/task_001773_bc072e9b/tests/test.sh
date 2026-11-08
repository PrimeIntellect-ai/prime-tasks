#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/legacy_token_gen"
AGENT_PATH = "/home/user/my_token_gen"


def test_agent_program_exists_and_executable():
    """Test that the agent's token generator script exists and is executable."""
    assert os.path.exists(AGENT_PATH), f"Agent program missing at {AGENT_PATH}. You must create your script here."
    assert os.path.isfile(AGENT_PATH), f"Agent path {AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program at {AGENT_PATH} is not marked as executable."

    # The requested artifact is a standalone script, not a copied ELF oracle.
    with open(AGENT_PATH, "rb") as f:
        assert f.read(2) == b"#!", f"Agent program at {AGENT_PATH} must be an executable script with a shebang."


def test_fuzz_equivalence_without_oracle_available():
    """Compare unpredictable cases, then run the agent after removing the oracle."""
    assert os.path.exists(ORACLE_PATH), f"Oracle program missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle program at {ORACLE_PATH} is not executable"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent submission must not be a byte-identical copy of the oracle."

    oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    rng = secrets.SystemRandom()
    chars = string.ascii_letters + string.digits

    # Fresh, verifier-time inputs prevent a fixed answer table.
    inputs = []
    for length in (1, 2, 7, 8, 16, 32, 64, 128):
        inputs.append(''.join(rng.choice(chars) for _ in range(length)))
    for _ in range(72):
        length = rng.randint(1, 128)
        inputs.append(''.join(rng.choice(chars) for _ in range(length)))

    expected = []
    for test_input in inputs:
        oracle_proc = subprocess.run(
            [ORACLE_PATH, test_input], capture_output=True, text=True, timeout=5
        )
        assert oracle_proc.returncode == 0, f"Oracle program failed unexpectedly on input '{test_input}'"
        expected.append(oracle_proc.stdout.strip())

    # Keep the oracle only in verifier memory while exercising the submission.
    # A wrapper around /app/legacy_token_gen therefore cannot pass.
    os.unlink(ORACLE_PATH)
    try:
        assert not os.path.exists(ORACLE_PATH), "Oracle was not removed before agent execution"
        for i, (test_input, oracle_output) in enumerate(zip(inputs, expected), 1):
            agent_proc = subprocess.run(
                [AGENT_PATH, test_input], capture_output=True, text=True, timeout=5
            )
            assert agent_proc.returncode == 0, (
                f"Agent program failed on input '{test_input}'.\nStderr: {agent_proc.stderr}"
            )
            agent_output = agent_proc.stdout.strip()
            assert agent_output == oracle_output, (
                f"Output mismatch on fuzz iteration {i} for input '{test_input}'.\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent):       {agent_output}"
            )
    finally:
        fd, temporary_path = tempfile.mkstemp(prefix=".legacy_token_gen.restore-", dir="/app")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(oracle_bytes)
            os.chmod(temporary_path, oracle_mode)
            os.replace(temporary_path, ORACLE_PATH)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
