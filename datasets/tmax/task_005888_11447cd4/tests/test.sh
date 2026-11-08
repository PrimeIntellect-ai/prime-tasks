#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import subprocess
import sys

import pytest

DUMP_PATH = "/home/user/crash_memory.dump"
SCRIPT_PATH = "/home/user/processor.py"
RESOLUTION_PATH = "/home/user/resolution.txt"


def expected_checksum(numbers):
    return sum(((n + 0x5A) * 13) % 256 for n in numbers)


def run_processor(numbers):
    payload = ",".join(str(n) for n in numbers)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, payload],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"processor.py exited with status {result.returncode}. stderr: {result.stderr!r}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"-?\d+", output), (
        f"processor.py must print only the resulting checksum number, got {result.stdout!r}"
    )
    return int(output)


def test_resolution_content():
    assert os.path.exists(DUMP_PATH), f"Memory dump file {DUMP_PATH} is missing."

    with open(DUMP_PATH, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    m = re.search(r'PAYLOAD_START\{(.*?)\}PAYLOAD_END', content)
    assert m is not None, "Could not find payload in crash_memory.dump"

    payload_str = m.group(1)
    numbers = [int(x.strip()) for x in payload_str.split(',') if x.strip()]
    expected_sum = expected_checksum(numbers)

    assert os.path.exists(RESOLUTION_PATH), f"Resolution file {RESOLUTION_PATH} is missing."
    with open(RESOLUTION_PATH, "r", encoding="utf-8") as f:
        res_content = f.read().strip()

    assert res_content == str(expected_sum), (
        f"Expected resolution.txt to contain '{expected_sum}', but found '{res_content}'."
    )

    actual = run_processor(numbers)
    assert actual == expected_sum, (
        f"processor.py produced {actual} for the extracted payload; expected {expected_sum}."
    )


def test_processor_script_fixes():
    assert os.path.exists(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original checks.
    assert "Lock" in content or "Semaphore" in content, (
        "The script does not appear to use a threading Lock to fix the race condition."
    )

    try:
        tree = ast.parse(content)
    except SyntaxError:
        pytest.fail("processor.py contains syntax errors.")

    assert "val + 0x5A * 13 % 256" not in content.replace(" ", ""), (
        "The order of operations bug is still present in processor.py."
    )

    # Require a real shared synchronization primitive, not merely the word Lock
    # in a comment. Support threading.Lock/Semaphore and imported aliases.
    constructors = {"Lock", "Semaphore"}
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module == "threading":
            for name in node.names:
                if name.name in ("Lock", "Semaphore"):
                    constructors.add(name.asname or name.name)

    lock_names = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        value = node.value
        if not isinstance(value, ast.Call):
            continue
        func = value.func
        is_constructor = (
            isinstance(func, ast.Name) and func.id in constructors
        ) or (
            isinstance(func, ast.Attribute)
            and func.attr in ("Lock", "Semaphore")
            and isinstance(func.value, ast.Name)
            and func.value.id == "threading"
        )
        if not is_constructor:
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        for target in targets:
            if isinstance(target, ast.Name):
                lock_names.add(target.id)

    assert lock_names, "processor.py does not instantiate a threading Lock or Semaphore."

    worker = next(
        (node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "worker"),
        None,
    )
    assert worker is not None, "processor.py no longer defines the worker function."

    context_managed = False
    acquired = set()
    released = set()
    for node in ast.walk(worker):
        if isinstance(node, (ast.With, ast.AsyncWith)):
            for item in node.items:
                if any(
                    isinstance(name, ast.Name) and name.id in lock_names
                    for name in ast.walk(item.context_expr)
                ):
                    context_managed = True
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            owner = node.func.value
            if isinstance(owner, ast.Name) and owner.id in lock_names:
                if node.func.attr == "acquire":
                    acquired.add(owner.id)
                elif node.func.attr == "release":
                    released.add(owner.id)

    assert context_managed or (acquired & released), (
        "The worker function does not actually use the shared Lock/Semaphore."
    )


def test_processor_formula_and_concurrent_updates_behaviorally():
    # Runtime-generated inputs prevent the verifier from trusting a submitted
    # precomputed answer. Singleton cases isolate calc_hash behavior.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    singleton_values = [0, 1, 15, 90, 255] + [rng.randrange(0, 1000) for _ in range(4)]
    for value in singleton_values:
        numbers = [value]
        assert run_processor(numbers) == expected_checksum(numbers), (
            f"Incorrect formula result for input {value}."
        )

    # Repeated, sufficiently large four-way workloads expose the original lost
    # update race while remaining quick for the synchronized implementation.
    for _ in range(4):
        numbers = [rng.randrange(0, 1000) for _ in range(257)]
        actual = run_processor(numbers)
        expected = expected_checksum(numbers)
        assert actual == expected, (
            f"Concurrent checksum was {actual}; expected {expected}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
