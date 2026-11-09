#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import secrets
import shutil
import string
import subprocess
import tempfile

AGENT_SCRIPT = "/home/user/token_gen.sh"
ORACLE_BIN = "/app/auth_module"
SALT = b"R3d0ct0ber"
USER = pwd.getpwnam("user")


def expected_token(value):
    # auth_module stores at most 255 input bytes, reverses that buffer, and
    # appends as much of the salt as remains in the 255-byte buffer.
    data = value.encode("ascii")[:255]
    data = data[::-1]
    data += SALT[:255 - len(data)]
    return hashlib.md5(data).hexdigest()


def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_agent(args):
    env = os.environ.copy()
    env["HOME"] = USER.pw_dir
    return subprocess.run(
        [AGENT_SCRIPT, *args],
        capture_output=True,
        text=True,
        env=env,
        preexec_fn=demote_to_user,
        timeout=10,
    )


def assert_agent_output(value, expected):
    proc = run_agent([value])
    assert proc.returncode == 0, f"Agent script failed on input: {value!r}"
    assert proc.stdout.strip() == expected, (
        f"Mismatch on input {value!r}.\n"
        f"Expected output: {expected}\n"
        f"Agent output:    {proc.stdout.strip()}"
    )
    assert proc.stdout == expected + "\n", (
        f"Agent script must output only the token and one newline for {value!r}"
    )
    assert proc.stderr == "", f"Agent script wrote to stderr for {value!r}"


def test_token_gen_sh_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is not a file."
    assert not os.path.islink(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} must not be a symlink."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

    with open(AGENT_SCRIPT, "rb") as handle:
        source = handle.read()
    assert b"\x00" not in source, "token_gen.sh must be a text Bash script."
    first_line = source.splitlines()[0] if source else b""
    assert first_line.startswith(b"#!") and b"bash" in first_line.lower(), (
        "token_gen.sh must have a Bash shebang."
    )


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} missing."
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} missing."

    # Move the oracle into a root-only directory before invoking the candidate.
    # The verifier can still exercise it, but token_gen.sh cannot delegate to it.
    hidden_dir = tempfile.mkdtemp(prefix="token-oracle-")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle")
    os.rename(ORACLE_BIN, hidden_oracle)

    try:
        # Preserve the original deterministic oracle-equivalence assertions.
        random.seed(42)
        charset = string.ascii_letters + string.digits
        for _ in range(100):
            length = random.randint(5, 20)
            fuzz_input = ''.join(random.choice(charset) for _ in range(length))

            oracle_proc = subprocess.run(
                [hidden_oracle, fuzz_input],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on input: {fuzz_input}"
            oracle_output = oracle_proc.stdout.strip()

            independently_derived = expected_token(fuzz_input)
            assert oracle_output == independently_derived, (
                f"Oracle disagrees with independently derived result for {fuzz_input!r}"
            )
            assert_agent_output(fuzz_input, oracle_output)

        # Exercise fresh, non-hardcodable inputs with independently derived answers.
        secure_random = secrets.SystemRandom()
        cases = [
            "A",
            "0",
            "aB3",
            "Z" * 254,
            "Y" * 255,
            "X" * 256,
            "Ab9" * 200,
        ]
        for _ in range(2000):
            length = secure_random.randint(1, 128)
            cases.append(''.join(secure_random.choice(charset) for _ in range(length)))

        for fuzz_input in cases:
            assert_agent_output(fuzz_input, expected_token(fuzz_input))

        # The interface must accept exactly one argument, as does auth_module.
        no_arg = run_agent([])
        assert no_arg.returncode != 0, "Agent script must reject zero arguments."
        two_args = run_agent(["abc", "def"])
        assert two_args.returncode != 0, "Agent script must reject more than one argument."
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_BIN)
        shutil.rmtree(hidden_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
