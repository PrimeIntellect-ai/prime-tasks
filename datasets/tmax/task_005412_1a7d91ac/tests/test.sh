#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

PROJECT = "/home/user/protein_network"
MAIN = os.path.join(PROJECT, "src/main.rs")
CARGO = os.path.join(PROJECT, "Cargo.toml")
OUTPUT = "/home/user/top_residues.txt"
COMPLEX = "/home/user/data/complex.pdb"
BINARY = os.path.join(PROJECT, "target/release/protein_network")


def parse_pdb(path):
    atoms = []
    with open(path) as f:
        for line in f:
            if line.startswith("ATOM  ") and line[12:16] == " CA ":
                atoms.append((
                    line[21], int(line[22:26].strip()),
                    float(line[30:38]), float(line[38:46]), float(line[46:54])
                ))
    return atoms


def expected_top(atoms):
    n = len(atoms)
    adjacency = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                dx = atoms[i][2] - atoms[j][2]
                dy = atoms[i][3] - atoms[j][3]
                dz = atoms[i][4] - atoms[j][4]
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= 8.0:
                    adjacency[i][j] = 1.0

    transition = [[0.0] * n for _ in range(n)]
    for col in range(n):
        degree = sum(adjacency[row][col] for row in range(n))
        if degree > 0.0:
            for row in range(n):
                transition[row][col] = adjacency[row][col] / degree

    scores = [1.0 / n] * n
    for _ in range(100):
        scores = [
            0.85 * sum(transition[i][j] * scores[j] for j in range(n)) + 0.15 / n
            for i in range(n)
        ]

    order = sorted(range(n), key=lambda i: (-scores[i], atoms[i][0], atoms[i][1]))
    return [f"{atoms[i][0]}:{atoms[i][1]}" for i in order[:3]]


def write_pdb(path, atoms):
    with open(path, "w") as f:
        for serial, (chain, resnum, x, y, z) in enumerate(atoms, 1):
            f.write(
                f"ATOM  {serial:5d}  CA  ALA {chain}{resnum:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 10.00           C  \n"
            )


def run_program(pdb_path):
    old_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            old_output = f.read()
        os.unlink(OUTPUT)
    try:
        result = subprocess.run(
            [BINARY, pdb_path], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert result.returncode == 0, f"Program failed on {pdb_path}: {result.stderr}"
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if not lines and os.path.isfile(OUTPUT):
            with open(OUTPUT) as f:
                lines = [line.strip() for line in f if line.strip()]
        return lines
    finally:
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        if old_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(old_output)


def test_rayon_in_cargo_toml():
    assert os.path.isfile(CARGO), "Cargo.toml is missing."
    with open(CARGO) as f:
        content = f.read()
    assert "rayon" in content, "The 'rayon' crate is missing from Cargo.toml dependencies."
    assert re.search(r"(?m)^\s*rayon\s*=", content), "rayon is not declared as a dependency."


def test_rayon_in_main_rs():
    assert os.path.isfile(MAIN), "main.rs is missing."
    with open(MAIN) as f:
        content = f.read()
    assert "par_iter" in content or "par_iter_mut" in content or "rayon" in content, \
        "Could not find evidence of rayon parallel iterators (e.g., par_iter) in main.rs."
    assert re.search(r"use\s+rayon::prelude", content), "The rayon parallel iterator prelude is not imported."
    first_adjacency = content.find("adjacency")
    first_transition = content.find("transition", first_adjacency + 1)
    assert first_adjacency >= 0 and first_transition > first_adjacency, "Contact graph construction is missing."
    graph_code = content[first_adjacency:first_transition]
    assert re.search(r"\.(?:par_iter(?:_mut)?|into_par_iter)\s*\(", graph_code), \
        "The pairwise contact calculation does not use a rayon parallel iterator."


def test_pagerank_logic_in_main_rs():
    with open(MAIN) as f:
        content = f.read()
    assert "0.85" in content, "The damping factor 0.85 is missing from main.rs."
    assert "0.15" in content, "The teleportation factor 0.15 is missing from main.rs."


def test_output_file_exists_and_correct():
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} was not created."
    with open(OUTPUT) as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ["A:1", "A:2", "A:3"]
    assert expected_top(parse_pdb(COMPLEX)) == expected
    assert len(lines) >= 3, f"Expected at least 3 lines in the output, found {len(lines)}."
    assert lines[:3] == expected, f"The top 3 residues are incorrect. Expected {expected}, got {lines[:3]}."


def test_program_compiles_and_runs_on_provided_input():
    result = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180
    )
    assert result.returncode == 0, f"Cargo build failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), "Cargo did not produce the expected executable."
    expected = expected_top(parse_pdb(COMPLEX))
    actual = run_program(COMPLEX)
    assert actual[:3] == expected, f"Fresh execution produced {actual[:3]}, expected {expected}."


def test_damped_iteration_and_tie_break_on_generated_graph():
    # A four-leaf star. Undamped iteration from a uniform vector oscillates and,
    # after 100 steps, ties all five nodes; damping instead ranks the Z:9 center first.
    atoms = [
        ("A", 1, 4.0, 4.0, 4.0),
        ("A", 2, 4.0, -4.0, -4.0),
        ("A", 3, -4.0, 4.0, -4.0),
        ("A", 4, -4.0, -4.0, 4.0),
        ("Z", 9, 0.0, 0.0, 0.0),
    ]
    path = "/tmp/generated_star.pdb"
    write_pdb(path, atoms)
    expected = expected_top(atoms)
    assert expected == ["Z:9", "A:1", "A:2"]
    actual = run_program(path)
    assert actual[:3] == expected, f"Damped PageRank result was {actual[:3]}, expected {expected}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
