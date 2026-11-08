#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import pytest

WORKSPACE = Path("/home/user/pkg-mgr")
BUILD_ORDER_PATH = Path("/home/user/build_order.txt")
DECODER_PATH = WORKSPACE / "decoder"
ORIGINAL_GRAPH = WORKSPACE / "graph.txt"


def run_resolver(graph_path):
    if BUILD_ORDER_PATH.exists():
        BUILD_ORDER_PATH.unlink()
    if DECODER_PATH.exists() or DECODER_PATH.is_symlink():
        DECODER_PATH.unlink()

    result = subprocess.run(
        ["./resolve.sh", str(graph_path)],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"resolve.sh failed with exit code {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert BUILD_ORDER_PATH.is_file(), f"File {BUILD_ORDER_PATH} was not created."


def read_build_order():
    with BUILD_ORDER_PATH.open("r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_build_order_exists_and_correct():
    run_resolver(ORIGINAL_GRAPH)
    lines = read_build_order()

    expected_nodes = {"App", "LibA", "LibB", "Core", "Standalone"}
    actual_nodes = set(lines)

    assert actual_nodes == expected_nodes, (
        f"build_order.txt does not contain the exact expected nodes. "
        f"Expected {expected_nodes}, got {actual_nodes}"
    )

    idx = {node: i for i, node in enumerate(lines)}
    assert idx["Core"] < idx["LibA"], "Core must be built before LibA"
    assert idx["Core"] < idx["LibB"], "Core must be built before LibB"
    assert idx["LibA"] < idx["App"], "LibA must be built before App"
    assert idx["LibB"] < idx["App"], "LibB must be built before App"


def test_decoder_compiled_and_functional():
    assert DECODER_PATH.is_file(), "decoder binary was not compiled."
    assert os.access(DECODER_PATH, os.X_OK), "decoder binary is not executable."
    assert DECODER_PATH.read_bytes()[:4] == b"\x7fELF", "decoder is not a compiled executable."

    samples = [
        "plain text",
        "café Ω",
        "工具と雪",
        "symbols !@#$%^&*()[]{}",
        "x" * 400,
    ]
    for value in samples:
        encoded = value.encode("utf-8").hex().encode("ascii") + b"\n"
        result = subprocess.run(
            [str(DECODER_PATH)],
            input=encoded,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode == 0, f"decoder failed for {value!r}"
        assert result.stdout == value.encode("utf-8") + b"\n", (
            f"decoder produced incorrect output for {value!r}: {result.stdout!r}"
        )


def test_resolver_on_generated_graph(tmp_path):
    salt = secrets.token_hex(5)
    nodes = [
        f"base α {salt}",
        f"library one {salt}",
        f"工具-{salt}",
        f"emoji 雪 {salt}",
        f"stand alone {salt}",
        f"dep:colon {salt}",
        f"café {salt}",
        f"final package {salt}",
    ]
    dependencies = {
        nodes[0]: [],
        nodes[1]: [nodes[0]],
        nodes[2]: [nodes[0]],
        nodes[3]: [nodes[1], nodes[2]],
        nodes[4]: [],
        nodes[5]: [nodes[2]],
        nodes[6]: [nodes[3], nodes[5]],
        nodes[7]: [],
    }

    records = []
    for parent, deps in dependencies.items():
        parent_hex = parent.encode("utf-8").hex()
        deps_hex = " ".join(dep.encode("utf-8").hex() for dep in deps)
        records.append(f"{parent_hex}: {deps_hex}\n")
    secrets.SystemRandom().shuffle(records)

    graph_path = tmp_path / "generated_graph.txt"
    graph_path.write_text("".join(records), encoding="ascii")
    run_resolver(graph_path)

    lines = read_build_order()
    assert len(lines) == len(nodes), "build order has missing or duplicate nodes"
    assert set(lines) == set(nodes), (
        f"generated graph output has incorrect nodes. Expected {set(nodes)}, got {set(lines)}"
    )

    idx = {node: i for i, node in enumerate(lines)}
    for parent, deps in dependencies.items():
        for dep in deps:
            assert idx[dep] < idx[parent], f"{dep!r} must be built before {parent!r}"

    assert DECODER_PATH.is_file(), "resolve.sh did not compile decoder for the generated graph."
    assert os.access(DECODER_PATH, os.X_OK), "compiled decoder is not executable."
    assert DECODER_PATH.read_bytes()[:4] == b"\x7fELF", "decoder is not a compiled executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
