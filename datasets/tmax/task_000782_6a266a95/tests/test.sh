#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile
import uuid
import pytest

LIBDIR = "/app/cgraph-1.0"
LIB = os.path.join(LIBDIR, "libcgraph.a")
SOURCE = "/home/user/deadlock_detector.c"
EXECUTABLE = "/home/user/deadlock_detector"
REBUILT = "/tmp/deadlock_detector_rebuilt"


def run_checked(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, **kwargs)


def test_cgraph_built():
    assert os.path.isfile(LIB), "The library /app/cgraph-1.0/libcgraph.a was not built."

    # The fixed Makefile must really rebuild a usable archive.
    run_checked(["make", "clean"], cwd=LIBDIR, timeout=10)
    run_checked(["make"], cwd=LIBDIR, timeout=10)
    assert os.path.isfile(LIB), "The fixed Makefile did not produce libcgraph.a."

    members = run_checked(["ar", "t", LIB], timeout=5).stdout.splitlines()
    assert "cgraph.o" in members, "libcgraph.a is not a valid archive containing cgraph.o."
    symbols = run_checked(["nm", "--defined-only", LIB], timeout=5).stdout
    for symbol in ("create_graph", "add_edge", "has_cycle"):
        assert symbol in symbols, f"libcgraph.a does not define {symbol}."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"The C source {SOURCE} does not exist."
    run_checked(["readelf", "-h", EXECUTABLE], timeout=5)


def test_source_builds_and_uses_cgraph():
    obj = "/tmp/deadlock_detector_submission.o"
    run_checked(["gcc", "-std=c11", "-O2", "-I", LIBDIR,
                 "-c", SOURCE, "-o", obj], timeout=15)
    undefined = run_checked(["nm", "-u", obj], timeout=5).stdout
    for symbol in ("create_graph", "add_edge", "has_cycle"):
        assert symbol in undefined, f"deadlock_detector.c does not use libcgraph's {symbol}."
    run_checked(["gcc", obj, LIB, "-o", REBUILT], timeout=15)
    assert os.access(REBUILT, os.X_OK)


def test_adversarial_corpus():
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    clean_files = glob.glob(os.path.join(clean_dir, "*"))

    assert len(evil_files) > 0, f"No files found in {evil_dir}"
    assert len(clean_files) > 0, f"No files found in {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    for f in evil_files:
        result = subprocess.run([EXECUTABLE, f], capture_output=True, timeout=3)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(f))
    for f in clean_files:
        result = subprocess.run([EXECUTABLE, f], capture_output=True, timeout=3)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def oracle(operations):
    holders = {}
    blocked = set()
    edges = {}

    def cyclic():
        visiting = set()
        visited = set()
        def visit(node):
            if node in visiting:
                return True
            if node in visited:
                return False
            visiting.add(node)
            for nxt in edges.get(node, ()):
                if visit(nxt):
                    return True
            visiting.remove(node)
            visited.add(node)
            return False
        return any(visit(node) for node in list(edges) if node not in visited)

    for tx, action, resource in operations:
        if tx in blocked:
            continue
        mode = "S" if action == "READ" else "X"
        resource_holders = holders.setdefault(resource, {})
        conflicts = []
        for owner, owner_mode in resource_holders.items():
            if owner != tx and (mode == "X" or owner_mode == "X"):
                conflicts.append(owner)
        if conflicts:
            blocked.add(tx)
            edges.setdefault(tx, set()).update(conflicts)
            if cyclic():
                return 1
        else:
            previous = resource_holders.get(tx)
            resource_holders[tx] = "X" if previous == "X" or mode == "X" else "S"
    return 0


def hidden_schedules():
    cases = [
        [(1,"READ","A"),(2,"READ","A"),(1,"WRITE","B"),(2,"WRITE","B")],
        [(1,"WRITE","A"),(2,"WRITE","B"),(1,"READ","B"),(2,"READ","A")],
        [(1,"READ","A"),(1,"WRITE","A"),(2,"READ","B")],
        [(1,"WRITE","A"),(2,"READ","A"),(2,"WRITE","B"),(1,"READ","B")],
        [(1,"READ","A"),(2,"READ","A"),(3,"WRITE","A"),(1,"WRITE","B"),(2,"WRITE","C")],
        [(1,"WRITE","A"),(2,"WRITE","B"),(3,"WRITE","C"),(1,"READ","B"),(2,"READ","C"),(3,"READ","A")],
    ]
    rng = random.Random(0xC6A7)
    for _ in range(180):
        tx_count = rng.randint(2, 7)
        resources = [f"R{i}" for i in range(rng.randint(2, 6))]
        operations = []
        for _ in range(rng.randint(8, 30)):
            operations.append((rng.randint(1, tx_count),
                               rng.choice(("READ", "WRITE")),
                               rng.choice(resources)))
        cases.append(operations)
    return cases


def test_opaque_generated_schedules():
    assert os.path.isfile(REBUILT), "Rebuilt C detector is missing."
    with tempfile.TemporaryDirectory(prefix="inputs_") as directory:
        for index, operations in enumerate(hidden_schedules()):
            path = os.path.join(directory, uuid.uuid4().hex + ".dat")
            with open(path, "w", encoding="ascii") as schedule:
                for tx, action, resource in operations:
                    schedule.write(f"T{tx} {action} {resource}\n")
            expected = oracle(operations)
            for executable in (EXECUTABLE, REBUILT):
                result = subprocess.run([executable, path], capture_output=True, timeout=3)
                assert result.returncode == expected, (
                    f"generated schedule {index} expected exit {expected}, "
                    f"but {executable} exited {result.returncode}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
