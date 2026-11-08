#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import shutil
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/seq_scorer"
AGENT_PATH = "/home/user/my_scorer.sh"
NUM_TESTS = 200

ALLOWED_EXECUTABLES = {
    AGENT_PATH,
    "/bin/sh",
    "/usr/bin/sh",
    "/bin/dash",
    "/usr/bin/dash",
    "/bin/bash",
    "/usr/bin/bash",
    "/bin/awk",
    "/usr/bin/awk",
    "/bin/gawk",
    "/usr/bin/gawk",
    "/usr/bin/env",
}


def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."

    st = os.stat(AGENT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Agent script {AGENT_PATH} is not executable."

    with open(AGENT_PATH, "rb") as f:
        header = f.read(4)
    assert header != b"\x7fELF", "Agent solution must be a Bash or Awk script, not a compiled executable."


def run_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return demote, account


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert shutil.which("strace"), "strace is required to verify that the solution does not delegate."

    random.seed(42)
    chars = ['A', 'C', 'G', 'T', 'N']
    cases = []

    # Obtain all reference answers before making the proprietary executable
    # unavailable to the submitted program.
    for i in range(NUM_TESTS):
        length = random.randint(10, 1000)
        seq = "".join(random.choice(chars) for _ in range(length))
        input_data = (seq + "\n").encode("utf-8")

        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                capture_output=True,
                check=True,
                timeout=2,
            )
            oracle_out = oracle_proc.stdout.decode("utf-8").strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input of length {length}.")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input of length {length}. Return code: {e.returncode}")

        cases.append((seq, input_data, oracle_out))

    hidden_dir = tempfile.mkdtemp(prefix="verifier_oracle_")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "seq_scorer")
    os.rename(ORACLE_PATH, hidden_oracle)

    demote, account = run_as_user()

    try:
        for i, (seq, input_data, oracle_out) in enumerate(cases):
            trace_path = os.path.join("/tmp", f"scorer_trace_{os.getpid()}_{i}")
            try:
                agent_proc = subprocess.run(
                    ["/usr/bin/strace", "-f", "-qq", "-e", "trace=execve", "-o", trace_path, "--", AGENT_PATH],
                    input=input_data,
                    capture_output=True,
                    check=False,
                    timeout=2,
                    preexec_fn=demote,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent script timed out on input:\n{seq}")

            assert agent_proc.returncode == 0, (
                f"Agent script failed with return code {agent_proc.returncode} on input:\n{seq}\n"
                f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )

            agent_out = agent_proc.stdout.decode("utf-8").strip()
            assert agent_out == oracle_out, (
                f"Mismatch on input of length {len(seq)}.\n"
                f"Input: {seq}\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent): {agent_out}"
            )

            assert os.path.exists(trace_path), "Execution trace was not produced."
            with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
                trace = f.read()

            executed = re.findall(r'execve\("([^"\\]*(?:\\.[^"\\]*)*)"', trace)
            assert executed, "No executable launch was recorded for the agent script."
            for encoded_path in executed:
                path = bytes(encoded_path, "utf-8").decode("unicode_escape")
                assert path in ALLOWED_EXECUTABLES, (
                    f"Solution delegated work to disallowed executable {path!r}; "
                    "the implementation must be pure Bash or Awk."
                )

            os.unlink(trace_path)
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
