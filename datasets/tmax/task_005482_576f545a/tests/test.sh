#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

C_FILE = "/home/user/query.c"
EXE_FILE = "/home/user/query"
RESULTS_FILE = "/home/user/results.csv"
NODES_FILE = "/home/user/data/nodes.csv"
EDGES_FILE = "/home/user/data/edges.csv"
EXPECTED_ORIGINAL = ["2,4", "5,4", "3,3", "10,3", "6,2", "9,1"]


def read_result_lines():
    assert os.path.isfile(RESULTS_FILE), f"Results file {RESULTS_FILE} does not exist."
    with open(RESULTS_FILE, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def expected_lines(nodes, edges):
    indegree = {paper_id: 0 for paper_id, _, _ in nodes}
    for _, target in edges:
        if target in indegree:
            indegree[target] += 1
    rows = [
        (paper_id, indegree[paper_id])
        for paper_id, year, topic in nodes
        if topic == "Genetics" and year >= 2015
    ]
    rows.sort(key=lambda row: (-row[1], row[0]))
    return [f"{paper_id},{degree}" for paper_id, degree in rows]


def write_dataset(nodes, edges):
    with open(NODES_FILE, "w", encoding="utf-8", newline="") as f:
        for paper_id, year, topic in nodes:
            f.write(f"{paper_id},{year},{topic}\n")
    with open(EDGES_FILE, "w", encoding="utf-8", newline="") as f:
        for source, target in edges:
            f.write(f"{source},{target}\n")


def run_case(executable, nodes, edges, label):
    write_dataset(nodes, edges)
    if os.path.exists(RESULTS_FILE):
        os.unlink(RESULTS_FILE)
    completed = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{label} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    actual = read_result_lines()
    expected = expected_lines(nodes, edges)
    assert actual == expected, (
        f"{label} produced incorrect output.\n"
        f"Expected:\n" + "\n".join(expected) + "\nGot:\n" + "\n".join(actual)
    )


# Preserve all original verifier assertions before modifying any data.
assert os.path.isfile(C_FILE), f"Source file {C_FILE} does not exist."
assert os.path.isfile(EXE_FILE), f"Executable {EXE_FILE} does not exist."
assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
assert os.path.isfile(RESULTS_FILE), f"Results file {RESULTS_FILE} does not exist."
assert read_result_lines() == EXPECTED_ORIGINAL, (
    f"Content of {RESULTS_FILE} does not match expected output."
)

# A GCC-compiled executable in this environment must be an ELF binary.
with open(EXE_FILE, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{EXE_FILE} is not a compiled ELF executable."

with open(NODES_FILE, "rb") as f:
    original_nodes_bytes = f.read()
with open(EDGES_FILE, "rb") as f:
    original_edges_bytes = f.read()
with open(RESULTS_FILE, "rb") as f:
    original_results_bytes = f.read()

compiled_file = tempfile.NamedTemporaryFile(prefix="verified_query_", delete=False)
compiled_path = compiled_file.name
compiled_file.close()
os.unlink(compiled_path)

try:
    compilation = subprocess.run(
        ["gcc", C_FILE, "-O2", "-o", compiled_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compilation.returncode == 0, (
        f"query.c failed to compile with GCC.\nstdout:\n{compilation.stdout}"
        f"\nstderr:\n{compilation.stderr}"
    )
    assert os.path.isfile(compiled_path) and os.access(compiled_path, os.X_OK)

    original_nodes = [
        (1, 2014, "Genetics"), (2, 2015, "Genetics"),
        (3, 2016, "Genetics"), (4, 2018, "Physics"),
        (5, 2020, "Genetics"), (6, 2015, "Genetics"),
        (7, 2010, "Genetics"), (8, 2016, "Chemistry"),
        (9, 2017, "Genetics"), (10, 2021, "Genetics")
    ]
    original_edges = [
        (1,2), (3,2), (4,2), (8,2), (2,3), (4,3), (5,3),
        (6,5), (7,5), (8,5), (10,5), (1,6), (3,6), (10,9),
        (4,10), (5,10), (7,10), (1,4)
    ]

    rng = random.SystemRandom()
    ids = rng.sample(range(100, 99000), 40)
    ids.append(100000)
    mixed_nodes = []
    for i, paper_id in enumerate(ids):
        if i < 10:
            mixed_nodes.append((paper_id, 2015 + rng.randrange(10), "Genetics"))
        else:
            mixed_nodes.append((paper_id, rng.randrange(2008, 2026), rng.choice(["Physics", "Chemistry", "Genetics"])))
    mixed_edges_set = set()
    while len(mixed_edges_set) < 220:
        source, target = rng.sample(ids, 2)
        mixed_edges_set.add((source, target))
    mixed_edges = list(mixed_edges_set)

    zero_ids = rng.sample(range(1, 90000), 9) + [100000]
    zero_nodes = [
        (zero_ids[0], 2015, "Genetics"),
        (zero_ids[1], 2024, "Genetics"),
        (zero_ids[2], 2019, "Genetics"),
        (zero_ids[3], 2017, "Genetics"),
    ] + [(paper_id, 2014, "Genetics") for paper_id in zero_ids[4:7]] + [
        (paper_id, 2020, "Physics") for paper_id in zero_ids[7:]
    ]
    zero_edges = [(zero_ids[i], zero_ids[7 + (i % 3)]) for i in range(7)]

    cases = [
        (original_nodes, original_edges),
        (mixed_nodes, mixed_edges),
        (zero_nodes, zero_edges),
    ]

    # Exercise both the submitted executable and a fresh build of submitted source.
    for executable, name in ((EXE_FILE, "submitted /home/user/query"),
                             (compiled_path, "freshly compiled query.c")):
        for index, (nodes, edges) in enumerate(cases, 1):
            run_case(executable, nodes, edges, f"{name}, case {index}")
finally:
    with open(NODES_FILE, "wb") as f:
        f.write(original_nodes_bytes)
    with open(EDGES_FILE, "wb") as f:
        f.write(original_edges_bytes)
    with open(RESULTS_FILE, "wb") as f:
        f.write(original_results_bytes)
    if os.path.exists(compiled_path):
        os.unlink(compiled_path)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
