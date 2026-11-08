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
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/oracle_parser"
AGENT_PATH = "/home/user/artifact_parser"
SOURCE_PATH = "/home/user/artifact_parser.c"
VENDOR_DIR = "/app/vendor/inih-53"
LIB_PATH = os.path.join(VENDOR_DIR, "libinih.a")
REBUILT_PATH = "/tmp/artifact_parser_rebuilt"
MAP_PATH = "/tmp/artifact_parser_rebuilt.map"


def run_parser(path, input_data, iteration, run_as_user=False):
    preexec_fn = None
    if run_as_user:
        account = pwd.getpwnam("user")
        def drop_privileges():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        preexec_fn = drop_privileges

    try:
        return subprocess.run(
            [path], input=input_data, capture_output=True, timeout=2,
            preexec_fn=preexec_fn
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Parser {path} timed out on iteration {iteration}. Input length: {len(input_data)}.")


def test_01_libinih_compiled():
    assert os.path.exists(LIB_PATH), f"{LIB_PATH} does not exist. Did you fix the Makefile and run make?"


def test_02_agent_parser_exists():
    assert os.path.exists(AGENT_PATH), f"{AGENT_PATH} does not exist. Did you compile your C program?"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable."
    assert os.path.isfile(AGENT_PATH) and not os.path.islink(AGENT_PATH), f"{AGENT_PATH} must be a regular compiled executable."
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_PATH} is not an ELF executable."
    with open(ORACLE_PATH, "rb") as oracle, open(AGENT_PATH, "rb") as agent:
        assert agent.read() != oracle.read(), "artifact_parser must not be a byte-identical copy of oracle_parser."


def test_03_makefile_and_source_build():
    assert os.path.isfile(SOURCE_PATH) and not os.path.islink(SOURCE_PATH), \
        f"{SOURCE_PATH} does not exist or is not a regular C source file."

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r'^\s*#\s*include\s*[<\"]ini\.h[>\"]', source, re.MULTILINE), \
        'artifact_parser.c must #include "ini.h".'

    # The repaired Makefile must itself be capable of recreating the archive.
    subprocess.run(["make", "clean"], cwd=VENDOR_DIR, check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["make"], cwd=VENDOR_DIR, check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.isfile(LIB_PATH), "The repaired Makefile did not produce libinih.a."

    members = subprocess.run(["ar", "t", LIB_PATH], check=True, capture_output=True, text=True).stdout.splitlines()
    assert "ini.o" in members, "libinih.a does not contain the compiled ini.o member."
    symbols = subprocess.run(["nm", "-g", "--defined-only", LIB_PATH], check=True,
                             capture_output=True, text=True).stdout
    assert "ini_parse_stream" in symbols and "ini_parse" in symbols, \
        "libinih.a does not contain the expected inih parser implementation."

    for path in (REBUILT_PATH, MAP_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Independently build the submitted source against the required archive.
    subprocess.run([
        "gcc", "-O2", "-Wall", "-Wextra", "-Werror=implicit-function-declaration",
        "-I" + VENDOR_DIR, SOURCE_PATH, LIB_PATH,
        "-Wl,-Map," + MAP_PATH, "-o", REBUILT_PATH
    ], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    with open(MAP_PATH, "r", encoding="utf-8", errors="replace") as f:
        link_map = f.read()
    assert re.search(r'libinih\.a\(ini\.o\)', link_map), \
        "The submitted source does not actually use and link the ini.o implementation from libinih.a."


def generate_random_ini(length):
    chars = string.ascii_letters + string.digits + "[]=\n"
    return "".join(random.choice(chars) for _ in range(length)).encode("utf-8")


def generate_structured_ini():
    sections = random.randint(1, 8)
    lines = []
    for section_index in range(sections):
        section = "sec" + str(section_index) + "_" + "".join(random.choice(string.ascii_letters) for _ in range(6))
        lines.append(f"[{section}]")
        for key_index in range(random.randint(1, 10)):
            key = f"key{key_index}_" + "".join(random.choice(string.ascii_letters) for _ in range(5))
            value_chars = string.ascii_letters + string.digits + " _-.:/"
            value = "".join(random.choice(value_chars) for _ in range(random.randint(0, 80)))
            separator = random.choice(["=", " = ", ":"])
            lines.append(key + separator + value)
        if random.random() < 0.4:
            lines.extend(["; comment", "malformed line without separator", "[broken"])
    return ("\n".join(lines) + "\n").encode("utf-8")


def test_04_fuzz_equivalence_and_independence():
    random.seed(42)
    inputs = []

    # Preserve the original 1000-case fuzz assertion.
    for _ in range(1000):
        inputs.append(generate_random_ini(random.randint(10, 5000)))

    # Also exercise successful parsing, whitespace, comments, and malformed parts.
    inputs.extend([
        b"[section]\nkey=value\n",
        b"root=value\n[one]\na=1\nb = two\n; comment\n[two]\nx:y\n",
        b"[good]\na=1\n[broken\nb=2\n[again]\nc=3\n",
        b"[empty]\nkey=\n[]=bad\n[final]\nname=value\n",
    ])
    for _ in range(200):
        inputs.append(generate_structured_ini())

    expected = []
    for i, input_data in enumerate(inputs):
        oracle_proc = run_parser(ORACLE_PATH, input_data, i)
        expected.append(oracle_proc.stdout)

    # Make both the oracle and submitted executable unavailable while exercising
    # the independently linked source build, preventing wrappers or copied paths
    # from substituting for an implementation.
    hidden_dir = tempfile.mkdtemp(prefix="verifier-hidden-")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle_parser")
    hidden_agent = os.path.join(hidden_dir, "artifact_parser")
    oracle_hidden = False
    agent_hidden = False

    try:
        os.rename(ORACLE_PATH, hidden_oracle)
        oracle_hidden = True

        # Keep checking the originally submitted executable, now without the
        # oracle at its documented path.
        for i, (input_data, wanted) in enumerate(zip(inputs, expected)):
            agent_proc = run_parser(AGENT_PATH, input_data, i)
            if agent_proc.stdout != wanted:
                preview = input_data[:200] + (b"..." if len(input_data) > 200 else b"")
                pytest.fail(
                    f"Submitted parser output mismatch on iteration {i}.\n"
                    f"Input preview:\n{preview}\n\n"
                    f"Expected output preview:\n{wanted[:200]}\n\n"
                    f"Agent output preview:\n{agent_proc.stdout[:200]}"
                )

        os.rename(AGENT_PATH, hidden_agent)
        agent_hidden = True

        for i, (input_data, wanted) in enumerate(zip(inputs, expected)):
            rebuilt_proc = run_parser(REBUILT_PATH, input_data, i, run_as_user=True)
            if rebuilt_proc.stdout != wanted:
                preview = input_data[:200] + (b"..." if len(input_data) > 200 else b"")
                pytest.fail(
                    f"Parser rebuilt from artifact_parser.c mismatched on iteration {i}.\n"
                    f"Input preview:\n{preview}\n\n"
                    f"Expected output preview:\n{wanted[:200]}\n\n"
                    f"Rebuilt output preview:\n{rebuilt_proc.stdout[:200]}"
                )
    finally:
        if agent_hidden:
            os.rename(hidden_agent, AGENT_PATH)
        if oracle_hidden:
            os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
