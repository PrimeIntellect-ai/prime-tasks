#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import secrets
import subprocess
import binascii
import pytest

WORKSPACE_DIR = "/home/user/project_workspace"
SOURCE_FILES_DIR = os.path.join(WORKSPACE_DIR, "source_files")
EXTRACTOR_DIR = os.path.join(WORKSPACE_DIR, "extractor")
DEPS_HEX = os.path.join(WORKSPACE_DIR, "deps.hex")
ANALYZER_C = os.path.join(WORKSPACE_DIR, "analyzer.c")
ANALYZER_BIN = os.path.join(WORKSPACE_DIR, "analyzer")
BUILD_ORDER = os.path.join(WORKSPACE_DIR, "build_order.txt")


def run_checked(command, cwd=None):
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            check=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Command failed: {command}\nstdout:\n{e.stdout}\nstderr:\n{e.stderr}"
        )


def dependency_pairs_from_sources():
    expected_pairs = set()
    for fname in os.listdir(SOURCE_FILES_DIR):
        fpath = os.path.join(SOURCE_FILES_DIR, fname)
        if os.path.isfile(fpath):
            with open(fpath, "r") as f:
                for line in f:
                    m = re.match(r'#include\s+"([^"]+)"', line)
                    if m:
                        expected_pairs.add(f"{fname} {m.group(1)}")
    return expected_pairs


def read_decoded_pairs():
    assert os.path.isfile(DEPS_HEX), f"Missing {DEPS_HEX}. The Rust extractor may not have run successfully."
    with open(DEPS_HEX, "r") as f:
        hex_data = f.read().strip()
    try:
        decoded = binascii.unhexlify(hex_data).decode("utf-8")
    except Exception as e:
        pytest.fail(f"Could not decode {DEPS_HEX} as hex-encoded UTF-8: {e}")
    return set(line.strip() for line in decoded.splitlines() if line.strip())


def expected_order_from_sources():
    nodes = set()
    deps = {}
    rev_deps = {}

    for fname in os.listdir(SOURCE_FILES_DIR):
        if os.path.isfile(os.path.join(SOURCE_FILES_DIR, fname)):
            nodes.add(fname)
            deps.setdefault(fname, set())
            rev_deps.setdefault(fname, set())

            with open(os.path.join(SOURCE_FILES_DIR, fname), "r") as f:
                for line in f:
                    m = re.match(r'#include\s+"([^"]+)"', line)
                    if m:
                        dep = m.group(1)
                        nodes.add(dep)
                        deps[fname].add(dep)
                        rev_deps.setdefault(dep, set()).add(fname)

    return topological_order(nodes, deps, rev_deps)


def topological_order(nodes, deps, rev_deps):
    in_degree = {n: len(deps.get(n, set())) for n in nodes}
    queue = [n for n in nodes if in_degree[n] == 0]
    expected_order = []
    while queue:
        queue.sort()
        u = queue.pop(0)
        expected_order.append(u)
        for v in rev_deps.get(u, set()):
            in_degree[v] -= 1
            if in_degree[v] == 0:
                queue.append(v)
    return expected_order


def expected_order_from_pairs(pairs):
    nodes = set()
    deps = {}
    rev_deps = {}
    for dependent, dependency in pairs:
        nodes.update((dependent, dependency))
        deps.setdefault(dependent, set()).add(dependency)
        deps.setdefault(dependency, set())
        rev_deps.setdefault(dependency, set()).add(dependent)
        rev_deps.setdefault(dependent, set())
    return topological_order(nodes, deps, rev_deps)


def read_build_order():
    assert os.path.isfile(BUILD_ORDER), f"Missing output file: {BUILD_ORDER}"
    with open(BUILD_ORDER, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_rust_extractor_output():
    # Preserve the original artifact assertion, then require cargo itself to regenerate it.
    assert os.path.isfile(DEPS_HEX), f"Missing {DEPS_HEX}. The Rust extractor may not have run successfully."
    os.remove(DEPS_HEX)
    run_checked(["cargo", "run", "--quiet"], cwd=EXTRACTOR_DIR)

    actual_pairs = read_decoded_pairs()
    expected_pairs = dependency_pairs_from_sources()
    assert actual_pairs == expected_pairs, (
        f"Extracted dependencies in {DEPS_HEX} do not match the expected source file includes."
    )


def test_c_analyzer_exists_and_compiles():
    assert os.path.isfile(ANALYZER_C), f"Missing C source file: {ANALYZER_C}"
    assert os.path.isfile(ANALYZER_BIN), f"Missing compiled executable: {ANALYZER_BIN}"
    assert os.access(ANALYZER_BIN, os.X_OK), f"The file {ANALYZER_BIN} is not executable."

    # Compile the submitted C source into the required executable path.
    run_checked(["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", ANALYZER_C, "-o", ANALYZER_BIN])
    assert os.path.isfile(ANALYZER_BIN) and os.access(ANALYZER_BIN, os.X_OK)


def test_build_order_output():
    # Preserve the original output assertion, then require the analyzer to regenerate it.
    assert os.path.isfile(BUILD_ORDER), f"Missing output file: {BUILD_ORDER}"
    os.remove(BUILD_ORDER)
    run_checked([ANALYZER_BIN], cwd=WORKSPACE_DIR)

    expected_order = expected_order_from_sources()
    actual_order = read_build_order()
    assert actual_order == expected_order, (
        f"Build order mismatch.\nExpected: {expected_order}\nGot:      {actual_order}\n"
        "Ensure topological sort correctly resolves dependencies and breaks ties alphabetically."
    )


def test_pipeline_on_unseen_inputs():
    # Replace the fixed fixtures with unpredictable, valid source files and rerun cargo.
    for name in os.listdir(SOURCE_FILES_DIR):
        path = os.path.join(SOURCE_FILES_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    tag = secrets.token_hex(5)
    files = {
        f"{tag}_app.c": f'#include "{tag}_alpha.h"\n#include "{tag}_beta.h"\n',
        f"{tag}_tool.c": f'#include "{tag}_beta.h"\n',
        f"{tag}_alpha.h": f'#include "{tag}_base.h"\n',
        f"{tag}_beta.h": f'#include "{tag}_base.h"\n',
        f"{tag}_base.h": "",
    }
    for name, content in files.items():
        with open(os.path.join(SOURCE_FILES_DIR, name), "w") as f:
            f.write(content)

    if os.path.exists(DEPS_HEX):
        os.remove(DEPS_HEX)
    run_checked(["cargo", "run", "--quiet"], cwd=EXTRACTOR_DIR)
    assert read_decoded_pairs() == dependency_pairs_from_sources()

    if os.path.exists(BUILD_ORDER):
        os.remove(BUILD_ORDER)
    run_checked([ANALYZER_BIN], cwd=WORKSPACE_DIR)
    assert read_build_order() == expected_order_from_sources()

    # Finally, feed the analyzer a graph not represented by source_files. This verifies
    # that it actually decodes and parses deps.hex rather than deriving a fixed answer.
    other = secrets.token_hex(6)
    pairs = [
        (f"{other}_program", f"{other}_left"),
        (f"{other}_program", f"{other}_right"),
        (f"{other}_left", f"{other}_base"),
        (f"{other}_right", f"{other}_base"),
        (f"{other}_utility", f"{other}_support"),
    ]
    decoded = "".join(f"{a} {b}\n" for a, b in pairs)
    with open(DEPS_HEX, "w") as f:
        f.write(binascii.hexlify(decoded.encode("utf-8")).decode("ascii"))

    if os.path.exists(BUILD_ORDER):
        os.remove(BUILD_ORDER)
    run_checked([ANALYZER_BIN], cwd=WORKSPACE_DIR)
    assert read_build_order() == expected_order_from_pairs(pairs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
