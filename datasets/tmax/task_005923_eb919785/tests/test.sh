#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess


class LCG:
    def __init__(self, seed=12345):
        self.state = seed

    def next_rand(self):
        self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
        return self.state


def compute_expected_stats(pdb_path):
    with open(pdb_path, "r") as f:
        lines = f.readlines()

    atoms = []
    for line in lines:
        if line.startswith("ATOM  "):
            try:
                x = float(line[30:38].strip())
                y = float(line[38:46].strip())
                z = float(line[46:54].strip())
                atoms.append((x, y, z))
            except ValueError:
                parts = line.split()
                x, y, z = float(parts[5]), float(parts[6]), float(parts[7])
                atoms.append((x, y, z))

    edges = []
    for i in range(len(atoms)):
        for j in range(i + 1, len(atoms)):
            dx = atoms[i][0] - atoms[j][0]
            dy = atoms[i][1] - atoms[j][1]
            dz = atoms[i][2] - atoms[j][2]
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if 0.0 < dist <= 1.8:
                edges.append(dist)

    n_atoms = len(atoms)
    n_edges = len(edges)
    mean_edge = sum(edges) / n_edges if n_edges > 0 else 0.0

    means = []
    if n_edges > 0:
        lcg = LCG()
        for _ in range(10000):
            sample_sum = 0.0
            for _ in range(n_edges):
                sample_sum += edges[lcg.next_rand() % n_edges]
            means.append(sample_sum / n_edges)
        means.sort()
        ci_lower = means[250]
        ci_upper = means[9749]
    else:
        ci_lower = 0.0
        ci_upper = 0.0

    return n_atoms, n_edges, mean_edge, ci_lower, ci_upper


def assert_stats_file(stats_path, expected):
    assert os.path.isfile(stats_path), f"The output file {stats_path} is missing."
    with open(stats_path, "r") as f:
        content = f.read().strip()

    parsed_stats = {}
    for line in content.split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            parsed_stats[key.strip()] = val.strip()

    exp_atoms, exp_edges, exp_mean, exp_ci_lower, exp_ci_upper = expected
    assert "Atoms" in parsed_stats, "Output is missing 'Atoms' field."
    assert int(parsed_stats["Atoms"]) == exp_atoms, f"Expected {exp_atoms} atoms, got {parsed_stats['Atoms']}."
    assert "Edges" in parsed_stats, "Output is missing 'Edges' field."
    assert int(parsed_stats["Edges"]) == exp_edges, f"Expected {exp_edges} edges, got {parsed_stats['Edges']}."
    assert "Mean" in parsed_stats, "Output is missing 'Mean' field."
    assert math.isclose(float(parsed_stats["Mean"]), exp_mean, abs_tol=1e-4), f"Expected Mean ~{exp_mean:.4f}, got {parsed_stats['Mean']}."
    assert "CI_Lower" in parsed_stats, "Output is missing 'CI_Lower' field."
    assert math.isclose(float(parsed_stats["CI_Lower"]), exp_ci_lower, abs_tol=1e-4), f"Expected CI_Lower ~{exp_ci_lower:.4f}, got {parsed_stats['CI_Lower']}."
    assert "CI_Upper" in parsed_stats, "Output is missing 'CI_Upper' field."
    assert math.isclose(float(parsed_stats["CI_Upper"]), exp_ci_upper, abs_tol=1e-4), f"Expected CI_Upper ~{exp_ci_upper:.4f}, got {parsed_stats['CI_Upper']}."


def pdb_atom(serial, x, y, z):
    return f"ATOM  {serial:5d}  CA  GLY A{1:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C\n"


def make_random_pdb(rng, case_number):
    bx = round(rng.uniform(-4.0, 4.0), 3)
    by = round(rng.uniform(-4.0, 4.0), 3)
    bz = round(rng.uniform(-4.0, 4.0), 3)
    points = [
        (bx, by, bz),
        (bx + round(rng.uniform(0.55, 1.25), 3), by, bz),
        (bx + 1.800, by, bz),
        (bx, by, bz),
    ]
    for _ in range(3 + case_number):
        points.append((
            bx + round(rng.uniform(-2.4, 2.4), 3),
            by + round(rng.uniform(-2.4, 2.4), 3),
            bz + round(rng.uniform(-2.4, 2.4), 3),
        ))

    lines = ["HEADER    VERIFIER GENERATED STRUCTURE\n"]
    for serial, point in enumerate(points, 1):
        lines.append(pdb_atom(serial, *point))
        if serial == 2:
            lines.append("HETATM 9999  O   HOH Z 999     0.000   0.000   0.000\n")
            lines.append("ATOMX  9998  C   IGN Z 999     0.000   0.000   0.000\n")
    return ''.join(lines)


def test_c_source_exists():
    assert os.path.isfile("/home/user/process_pdb.c"), "The C source file /home/user/process_pdb.c is missing."


def test_executable_exists():
    path = "/home/user/process_pdb"
    assert os.path.isfile(path), "The executable /home/user/process_pdb is missing."
    assert os.access(path, os.X_OK), "The file /home/user/process_pdb is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF program."


def test_graph_stats_output():
    stats_path = "/home/user/graph_stats.txt"
    assert os.path.isfile(stats_path), f"The output file {stats_path} is missing."
    pdb_path = "/home/user/data.pdb"
    assert os.path.isfile(pdb_path), f"The input file {pdb_path} is missing."
    assert_stats_file(stats_path, compute_expected_stats(pdb_path))


def test_program_processes_unseen_pdb_inputs():
    source = "/home/user/process_pdb.c"
    submitted_exe = "/home/user/process_pdb"
    rebuilt_exe = "/tmp/verifier_process_pdb"
    pdb_path = "/home/user/data.pdb"
    stats_path = "/home/user/graph_stats.txt"

    compile_result = subprocess.run(
        ["gcc", "-O2", source, "-o", rebuilt_exe, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, "process_pdb.c does not compile with gcc -O2 -lm:\n" + compile_result.stderr

    with open(pdb_path, "rb") as f:
        original_pdb = f.read()
    original_stats = None
    if os.path.exists(stats_path):
        with open(stats_path, "rb") as f:
            original_stats = f.read()

    rng = secrets.SystemRandom()
    cases = [make_random_pdb(rng, i) for i in range(3)]

    try:
        for case_number, pdb_content in enumerate(cases):
            for executable in (submitted_exe, rebuilt_exe):
                with open(pdb_path, "w") as f:
                    f.write(pdb_content)
                expected = compute_expected_stats(pdb_path)
                assert expected[1] > 0
                if os.path.exists(stats_path):
                    os.unlink(stats_path)

                result = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert result.returncode == 0, f"{executable} failed on generated input {case_number}:\n{result.stderr}"
                assert_stats_file(stats_path, expected)
    finally:
        with open(pdb_path, "wb") as f:
            f.write(original_pdb)
        if original_stats is None:
            if os.path.exists(stats_path):
                os.unlink(stats_path)
        else:
            with open(stats_path, "wb") as f:
                f.write(original_stats)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
