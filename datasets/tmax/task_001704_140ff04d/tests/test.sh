#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/csv_processor_oracle"
AGENT_PATH = "/home/user/csv_processor"
SOURCE_PATH = "/home/user/csv_processor.cpp"
NUM_TESTS = 10000


def generate_random_input(rng):
    id_val = "".join(rng.choices(string.digits, k=rng.randint(1, 5)))
    first_name_len = rng.randint(3, 8)
    first_name = rng.choice(string.ascii_uppercase) + "".join(
        rng.choices(string.ascii_lowercase, k=first_name_len)
    )
    last_name_len = rng.randint(4, 10)
    last_name = rng.choice(string.ascii_uppercase) + "".join(
        rng.choices(string.ascii_lowercase, k=last_name_len)
    )
    email_len = rng.randint(5, 10)
    email_prefix = "".join(rng.choices(string.ascii_lowercase, k=email_len))
    domain = rng.choice(["gmail", "yahoo", "hotmail"])
    email = f"{email_prefix}@{domain}.com"
    phone = "".join(rng.choices(string.digits, k=10))
    return f"{id_val},{first_name},{last_name},{email},{phone}\n"


def run_program(path, input_data, preexec_fn=None):
    return subprocess.run(
        [path],
        input=input_data,
        text=True,
        capture_output=True,
        check=True,
        timeout=1,
        preexec_fn=preexec_fn,
    ).stdout


def test_submission():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"

    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} must be a regular C++ source file"
    assert source_stat.st_size > 0, f"{SOURCE_PATH} is empty"

    assert os.path.exists(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"{ORACLE_PATH} is not a file"
    assert os.access(ORACLE_PATH, os.X_OK), f"{ORACLE_PATH} is not executable"
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent executable must not be a byte-identical copy of the oracle"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    corpus = [generate_random_input(rng) for _ in range(NUM_TESTS)]
    expected = []
    for input_data in corpus:
        expected.append(run_program(ORACLE_PATH, input_data))

    # The oracle was available for the requested reverse engineering, but must not
    # remain callable by the submitted program during verification.
    os.unlink(ORACLE_PATH)

    build_dir = tempfile.mkdtemp(prefix="csv_processor_build_")
    rebuilt_path = os.path.join(build_dir, "csv_processor")
    compile_proc = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", rebuilt_path, "-lcrypto", "-static"],
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert compile_proc.returncode == 0, (
        "Failed to compile /home/user/csv_processor.cpp:\n"
        + compile_proc.stdout
        + compile_proc.stderr
    )
    assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)

    # Preserve the original 10,000-case equivalence check on the submitted executable.
    for input_data, oracle_out in zip(corpus, expected):
        agent_out = run_program(AGENT_PATH, input_data)
        assert agent_out == oracle_out, (
            f"Mismatch on input: {input_data.strip()}\n"
            f"Expected (Oracle): {oracle_out!r}\n"
            f"Got (Agent):       {agent_out!r}"
        )

    # Also execute a fresh build of the requested C++ source in an empty chroot, so
    # wrappers and auxiliary copies of the oracle cannot satisfy the source check.
    jail = tempfile.mkdtemp(prefix="csv_processor_jail_")
    jailed_program = os.path.join(jail, "csv_processor")
    shutil.copy2(rebuilt_path, jailed_program)
    os.chmod(jailed_program, 0o755)
    os.chmod(jail, 0o755)

    def enter_jail():
        os.chroot(jail)
        os.chdir("/")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)

    for input_data, oracle_out in zip(corpus, expected):
        rebuilt_out = run_program("/csv_processor", input_data, preexec_fn=enter_jail)
        assert rebuilt_out == oracle_out, (
            f"Freshly compiled source mismatch on input: {input_data.strip()}\n"
            f"Expected (Oracle): {oracle_out!r}\n"
            f"Got (Rebuilt):     {rebuilt_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
