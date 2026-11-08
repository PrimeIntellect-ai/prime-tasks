#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir="$(mktemp -d)"
cp /home/user/nodes.csv "$backup_dir/nodes.csv"
cp /home/user/edges.csv "$backup_dir/edges.csv"
if [ -e /home/user/cycles.txt ]; then
    cp /home/user/cycles.txt "$backup_dir/cycles.txt"
    touch "$backup_dir/had_cycles"
fi
restore_files() {
    cp "$backup_dir/nodes.csv" /home/user/nodes.csv
    cp "$backup_dir/edges.csv" /home/user/edges.csv
    if [ -e "$backup_dir/had_cycles" ]; then
        cp "$backup_dir/cycles.txt" /home/user/cycles.txt
    else
        rm -f /home/user/cycles.txt
    fi
    rm -rf "$backup_dir"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
import tempfile

NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
CYCLES = "/home/user/cycles.txt"
SOURCE = "/home/user/analyzer.cpp"


def test_cycles_txt_exists_and_content():
    cycles_path = "/home/user/cycles.txt"
    assert os.path.isfile(cycles_path), f"File {cycles_path} does not exist. Did you compile and run your C++ program?"

    with open(cycles_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "101,102,103",
        "101,103,104"
    ]

    assert lines == expected_lines, (
        f"Content of {cycles_path} is incorrect.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{lines}"
    )


def compile_submission():
    assert os.path.lexists(SOURCE), f"Required C++ source {SOURCE} does not exist"
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE} must be a regular C++ source file"

    build_dir = tempfile.mkdtemp(prefix="verify_analyzer_")
    os.chmod(build_dir, 0o755)
    binary = os.path.join(build_dir, "analyzer")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"analyzer.cpp did not compile with C++17:\n{result.stderr}"
    os.chmod(binary, 0o755)
    return binary


def expected_cycles(node_ids, edges):
    known = set(node_ids)
    adjacency = {node_id: set() for node_id in node_ids}
    for src, dst, rel_type, amount in edges:
        if src in known and dst in known and rel_type == "TRANSFER" and int(amount) >= 1000:
            adjacency[src].add(dst)

    found = set()
    for a in node_ids:
        for b in adjacency[a]:
            for c in adjacency.get(b, ()):
                if len({a, b, c}) == 3 and a in adjacency.get(c, ()):
                    found.add(tuple(sorted((a, b, c))))
    return [",".join(cycle) for cycle in sorted(found)]


def write_dataset(node_ids, edges):
    with open(NODES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["node_id", "node_type", "name"])
        for i, node_id in enumerate(node_ids):
            writer.writerow([node_id, "PERSON" if i % 2 == 0 else "CORP", f"Entity{i}"])

    with open(EDGES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["src_id", "dst_id", "rel_type", "amount"])
        writer.writerows(edges)


def execute_and_check(binary, node_ids, edges, timeout):
    write_dataset(node_ids, edges)
    if os.path.exists(CYCLES):
        os.remove(CYCLES)

    result = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Compiled analyzer exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CYCLES), "Executing the compiled analyzer did not create /home/user/cycles.txt"

    with open(CYCLES, "r", newline="") as f:
        actual = f.read().splitlines()
    expected = expected_cycles(node_ids, edges)
    assert actual == expected, f"Analyzer output is incorrect for a verifier-generated graph.\nExpected: {expected}\nGot: {actual}"


def test_compiled_program_on_generated_graphs():
    binary = compile_submission()
    prefix = "v" + secrets.token_hex(5) + "_"
    ids = [prefix + suffix for suffix in ["2", "10", "a", "b", "c", "x", "y", "z", "last"]]
    edges = [
        (ids[0], ids[1], "TRANSFER", "1000"),
        (ids[1], ids[2], "TRANSFER", "2450"),
        (ids[2], ids[0], "TRANSFER", "1300"),
        (ids[2], ids[3], "TRANSFER", "5000"),
        (ids[3], ids[4], "TRANSFER", "1001"),
        (ids[4], ids[2], "TRANSFER", "1000"),
        (ids[5], ids[6], "TRANSFER", "4000"),
        (ids[6], ids[7], "TRANSFER", "999"),
        (ids[7], ids[5], "TRANSFER", "4000"),
        (ids[0], ids[5], "PAYMENT", "9000"),
        (ids[5], ids[4], "TRANSFER", "8000"),
        (ids[4], ids[0], "TRANSFER", "8000"),
        (ids[0], ids[1], "TRANSFER", "1500"),
    ]
    execute_and_check(binary, ids, edges, timeout=5)

    # A large sparse graph makes a full O(N^3) node scan impractical while
    # remaining quick for an indexed adjacency-list implementation.
    large_prefix = "p" + secrets.token_hex(4) + "_"
    large_ids = [f"{large_prefix}{i:04d}" for i in range(3000)]
    large_edges = []
    for i in range(len(large_ids)):
        for offset in (1, 17, 43, 101):
            if i + offset < len(large_ids):
                large_edges.append((large_ids[i], large_ids[i + offset], "TRANSFER", "1200"))
    for a, b, c in ((7, 516, 1010), (1300, 1811, 2450), (2700, 2803, 2999)):
        large_edges.extend([
            (large_ids[a], large_ids[b], "TRANSFER", "1000"),
            (large_ids[b], large_ids[c], "TRANSFER", "5000"),
            (large_ids[c], large_ids[a], "TRANSFER", "2500"),
        ])
    large_edges.extend([
        (large_ids[50], large_ids[60], "TRANSFER", "999"),
        (large_ids[60], large_ids[70], "TRANSFER", "9000"),
        (large_ids[70], large_ids[50], "TRANSFER", "9000"),
        (large_ids[100], large_ids[200], "PAYMENT", "9000"),
    ])
    execute_and_check(binary, large_ids, large_edges, timeout=8)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
