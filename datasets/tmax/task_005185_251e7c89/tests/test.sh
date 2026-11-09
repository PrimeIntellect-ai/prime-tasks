#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import stat
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/dataset_encoder"
AGENT_PATH = "/home/user/encoder"
SOURCE_PATH = "/home/user/encoder.rs"


def generate_random_input(length):
    charset = string.ascii_letters + string.digits + " ,"
    return "".join(random.choice(charset) for _ in range(length))


def run_executable(executable_path, input_data, drop_privileges=False):
    preexec_fn = None
    if drop_privileges:
        account = pwd.getpwnam("user")

        def become_user():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        preexec_fn = become_user

    result = subprocess.run(
        [executable_path],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2,
        preexec_fn=preexec_fn,
    )
    assert result.returncode == 0, (
        f"{executable_path} exited with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout.decode("utf-8")


def derived_output(input_data):
    data = input_data.encode("utf-8")[:4095]
    if data.endswith(b"\n"):
        data = data[:-1]
    if b"\0" in data:
        data = data.split(b"\0", 1)[0]

    # C strtok skips empty fields, including leading, trailing, and repeated commas.
    tokens = [token for token in data.split(b",") if token]
    if not tokens:
        return "0\n"

    vowels = set(b"aeiouAEIOU")
    values = []
    for token in tokens:
        vowel_count = sum(byte in vowels for byte in token)
        values.append(str((len(token) * 7 + vowel_count * 3) % 256))
    return " ".join(values) + "\n"


def test_final_submission():
    assert os.path.lexists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), f"{AGENT_PATH} must not be a symlink"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    assert open(AGENT_PATH, "rb").read(4) == b"\x7fELF", f"{AGENT_PATH} is not an ELF binary"
    assert not (os.stat(AGENT_PATH).st_mode & (stat.S_ISUID | stat.S_ISGID)), "setuid/setgid binaries are not allowed"

    assert os.path.lexists(SOURCE_PATH), f"Rust source not found at {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must not be a symlink"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"

    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    with open(AGENT_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submitted executable is byte-identical to the oracle"

    random.seed(42)
    inputs = ["", "\n", "a,b,c\n"]
    for _ in range(997):
        length = random.randint(0, 1024)
        inp = generate_random_input(length)
        if random.random() < 0.5:
            inp += "\n"
        inputs.append(inp)

    oracle_outputs = []
    for i, inp in enumerate(inputs):
        oracle_out = run_executable(ORACLE_PATH, inp)
        expected = derived_output(inp)
        assert oracle_out == expected, f"Internal expected-output mismatch on input {i}"
        oracle_outputs.append(oracle_out)

    # Make the proprietary executable unavailable while compiling and exercising
    # the submission, so a Rust wrapper cannot delegate its work to the oracle.
    hidden_dir = tempfile.mkdtemp(prefix="hidden-oracle-")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "dataset_encoder")
    os.rename(ORACLE_PATH, hidden_oracle)

    build_dir = tempfile.mkdtemp(prefix="rust-build-")
    account = pwd.getpwnam("user")
    os.chown(build_dir, account.pw_uid, account.pw_gid)
    rebuilt_path = os.path.join(build_dir, "encoder")

    try:
        def become_user():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        compile_result = subprocess.run(
            ["rustc", SOURCE_PATH, "-O", "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            preexec_fn=become_user,
        )
        assert compile_result.returncode == 0, (
            "encoder.rs did not compile successfully with rustc:\n" +
            compile_result.stderr.decode("utf-8", errors="replace")
        )
        assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)
        assert open(rebuilt_path, "rb").read(4) == b"\x7fELF"

        for i, (inp, oracle_out) in enumerate(zip(inputs, oracle_outputs)):
            try:
                agent_out = run_executable(AGENT_PATH, inp, drop_privileges=True)
                rebuilt_out = run_executable(rebuilt_path, inp, drop_privileges=True)
            except subprocess.TimeoutExpired:
                pytest.fail(f"Submission timed out on input {i} (length {len(inp)})")
            except Exception as exc:
                pytest.fail(f"Submission failed on input {i}: {exc}")

            if agent_out != oracle_out or rebuilt_out != oracle_out:
                display_inp = inp if len(inp) <= 100 else inp[:100] + "... (truncated)"
                pytest.fail(
                    f"Mismatch on input {i}:\n"
                    f"Input: {display_inp!r}\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Agent output: {agent_out!r}\n"
                    f"Recompiled Rust output: {rebuilt_out!r}"
                )
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
