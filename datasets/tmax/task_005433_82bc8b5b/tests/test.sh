#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import heapq
import os
import random
import secrets
import subprocess

import pytest

UTILITY = "/home/user/utility"
RUST_DIR = os.path.join(UTILITY, "rust_lib")
SO_PATH = os.path.join(RUST_DIR, "target/release/librust_lib.so")
RESOLVER = os.path.join(UTILITY, "resolver.py")
DEPS = os.path.join(UTILITY, "deps.txt")
LOAD_ORDER = os.path.join(UTILITY, "load_order.txt")

ORIGINAL_DEPS = """libalpha: libbeta libgamma
libbeta: libdelta
libgamma: libdelta
libdelta:
librust_lib: libalpha
"""
ORIGINAL_EXPECTED = "libdelta, libbeta, libgamma, libalpha, librust_lib"


def run_resolver():
    if os.path.exists(LOAD_ORDER):
        os.remove(LOAD_ORDER)
    result = subprocess.run(
        ["python3", RESOLVER],
        cwd=UTILITY,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"resolver.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOAD_ORDER), "resolver.py did not create load_order.txt"
    with open(LOAD_ORDER, "r") as f:
        return f.read().strip()


def canonical_order(graph):
    nodes = set(graph)
    for dependencies in graph.values():
        nodes.update(dependencies)

    dependents = {node: [] for node in nodes}
    remaining = {node: 0 for node in nodes}
    for node in nodes:
        dependencies = set(graph.get(node, []))
        remaining[node] = len(dependencies)
        for dependency in dependencies:
            dependents[dependency].append(node)

    ready = [node for node in nodes if remaining[node] == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        node = heapq.heappop(ready)
        result.append(node)
        for dependent in dependents[node]:
            remaining[dependent] -= 1
            if remaining[dependent] == 0:
                heapq.heappush(ready, dependent)

    assert len(result) == len(nodes)
    return result


def graph_text(graph):
    lines = []
    items = list(graph.items())
    random.SystemRandom().shuffle(items)
    for node, dependencies in items:
        dependencies = list(dependencies)
        random.SystemRandom().shuffle(dependencies)
        suffix = " ".join(dependencies)
        lines.append(f"{node}:" + (f" {suffix}" if suffix else ""))
    return "\n".join(lines) + "\n"


def random_test_graph():
    names = []
    while len(names) < 8:
        name = "lib_" + secrets.token_hex(4)
        if name not in names:
            names.append(name)

    # This DAG deliberately contains several simultaneous choices. Randomized
    # names make the alphabetic tie decisions unknowable before verification.
    a, b, c, d, e, f, g, h = names
    return {
        a: [],
        b: [],
        c: [a],
        d: [a],
        e: [b, c],
        f: [b, d],
        g: [c],
        h: [e, f, g],
    }


def test_rust_library_compiled():
    """Verify the requested release artifact exists, then rebuild and load it."""
    assert os.path.isfile(SO_PATH), (
        f"Compiled Rust library not found at {SO_PATH}. "
        "Did you fix the borrow checker error and run 'cargo build --release'?"
    )

    clean = subprocess.run(
        ["cargo", "clean"], cwd=RUST_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=RUST_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, (
        "The Rust source does not successfully compile in release mode:\n"
        f"{build.stdout}\n{build.stderr}"
    )
    assert os.path.isfile(SO_PATH), f"Release build did not produce {SO_PATH}"
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not an ELF library"

    try:
        library = ctypes.CDLL(SO_PATH)
        function = library.process_deps
        function.argtypes = []
        function.restype = None
        function()
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load and call process_deps from the shared library: {exc}")


def test_load_order_correct():
    """Retain the original final-output assertion."""
    assert os.path.isfile(LOAD_ORDER), (
        f"Output file not found at {LOAD_ORDER}. Did you complete and run resolver.py?"
    )
    with open(LOAD_ORDER, "r") as f:
        content = f.read().strip()
    assert content == ORIGINAL_EXPECTED, (
        f"Incorrect load order in {LOAD_ORDER}.\n"
        f"Expected: {ORIGINAL_EXPECTED}\nGot:      {content}\n"
        "Ensure you are breaking ties alphabetically and sorting dependencies before dependents."
    )


def test_resolver_implementation_on_derived_inputs():
    assert os.path.isfile(RESOLVER), f"Missing resolver script: {RESOLVER}"
    with open(DEPS, "rb") as f:
        saved_deps = f.read()

    try:
        for _ in range(3):
            graph = random_test_graph()
            with open(DEPS, "w") as f:
                f.write(graph_text(graph))
            expected = ", ".join(canonical_order(graph))
            assert run_resolver() == expected

        # Execute the script against the task's original dependency graph too.
        with open(DEPS, "w") as f:
            f.write(ORIGINAL_DEPS)
        assert run_resolver() == ORIGINAL_EXPECTED
    finally:
        with open(DEPS, "wb") as f:
            f.write(saved_deps)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
