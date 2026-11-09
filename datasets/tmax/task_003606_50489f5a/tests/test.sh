#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import string
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_parser"
AGENT_PATH = "/home/user/parser"
SOURCE_PATH = "/home/user/parser.c"


def generate_input():
    num_commas = random.randint(0, 5)
    chars = string.ascii_letters + string.digits + " "
    parts = []
    for _ in range(num_commas + 1):
        length = random.randint(0, 20)
        parts.append("".join(random.choices(chars, k=length)))
    return ",".join(parts)[:100]


def get_test_inputs():
    random.seed(42)
    inputs = [
        "",
        "   ",
        " , , , ",
        "prod,fr_FR.UTF-8,CET,4",
        "  prod  ,  fr_FR.UTF-8  ,  CET  ,  4  ",
        "dev, , , 0",
        "test,en_GB,GMT,-1",
        "stage, , , abc",
        "stage, , , 2.5",
        "a,b,c,d,e,f",
    ]
    for _ in range(1000 - len(inputs)):
        inputs.append(generate_input())
    return inputs


def expected_output(value):
    fields = value.split(",")[:4]
    fields += [""] * (4 - len(fields))
    fields = [field.strip(" \t\n\r\v\f") for field in fields]

    stage = fields[0] or "canary"
    locale = fields[1] or "en_US.UTF-8"
    timezone = fields[2] or "UTC"
    cores = fields[3]
    if not cores or not all("0" <= c <= "9" for c in cores) or int(cores) <= 0:
        cores = "2"

    return f"[Stage:{stage}|Lang:{locale}|TZ:{timezone}|Cores:{cores}]\n"


def run_parser(path, value):
    return subprocess.run(
        [path, value], capture_output=True, text=True, timeout=5
    ).stdout


def test_fuzz_equivalence_and_c_implementation():
    agent_stat = os.lstat(AGENT_PATH)
    source_stat = os.lstat(SOURCE_PATH)
    oracle_stat = os.lstat(ORACLE_PATH)

    assert stat.S_ISREG(agent_stat.st_mode), "Agent executable must be a regular file"
    assert stat.S_ISREG(source_stat.st_mode), "parser.c must be a regular C source file"
    assert stat.S_ISREG(oracle_stat.st_mode), "Legacy parser must be a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable is not executable: {AGENT_PATH}"
    assert source_stat.st_size > 0, "parser.c is empty"

    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes.startswith(b"\x7fELF"), "Agent executable is not a compiled ELF binary"
    assert agent_bytes != oracle_bytes, "Agent executable is a byte-identical copy of the legacy parser"

    inputs = get_test_inputs()

    # Preserve the original oracle-based fuzz assertion.
    for test_input in inputs:
        oracle_stdout = run_parser(ORACLE_PATH, test_input)
        agent_stdout = run_parser(AGENT_PATH, test_input)
        assert oracle_stdout == agent_stdout, (
            f"Stdout mismatch on input {test_input!r}.\n"
            f"Oracle:\n{oracle_stdout!r}\nAgent:\n{agent_stdout!r}"
        )

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt_path = os.path.join(tempdir, "parser_from_source")
        compile_proc = subprocess.run(
            ["gcc", "-O2", SOURCE_PATH, "-o", rebuilt_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_proc.returncode == 0, (
            "parser.c did not compile successfully:\n" + compile_proc.stderr
        )

        hidden_inputs = inputs + [
            "\tprod\t,\tfr_FR\t,\tCET\t,\t8\t",
            ",,,0004",
            ",,,+4",
            "blue,en_US,UTC,999999",
            "one,two,three,4,ignored",
        ]

        oracle_mode = stat.S_IMODE(oracle_stat.st_mode)
        agent_mode = stat.S_IMODE(agent_stat.st_mode)

        # Remove the oracle while exercising the submitted binary, then remove
        # both shipped binaries while exercising a fresh build of parser.c.
        os.unlink(ORACLE_PATH)
        try:
            for test_input in hidden_inputs:
                assert run_parser(AGENT_PATH, test_input) == expected_output(test_input), (
                    f"Submitted parser failed independently on {test_input!r}"
                )

            os.unlink(AGENT_PATH)
            try:
                for test_input in hidden_inputs:
                    assert run_parser(rebuilt_path, test_input) == expected_output(test_input), (
                        f"Freshly compiled parser.c failed independently on {test_input!r}"
                    )
            finally:
                with open(AGENT_PATH, "wb") as f:
                    f.write(agent_bytes)
                os.chmod(AGENT_PATH, agent_mode)
        finally:
            with open(ORACLE_PATH, "wb") as f:
                f.write(oracle_bytes)
            os.chmod(ORACLE_PATH, oracle_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
