#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess

ORACLE = "/app/nanopore_scorer"
AGENT = "/home/user/open_scorer"
SOURCE = "/home/user/open_scorer.c"
REBUILT = "/tmp/open_scorer_rebuilt"


def run(path, args):
    return subprocess.run(
        [path] + args,
        capture_output=True,
        text=True,
        timeout=5,
    )


def expected_score(seq, signal_strings):
    levels = {'A': 1.0, 'C': -1.0, 'G': 0.5, 'T': -0.5}
    raw = [float(value) for value in signal_strings]
    filtered = []
    for i in range(len(raw)):
        if i == 0:
            value = raw[i]
        elif i == 1:
            value = 0.75 * raw[i] + 0.25 * raw[i - 1]
        else:
            value = 0.5 * raw[i] + 0.25 * raw[i - 1] + 0.25 * raw[i - 2]
        filtered.append(value)

    distance = math.sqrt(sum(
        (filtered[i] - levels[seq[i]]) ** 2
        for i in range(len(seq))
    ))
    return f"{distance:.4f}"


def test_open_scorer_exists_and_executable():
    assert os.path.exists(AGENT), f"The agent binary {AGENT} does not exist."
    assert os.path.isfile(AGENT), f"The path {AGENT} is not a file."
    assert os.access(AGENT, os.X_OK), f"The file {AGENT} is not executable."
    assert stat.S_ISREG(os.lstat(AGENT).st_mode), "Agent binary must be a regular file, not a symlink."

    assert os.path.exists(SOURCE), f"Required C source {SOURCE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), "C source must be a regular file, not a symlink."

    with open(AGENT, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary."

    assert os.path.exists(ORACLE), f"Oracle binary {ORACLE} missing."
    with open(AGENT, "rb") as agent_file, open(ORACLE, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent executable must not be a copy of the oracle."


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE), f"Oracle binary {ORACLE} missing."
    assert os.path.exists(AGENT), f"Agent binary {AGENT} missing."

    random.seed(42)
    num_iterations = 1000
    bases = ['A', 'C', 'G', 'T']

    for i in range(num_iterations):
        n = random.randint(5, 50)
        seq = "".join(random.choice(bases) for _ in range(n))
        signals = [str(round(random.uniform(-2.0, 2.0), 6)) for _ in range(n)]
        args = [seq] + signals

        oracle_res = run(ORACLE, args)
        agent_res = run(AGENT, args)

        assert oracle_res.returncode == 0, f"Oracle failed on input: {' '.join(args)}"
        assert agent_res.returncode == 0, f"Agent failed on input: {' '.join(args)}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()
        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i + 1}:\n"
            f"Input args: {' '.join(args)}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )


def test_independent_c_implementation_without_oracle():
    # Remove the proprietary executable before rebuilding and exercising the
    # submission, so a C wrapper, symlink, or build-time inclusion cannot use it.
    os.unlink(ORACLE)

    compile_res = subprocess.run(
        ["gcc", "-O2", "-o", REBUILT, SOURCE, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_res.returncode == 0, (
        "open_scorer.c did not compile with the required command:\n"
        + compile_res.stderr
    )
    assert stat.S_ISREG(os.lstat(REBUILT).st_mode)
    with open(REBUILT, "rb") as handle:
        assert handle.read(4) == b"\x7fELF"

    # The submitted executable must be the result of compiling the submitted
    # source with the command required by the instruction.
    with open(AGENT, "rb") as agent_file, open(REBUILT, "rb") as rebuilt_file:
        assert agent_file.read() == rebuilt_file.read(), (
            "The submitted executable does not match a fresh required build of open_scorer.c."
        )

    random.seed(917263)
    bases = ['A', 'C', 'G', 'T']
    for i in range(300):
        n = random.randint(1, 50)
        seq = "".join(random.choice(bases) for _ in range(n))
        signals = [format(random.uniform(-2.0, 2.0), ".6f") for _ in range(n)]
        args = [seq] + signals
        expected = expected_score(seq, signals)

        for executable in (AGENT, REBUILT):
            result = run(executable, args)
            assert result.returncode == 0, (
                f"{executable} failed without the oracle on input: {' '.join(args)}"
            )
            assert result.stdout.strip() == expected, (
                f"Independent result mismatch on iteration {i + 1}:\n"
                f"Input args: {' '.join(args)}\n"
                f"Expected: {expected}\n"
                f"Actual:   {result.stdout.strip()}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
