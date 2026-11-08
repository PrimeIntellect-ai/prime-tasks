#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_c_source_file_exists():
    c_file = "/home/user/analyze_backups.c"
    assert os.path.exists(c_file), f"C source file {c_file} does not exist."
    assert os.path.isfile(c_file), f"Path {c_file} is not a file."


def test_binary_executable_exists():
    binary_file = "/home/user/analyze_backups"
    assert os.path.exists(binary_file), f"Compiled binary {binary_file} does not exist."
    assert os.path.isfile(binary_file), f"Path {binary_file} is not a file."
    assert os.access(binary_file, os.X_OK), f"File {binary_file} is not executable."
    with open(binary_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {binary_file} is not a compiled ELF executable."


def test_top_backups_txt_content():
    output_file = "/home/user/top_backups.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

    expected_lines = [
        "db_core,9",
        "db_users,4",
        "db_logs,2",
        "db_orders,2",
        "db_analytics,1"
    ]

    with open(output_file, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_file}, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual.strip()}'."


def expected_output(edges):
    nodes = set()
    children = {}
    for dependent, parent in edges:
        nodes.update((dependent, parent))
        children.setdefault(parent, set()).add(dependent)

    def descendants(start):
        seen = set()
        stack = list(children.get(start, ()))
        while stack:
            node = stack.pop()
            if node in seen:
                continue
            seen.add(node)
            stack.extend(children.get(node, ()))
        return len(seen)

    rows = [(node, descendants(node)) for node in nodes]
    rows = [row for row in rows if row[1] > 0]
    rows.sort(key=lambda row: (-row[1], row[0]))
    return [f"{name},{score}" for name, score in rows[:5]]


def run_case(binary, edges):
    with open("/home/user/backups.tsv", "w") as f:
        for dependent, parent in edges:
            f.write(f"{dependent}\t{parent}\n")

    try:
        os.remove("/home/user/top_backups.txt")
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile("/home/user/top_backups.txt"), (
        f"{binary} did not create /home/user/top_backups.txt"
    )
    with open("/home/user/top_backups.txt", "r") as f:
        actual = [line.strip() for line in f.read().strip().splitlines()]
    assert actual == expected_output(edges)


def test_program_compiles_and_handles_unseen_graphs():
    compiled = "/tmp/analyze_backups_from_source"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/analyze_backups.c", "-o", compiled],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"C source failed to compile: {build.stderr}"

    with open("/home/user/backups.tsv", "rb") as f:
        original_input = f.read()
    output_existed = os.path.exists("/home/user/top_backups.txt")
    original_output = None
    if output_existed:
        with open("/home/user/top_backups.txt", "rb") as f:
            original_output = f.read()

    token = secrets.token_hex(6)
    chain = [f"db_{token}_{i:02d}" for i in range(12)]
    chain_edges = [(chain[i], chain[i - 1]) for i in range(1, len(chain))]
    chain_edges += [(chain[i], chain[i - 2]) for i in range(2, len(chain), 2)]

    tied = [f"node_{secrets.token_hex(5)}" for _ in range(10)]
    tie_edges = [
        (tied[1], tied[0]), (tied[2], tied[0]),
        (tied[4], tied[3]), (tied[5], tied[3]),
        (tied[7], tied[6]), (tied[9], tied[8])
    ]

    try:
        for binary in ("/home/user/analyze_backups", compiled):
            run_case(binary, chain_edges)
            run_case(binary, tie_edges)
    finally:
        with open("/home/user/backups.tsv", "wb") as f:
            f.write(original_input)
        if output_existed:
            with open("/home/user/top_backups.txt", "wb") as f:
                f.write(original_output)
        else:
            try:
                os.remove("/home/user/top_backups.txt")
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
