#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import math
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

SO_PATH = "/home/user/mathlib/libmathparser.so"
SCRIPT_PATH = "/home/user/validator.py"


def run_validator(path, env=None):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "check", path],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    output = result.stdout.strip()
    assert output in {"CLEAN", "EVIL"}, repr(result.stdout)
    return output


def write_graph(path, version, nodes, deps):
    graph = {"version": version, "nodes": nodes}
    graph["dependencies" if version == 1 else "deps"] = deps
    with open(path, "w", encoding="utf-8") as f:
        json.dump(graph, f)


def test_mathlib_compiled():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not compiled."

    build = subprocess.run(
        ["make", "clean", "all"],
        cwd="/home/user/mathlib",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not compiled."
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmathparser.so is not an ELF shared library"

    lib = ctypes.CDLL(SO_PATH)
    fn = lib.eval_expr
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_double

    rng = random.SystemRandom()
    cases = [
        ("2 ^ 3 ^ 2", 512.0),
        ("(3 + 5) * 4 - 6 / 2", 29.0),
    ]
    for _ in range(8):
        a, b, c = (rng.randint(1, 20) for _ in range(3))
        cases.append((f"({a} + {b}) * {c}", float((a + b) * c)))
        cases.append((f"{a} * {b} + {c}", float(a * b + c)))
    for expression, expected in cases:
        actual = fn(expression.encode())
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (expression, actual, expected)


def test_validator_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Validator script {SCRIPT_PATH} does not exist."


def test_adversarial_corpus_evaluation():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for cf in clean_files:
        try:
            output = run_validator(cf)
            if output != "CLEAN":
                clean_failures.append((os.path.basename(cf), output))
        except Exception as e:
            clean_failures.append((os.path.basename(cf), str(e)))

    evil_failures = []
    for ef in evil_files:
        try:
            output = run_validator(ef)
            if output != "EVIL":
                evil_failures.append((os.path.basename(ef), output))
        except Exception as e:
            evil_failures.append((os.path.basename(ef), str(e)))

    error_messages = []
    if clean_failures:
        basenames = [f[0] for f in clean_failures]
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(basenames)}")
    if evil_failures:
        basenames = [f[0] for f in evil_failures]
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(basenames)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_graphs_and_same_path_reuse():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="graph_inputs_") as td:
        path = os.path.join(td, uuid.uuid4().hex + ".json")

        # Reuse one path for opposite answers so classification cannot depend on its name.
        node = uuid.uuid4().hex
        write_graph(path, 2, {node: {"expr": "25 * 2"}}, {node: []})
        assert run_validator(path) == "CLEAN"
        write_graph(path, 1, {node: {"expr": "49 + 2"}}, {node: []})
        assert run_validator(path) == "EVIL"

        # Random clean DAGs in both schema versions.
        for version in (1, 2):
            for _ in range(4):
                count = rng.randint(4, 8)
                names = [uuid.uuid4().hex for _ in range(count)]
                weights = {name: rng.randint(1, 5) for name in names}
                deps = {name: [] for name in names}
                for i in range(count):
                    for j in range(i + 1, count):
                        if rng.random() < 0.3:
                            deps[names[i]].append(names[j])
                nodes = {
                    name: {"expr": f"({weights[name]} * 3) / 3"}
                    for name in names
                }
                write_graph(path, version, nodes, deps)
                assert run_validator(path) == "CLEAN"

        # Random over-threshold chains in both schema versions.
        for version in (1, 2):
            names = [uuid.uuid4().hex for _ in range(4)]
            weights = [rng.randint(13, 20) for _ in names]
            nodes = {name: {"expr": str(weight)} for name, weight in zip(names, weights)}
            deps = {name: ([names[i + 1]] if i + 1 < len(names) else []) for i, name in enumerate(names)}
            assert sum(weights) > 50
            write_graph(path, version, nodes, deps)
            assert run_validator(path) == "EVIL"

        # A cycle is evil even though every individual and acyclic path weight is low.
        names = [uuid.uuid4().hex for _ in range(3)]
        nodes = {name: {"expr": "1 + 1"} for name in names}
        deps = {names[0]: [names[1]], names[1]: [names[2]], names[2]: [names[0]]}
        write_graph(path, rng.choice([1, 2]), nodes, deps)
        assert run_validator(path) == "EVIL"

        # Branching must use the maximum path rather than summing the whole graph.
        root, left, right = [uuid.uuid4().hex for _ in range(3)]
        nodes = {root: {"expr": "10"}, left: {"expr": "40"}, right: {"expr": "41"}}
        deps = {root: [left, right], left: [], right: []}
        write_graph(path, 2, nodes, deps)
        assert run_validator(path) == "EVIL"


def test_validator_uses_eval_expr_abi_results():
    # Replace the library briefly with an ABI-compatible probe. Its deliberately
    # different results make using the library's return values observable.
    backup = SO_PATH + ".verifier_backup"
    marker = os.path.join(tempfile.gettempdir(), "abi_calls_" + uuid.uuid4().hex)
    source = os.path.join(tempfile.gettempdir(), "abi_probe_" + uuid.uuid4().hex + ".c")
    probe_code = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
double eval_expr(const char *expr) {
    const char *marker = getenv("ABI_MARKER");
    if (marker) {
        FILE *f = fopen(marker, "a");
        if (f) { fprintf(f, "%s\n", expr); fclose(f); }
    }
    if (strcmp(expr, "6 * 7") == 0) return 35.0;
    if (strcmp(expr, "100 - 99") == 0) return 20.0;
    if (strcmp(expr, "100") == 0) return 0.0;
    return 0.0;
}
'''
    with open(source, "w", encoding="utf-8") as f:
        f.write(probe_code)

    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(SO_PATH, backup)
    try:
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", SO_PATH, source],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr
        env = os.environ.copy()
        env["ABI_MARKER"] = marker
        with tempfile.TemporaryDirectory(prefix="abi_graph_") as td:
            path = os.path.join(td, uuid.uuid4().hex + ".json")
            a, b = uuid.uuid4().hex, uuid.uuid4().hex
            write_graph(path, 2, {a: {"expr": "6 * 7"}, b: {"expr": "100 - 99"}}, {a: [b], b: []})
            assert run_validator(path, env=env) == "EVIL"  # Probe weights are 35 + 20.

            c = uuid.uuid4().hex
            write_graph(path, 1, {c: {"expr": "100"}}, {c: []})
            assert run_validator(path, env=env) == "CLEAN"  # Probe weight is zero.

        with open(marker, encoding="utf-8") as f:
            calls = [line.strip() for line in f]
        assert "6 * 7" in calls and "100 - 99" in calls and "100" in calls
    finally:
        try:
            os.unlink(SO_PATH)
        except FileNotFoundError:
            pass
        os.replace(backup, SO_PATH)
        for item in (source, marker):
            try:
                os.unlink(item)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
