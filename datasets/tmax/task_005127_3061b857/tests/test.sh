#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/project")
EXECUTABLE = PROJECT_DIR / "sanitise_deps"


def run_tool(path, timeout=5):
    return subprocess.run(
        [str(EXECUTABLE), str(path)],
        cwd=str(PROJECT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def oracle(data):
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        return False

    graph = {}
    for line in text.split("\n"):
        fields = line.split()
        if not fields:
            continue
        for field in fields:
            if "\x00" in field or "../" in field or "..\\" in field:
                return False
        graph.setdefault(fields[0], []).extend(fields[1:])
        for dependency in fields[1:]:
            graph.setdefault(dependency, [])

    state = {}

    def visit(node):
        status = state.get(node, 0)
        if status == 1:
            return False
        if status == 2:
            return True
        state[node] = 1
        for dependency in graph.get(node, []):
            if not visit(dependency):
                return False
        state[node] = 2
        return True

    return all(visit(node) for node in graph)


def assert_result(path, expected):
    result = run_tool(path)
    if expected:
        assert result.returncode == 0, (
            f"valid input was rejected with code {result.returncode}; stderr={result.stderr!r}"
        )
        assert result.stdout == b"ACCEPT\n", f"unexpected stdout: {result.stdout!r}"
    else:
        assert result.returncode == 1, (
            f"invalid input was not rejected with code 1; code={result.returncode}, "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert result.stdout == b"REJECT\n", f"unexpected stdout: {result.stdout!r}"


def test_compilation():
    cpp_file = PROJECT_DIR / "sanitise_deps.cpp"
    makefile = PROJECT_DIR / "Makefile"

    assert cpp_file.is_file(), f"Source file {cpp_file} is missing."
    assert makefile.is_file(), f"Makefile {makefile} is missing."

    if EXECUTABLE.exists() or EXECUTABLE.is_symlink():
        EXECUTABLE.unlink()

    result = subprocess.run(
        ["make"], cwd=str(PROJECT_DIR), capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"Compilation failed. Make output:\n{result.stdout}\n{result.stderr}"
    )
    assert EXECUTABLE.is_file(), "Executable 'sanitise_deps' was not created by make."
    assert os.access(EXECUTABLE, os.X_OK), "Executable is not executable."
    assert EXECUTABLE.read_bytes()[:4] == b"\x7fELF", "Make did not produce a compiled executable."


def test_adversarial_corpus():
    evil_dir = Path("/app/tests/evil")
    clean_dir = Path("/app/tests/clean")
    evil_files = [f for f in evil_dir.iterdir() if f.is_file()]
    clean_files = [f for f in clean_dir.iterdir() if f.is_file()]

    assert evil_files, "Evil corpus is empty or missing."
    assert clean_files, "Clean corpus is empty or missing."

    evil_bypassed = []
    clean_modified = []
    for path in evil_files:
        result = run_tool(path)
        if result.returncode != 1 or result.stdout.strip() != b"REJECT":
            evil_bypassed.append(path.name)
    for path in clean_files:
        result = run_tool(path)
        if result.returncode != 0 or result.stdout.strip() != b"ACCEPT":
            clean_modified.append(path.name)

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(clean_modified)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def make_valid_case(rng):
    count = rng.randrange(3, 12)
    salt = secrets.token_hex(5)
    prefixes = ["node", "café", "資料", "δοκιμή", "emoji😀"]
    names = [f"{rng.choice(prefixes)}_{salt}_{i}" for i in range(count)]
    lines = []
    for i, name in enumerate(names):
        dependencies = [
            names[j] for j in range(i + 1, count) if rng.randrange(4) == 0
        ]
        lines.append(" ".join([name] + dependencies))
    rng.shuffle(lines)
    lines.insert(rng.randrange(len(lines) + 1), "")
    return ("\n".join(lines) + "\n").encode("utf-8")


def make_cycle_case(rng):
    salt = secrets.token_hex(6)
    length = rng.randrange(1, 9)
    nodes = [f"cycle_{salt}_{i}" for i in range(length)]
    lines = []
    if length == 1:
        lines.append(f"{nodes[0]} {nodes[0]}")
    else:
        for i, node in enumerate(nodes):
            lines.append(f"{node} {nodes[(i + 1) % length]}")
    lines.extend([
        f"safe_{salt}_0 safe_{salt}_1",
        f"safe_{salt}_1 safe_{salt}_2",
    ])
    rng.shuffle(lines)
    return ("\n".join(lines) + "\n").encode("utf-8")


def make_traversal_case(rng):
    salt = secrets.token_hex(6)
    attacks = [
        "../secret", "a/../../b", "..\\windows", "prefix..\\suffix",
        "資料/../秘密", "x../y"
    ]
    attack = rng.choice(attacks)
    if rng.randrange(2):
        text = f"target_{salt} {attack}\nother_{salt}\n"
    else:
        text = f"{attack} dependency_{salt}\n"
    return text.encode("utf-8")


def make_bad_utf8_case(rng):
    bad_sequences = [
        b"\xff", b"\xfe", b"\xc0\xaf", b"\xe0\x80\xaf",
        b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xe2\x82", b"\x80"
    ]
    salt = secrets.token_hex(6).encode("ascii")
    return b"root_" + salt + b" child_" + rng.choice(bad_sequences) + b"\n"


def make_null_case(rng):
    salt = secrets.token_hex(6).encode("ascii")
    if rng.randrange(2):
        return b"root_" + salt + b" dep\x00hidden\n"
    return b"bad\x00target_" + salt + b" dep\n"


def test_runtime_generated_inputs():
    rng = secrets.SystemRandom()
    generators = [
        make_valid_case,
        make_cycle_case,
        make_traversal_case,
        make_bad_utf8_case,
        make_null_case,
    ]

    with tempfile.TemporaryDirectory(prefix="dependency-check-" + secrets.token_hex(8) + "-") as td:
        root = Path(td)
        cases = []
        for index in range(100):
            generator = generators[index % len(generators)]
            cases.append(generator(rng))
        rng.shuffle(cases)

        for index, data in enumerate(cases):
            expected = oracle(data)
            path = root / f"{secrets.token_hex(12)}-{index}.graph"
            path.write_bytes(data)
            assert_result(path, expected)

        # Exercise an empty graph separately.
        empty_path = root / (secrets.token_hex(12) + ".empty")
        empty_path.write_bytes(b"\n\n")
        assert oracle(empty_path.read_bytes())
        assert_result(empty_path, True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
