#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import string
import subprocess
import pytest

ORACLE_PATH = "/home/user/oracle"
AGENT_PATH = "/home/user/fixed_parser.py"
PACKAGE_DIR = "/app/vendored_logparser-1.2.0"
REPO_DIR = "/app/internal_tools"
EXPECTED_ORACLE = (
    b"#!/usr/bin/env python3\n"
    b"import sys\n"
    b"print(f\"Parsed: {sys.argv[1]}\")\n"
)


def run_program(argv, inp_str, label):
    try:
        return subprocess.run(
            argv + [inp_str],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{label} timed out on input {inp_str!r}")
    except Exception as exc:
        pytest.fail(f"{label} failed to run on input {inp_str!r}: {exc}")


def assert_equivalent(inp_str):
    oracle_res = run_program([ORACLE_PATH], inp_str, "Oracle")
    agent_res = run_program(["/usr/bin/python3", AGENT_PATH], inp_str, "Agent script")

    assert oracle_res.returncode == agent_res.returncode, (
        f"Return code mismatch on input {inp_str!r}.\n"
        f"Oracle: {oracle_res.returncode}\nAgent: {agent_res.returncode}\n"
        f"Oracle stderr: {oracle_res.stderr!r}\nAgent stderr: {agent_res.stderr!r}"
    )
    assert oracle_res.stdout == agent_res.stdout, (
        f"Output mismatch on input {inp_str!r}.\n"
        f"Oracle output: {oracle_res.stdout!r}\nAgent output: {agent_res.stdout!r}"
    )

    expected = f"Parsed: {inp_str}\n"
    assert oracle_res.returncode == 0
    assert oracle_res.stderr == ""
    assert oracle_res.stdout == expected
    assert agent_res.returncode == 0
    assert agent_res.stdout == expected


def test_c_extension_build_repaired_and_package_installs():
    for artifact in glob.glob(os.path.join(PACKAGE_DIR, "logparser", "fast*.so")):
        os.unlink(artifact)

    build = subprocess.run(
        ["/usr/bin/python3", "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, (
        f"C extension build failed.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    artifacts = glob.glob(os.path.join(PACKAGE_DIR, "logparser", "fast*.so"))
    assert artifacts, "build_ext did not produce the configured logparser.fast extension"
    assert any(open(path, "rb").read(4) == b"\x7fELF" for path in artifacts), (
        "The produced logparser.fast artifact is not an ELF shared object"
    )

    install = subprocess.run(
        ["/usr/bin/python3", "-m", "pip", "install", "-e", ".", "--no-build-isolation"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert install.returncode == 0, (
        f"pip install -e . failed.\nstdout:\n{install.stdout}\nstderr:\n{install.stderr}"
    )


def test_oracle_is_the_historical_git_blob():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    with open(ORACLE_PATH, "rb") as handle:
        recovered = handle.read()
    assert recovered == EXPECTED_ORACLE, (
        "/home/user/oracle is not the canonical historical parser_oracle_bin"
    )

    history = subprocess.run(
        ["git", "-c", f"safe.directory={REPO_DIR}", "rev-list", "--all", "--", "parser_oracle_bin"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    commits = [line.strip() for line in history.stdout.splitlines() if line.strip()]
    assert commits, "No parser_oracle_bin history exists in /app/internal_tools"

    historical_blobs = []
    for commit in commits:
        shown = subprocess.run(
            ["git", "-c", f"safe.directory={REPO_DIR}", "show", f"{commit}:parser_oracle_bin"],
            cwd=REPO_DIR,
            capture_output=True,
            timeout=10,
        )
        if shown.returncode == 0:
            historical_blobs.append(shown.stdout)
    assert EXPECTED_ORACLE in historical_blobs, (
        "The repository history does not contain the canonical parser_oracle_bin blob"
    )


def test_agent_script_state():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as handle:
        agent_bytes = handle.read()
    assert agent_bytes != EXPECTED_ORACLE, (
        "fixed_parser.py must be an independently written implementation, not a byte-for-byte oracle copy"
    )


def test_recovered_crash_input():
    listing = subprocess.run(
        ["fls", "-d", "-p", "/app/server_disk.img"],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    inode = None
    for line in listing.stdout.splitlines():
        if line.rstrip().endswith("core.dump"):
            match = re.search(r"\b(\d+):", line)
            if match:
                inode = match.group(1)
                break
    assert inode is not None, "Deleted core.dump was not recoverable from the ext4 image"

    recovered = subprocess.run(
        ["icat", "/app/server_disk.img", inode],
        capture_output=True,
        timeout=20,
        check=True,
    ).stdout
    marker = b"CRASH_INP:"
    assert marker in recovered, "Recovered dump does not contain the CRASH_INP marker"
    crash_input = recovered.split(marker, 1)[1].decode("utf-8").replace("\x00", "\\x00")
    assert crash_input, "Recovered crashing input is empty"
    assert_equivalent(crash_input)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    random.seed(42)
    edge_cases = [':', '[', ']', '\\x00']
    base_chars = list(string.printable)

    def generate_input():
        length = random.randint(1, 100)
        chars = []
        for _ in range(length):
            if random.random() < 0.2:
                chars.append(random.choice(edge_cases))
            else:
                chars.append(random.choice(base_chars))
        return "".join(chars)

    for _ in range(5000):
        assert_equivalent(generate_input())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
