#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/relax_bin"
AGENT_PATH = "/home/user/relax_out"
SOURCE_PATH = "/home/user/src/relax.c"
NUM_TESTS = 100


def generate_input(seed):
    random.seed(seed)
    n = random.randint(10, 200)
    vals = [str(random.randint(-100, 100)) for _ in range(n)]
    return f">SEQ\n{' '.join(vals)}\n"


def run_program(executable, input_data):
    return subprocess.run(
        [executable],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=5,
        cwd="/tmp",
        env={"PATH": "/usr/bin:/bin", "LANG": "C"},
    )


def test_source_build_and_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"
    assert open(AGENT_PATH, "rb").read(4) == b"\x7fELF", "relax_out must be a compiled ELF executable"

    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"Source must be a regular file at {SOURCE_PATH}"

    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle file at {ORACLE_PATH} is not executable"

    with tempfile.TemporaryDirectory(prefix="relax_verify_") as td:
        rebuilt_path = os.path.join(td, "relax_rebuilt")
        build = subprocess.run(
            ["/usr/bin/gcc", "-O2", SOURCE_PATH, "-o", rebuilt_path],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert build.returncode == 0, f"gcc -O2 failed:\n{build.stderr}"
        assert os.access(rebuilt_path, os.X_OK)
        assert open(rebuilt_path, "rb").read(4) == b"\x7fELF"

        with open(AGENT_PATH, "rb") as f:
            agent_bytes = f.read()
        with open(rebuilt_path, "rb") as f:
            rebuilt_bytes = f.read()
        with open(ORACLE_PATH, "rb") as f:
            oracle_bytes = f.read()

        assert agent_bytes == rebuilt_bytes, (
            "relax_out is not the result of compiling the submitted relax.c with gcc -O2"
        )
        assert agent_bytes != oracle_bytes, "relax_out must not be a copy of the oracle binary"

        cases = [generate_input(42 + i) for i in range(NUM_TESTS)]
        expected = []
        for i, input_data in enumerate(cases):
            result = run_program(ORACLE_PATH, input_data)
            assert result.returncode == 0, (
                f"Oracle failed on test case {i+1}/{NUM_TESTS}: {result.stderr}"
            )
            expected.append(result.stdout.strip())

        oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
        os.unlink(ORACLE_PATH)
        try:
            for executable, label in ((rebuilt_path, "rebuilt source"), (AGENT_PATH, "agent executable")):
                for i, (input_data, oracle_output) in enumerate(zip(cases, expected)):
                    result = run_program(executable, input_data)
                    assert result.returncode == 0, (
                        f"{label} failed on test case {i+1}/{NUM_TESTS}.\n"
                        f"Input:\n{input_data}\nStderr:\n{result.stderr}"
                    )
                    assert result.stdout.strip() == oracle_output, (
                        f"Mismatch for {label} on test case {i+1}/{NUM_TESTS}.\n"
                        f"Input:\n{input_data}\n"
                        f"Oracle output:\n{oracle_output}\n"
                        f"Program output:\n{result.stdout.strip()}\n"
                    )
        finally:
            with open(ORACLE_PATH, "wb") as f:
                f.write(oracle_bytes)
            os.chmod(ORACLE_PATH, oracle_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
