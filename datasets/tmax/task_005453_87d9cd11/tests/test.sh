#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import tempfile
import subprocess
import pytest

AGENT_BIN = "/home/user/router_vm/target/release/router_vm"
REF_BIN = "/app/ref_router_vm"
BYTECODE_FILE = "/tmp/bytecode.bin"
URLS_FILE = "/tmp/urls.txt"


def setup_module(module):
    """Generate the large timing dataset before running the tests."""
    with open(BYTECODE_FILE, "w") as f:
        f.write("ROUTE /api/*\nROUTE /user/*\n")
    with open(URLS_FILE, "w") as f:
        for i in range(50000):
            f.write(f"/api/item/{i}\n")


def run_and_check(binary, bytecode, urls, expected):
    result = subprocess.run(
        [binary, bytecode, urls],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{binary} failed with exit code {result.returncode}. "
        f"Stderr: {result.stderr.decode(errors='replace')}"
    )
    output = result.stdout.decode(errors="replace").strip()
    match = re.fullmatch(r"Matches:\s*(\d+)", output)
    assert match, f"Unexpected output from {binary}: {output!r}"
    assert int(match.group(1)) == expected, (
        f"Incorrect routing result from {binary}: expected {expected}, got {match.group(1)}"
    )


def test_agent_binary_exists():
    """Check that the agent produced an executable release binary."""
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}. Did you run `cargo build --release`?"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable."
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent artifact is not an ELF executable."
    with open(AGENT_BIN, "rb") as agent, open(REF_BIN, "rb") as ref:
        assert agent.read() != ref.read(), "Agent binary must not be a byte-identical copy of the reference binary."


def test_routing_results():
    """Exercise routing behavior on independently derived mixed inputs."""
    cases = [
        (["ROUTE /api/*", "ROUTE /user/*"],
         ["/api/item/1", "/user/7", "/apis/not-a-match", "/x/api/nested", "/api/", "/api"], 3),
        (["ROUTE /anything"],
         ["/", "/user/1", "/static/api", "/API/item", "/api/item/9"], 1),
        ([], ["/api/item/1", "/api/item/2", "/other"], 0),
    ]

    for patterns, urls, expected in cases:
        with tempfile.TemporaryDirectory(prefix="router_vm_test_") as d:
            bc = os.path.join(d, "program.bc")
            url_file = os.path.join(d, "urls.txt")
            with open(bc, "w") as f:
                for pattern in patterns:
                    f.write(pattern + "\n")
            with open(url_file, "w") as f:
                for url in urls:
                    f.write(url + "\n")

            # The expected count is derived from the supplied matcher semantics,
            # and the reference is checked against it rather than treated blindly.
            derived = sum(1 for url in urls if patterns and "/api/" in url)
            assert derived == expected
            run_and_check(REF_BIN, bc, url_file, derived)
            run_and_check(AGENT_BIN, bc, url_file, derived)


def test_execution_time_ratio():
    """Check correctness on the timing data and enforce the original threshold."""
    assert os.path.isfile(REF_BIN), f"Reference binary missing at {REF_BIN}."

    t0 = time.time()
    ref_result = subprocess.run(
        [REF_BIN, BYTECODE_FILE, URLS_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    ref_time = time.time() - t0
    assert ref_result.returncode == 0, "Reference binary failed to execute."
    assert ref_result.stdout.decode(errors="replace").strip() == "Matches: 50000", (
        f"Reference produced an unexpected result: {ref_result.stdout!r}"
    )

    t0 = time.time()
    agent_result = subprocess.run(
        [AGENT_BIN, BYTECODE_FILE, URLS_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    agent_time = time.time() - t0

    assert agent_result.returncode == 0, (
        f"Agent binary failed to execute. Stderr: {agent_result.stderr.decode(errors='replace')}"
    )
    assert agent_result.stdout.decode(errors="replace").strip() == "Matches: 50000", (
        f"Agent produced an incorrect routing result: {agent_result.stdout!r}"
    )

    ratio = agent_time / ref_time
    assert ratio <= 1.5, (
        f"Execution Time Ratio is {ratio:.3f}, which exceeds the threshold of 1.5. "
        f"(Agent Time: {agent_time:.4f}s, Reference Time: {ref_time:.4f}s). "
        "The Rust code is still too slow. Make sure you hoisted the bytecode parsing out of the hot loop."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
