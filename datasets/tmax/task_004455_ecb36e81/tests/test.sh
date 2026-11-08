#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/oracle_router

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_BINARY = "/home/user/router_fixed"
ORACLE_BINARY = "/tests/oracle_router"
NUM_ITERATIONS = 1000


def generate_random_url(rng):
    path_charset = string.ascii_letters + string.digits + "/"
    path_len = rng.randint(1, 1000)
    path = "/" + "".join(rng.choices(path_charset, k=path_len - 1)) if path_len > 1 else "/"

    if rng.choice([True, False]):
        num_params = rng.randint(1, 10)
        params = []
        for _ in range(num_params):
            key_len = rng.randint(1, 20)
            key = "".join(rng.choices(string.ascii_letters + string.digits + "_", k=key_len))
            val_len = rng.randint(1, 50)
            val = "".join(rng.choices(string.ascii_letters + string.digits + "_-", k=val_len))
            params.append(f"{key}={val}")
        query = "?" + "&".join(params)
    else:
        query = ""

    return path + query


def run_program(binary, url, timeout=2):
    return subprocess.run(
        [binary, url], capture_output=True, text=True, timeout=timeout
    )


def assert_equivalent(url):
    oracle_proc = run_program(ORACLE_BINARY, url)
    assert oracle_proc.returncode == 0, f"Oracle failed on input {url!r}: {oracle_proc.stderr}"

    agent_proc = run_program(AGENT_BINARY, url)
    assert agent_proc.returncode == 0, (
        f"Your program crashed (return code {agent_proc.returncode}) on input {url!r}.\n"
        f"Stderr: {agent_proc.stderr}"
    )
    assert agent_proc.stderr == "", f"Unexpected stderr on input {url!r}: {agent_proc.stderr}"
    assert agent_proc.stdout == oracle_proc.stdout, (
        f"Mismatch on input {url!r}!\n\n"
        f"Expected Output (Oracle):\n{oracle_proc.stdout}\n"
        f"Actual Output (Agent):\n{agent_proc.stdout}\n"
    )


def test_router_fixed_exists_and_is_binary():
    assert os.path.exists(AGENT_BINARY), f"Missing compiled executable: {AGENT_BINARY}"
    assert os.path.isfile(AGENT_BINARY), f"Expected {AGENT_BINARY} to be a file"
    assert os.access(AGENT_BINARY, os.X_OK), f"Expected {AGENT_BINARY} to be executable"
    with open(AGENT_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {AGENT_BINARY} to be a compiled ELF executable"


def test_exact_argument_count():
    no_arg = subprocess.run([AGENT_BINARY], capture_output=True, text=True, timeout=2)
    two_args = subprocess.run([AGENT_BINARY, "/a", "/b"], capture_output=True, text=True, timeout=2)
    assert no_arg.returncode != 0, "Program must reject invocation without a URL"
    assert two_args.returncode != 0, "Program must reject invocation with more than one URL"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_BINARY), f"Missing test oracle: {ORACLE_BINARY}"
    assert os.access(ORACLE_BINARY, os.X_OK), f"Expected {ORACLE_BINARY} to be executable"

    rng = random.Random(42)
    for i in range(NUM_ITERATIONS):
        url = generate_random_url(rng)
        try:
            assert_equivalent(url)
        except AssertionError as exc:
            pytest.fail(f"Fuzz iteration {i + 1}: {exc}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Program timed out on fuzz iteration {i + 1}, input {url!r}")


def test_malformed_and_boundary_queries():
    cases = [
        "",
        "/",
        "?",
        "/?",
        "/?&",
        "/?&&",
        "/?=",
        "/?===",
        "/?key",
        "/?key=",
        "/?=value",
        "/?a=b&&c=d&",
        "/?a=b?c=d",
        "/path?broken&good=value",
        "/" + "p" * 12000,
        "/" + "x" * 8000 + "?" + "k" * 2000 + "=" + "v" * 8000,
    ]
    for url in cases:
        assert_equivalent(url)


def test_memory_safety_under_valgrind():
    cases = [
        "/" + "a" * 4096,
        "/route?=" + "v" * 4096,
        "/route?" + "k" * 2048 + "=" + "v" * 4096 + "&&broken&x=",
        "/?&&&&=&&noequals&final=value",
    ]

    for url in cases:
        oracle_proc = run_program(ORACLE_BINARY, url)
        assert oracle_proc.returncode == 0
        try:
            proc = subprocess.run(
                [
                    "valgrind",
                    "--quiet",
                    "--leak-check=full",
                    "--show-leak-kinds=all",
                    "--errors-for-leak-kinds=all",
                    "--track-origins=yes",
                    "--error-exitcode=99",
                    AGENT_BINARY,
                    url,
                ],
                capture_output=True,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Valgrind timed out on input {url!r}")

        assert proc.returncode == 0, (
            f"Valgrind detected a memory error/leak or the program failed on input {url!r} "
            f"(return code {proc.returncode}).\n{proc.stderr}"
        )
        assert proc.stdout == oracle_proc.stdout, f"Output mismatch under Valgrind on input {url!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
