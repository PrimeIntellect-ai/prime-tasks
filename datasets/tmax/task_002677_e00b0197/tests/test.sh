#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import re
import subprocess

import numpy as np
import pytest

SOURCE = "/home/user/fit_loop.c"
BINARY = "/home/user/fit_loop"
REBUILT = "/tmp/fit_loop_rebuilt"


def extract_ca_chain_a(pdb_path):
    coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM  "):
                atom_name = line[12:16].strip()
                chain_id = line[21]
                if atom_name == "CA" and chain_id == "A":
                    try:
                        coords.append([
                            float(line[30:38]),
                            float(line[38:46]),
                            float(line[46:54]),
                        ])
                    except ValueError:
                        pass
    return np.asarray(coords, dtype=float)


def compute_expected_radius(coords):
    assert len(coords) >= 3
    centered = coords - np.mean(coords, axis=0)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    proj = centered @ vt[:2, :].T
    x = proj[:, 0]
    y = proj[:, 1]
    design = np.column_stack((2 * x, 2 * y, np.ones_like(x)))
    a, b, c = np.linalg.lstsq(design, x * x + y * y, rcond=None)[0]
    return float(np.sqrt(a * a + b * b + c))


def atom_line(serial, atom, chain, residue, xyz):
    x, y, z = xyz
    return (
        f"ATOM  {serial:5d} {atom:^4s} ALA {chain}{residue:4d}    "
        f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
    )


def write_case(path, rng, count, radius, arc, noise):
    angles = np.sort(rng.uniform(-arc / 2.0, arc / 2.0, count))
    angles += rng.uniform(-np.pi, np.pi)
    radial = radius + rng.normal(0.0, noise, count)
    local = np.column_stack((
        radial * np.cos(angles),
        radial * np.sin(angles),
        rng.normal(0.0, noise * 0.7 + 0.015, count),
    ))

    q, _ = np.linalg.qr(rng.normal(size=(3, 3)))
    coords = local @ q.T + rng.uniform(-40.0, 40.0, 3)

    with open(path, "w") as f:
        f.write("REMARK dynamically generated verifier case\n")
        f.write(atom_line(1, "CA", "B", 1, rng.uniform(-100, 100, 3)))
        serial = 10
        for i, point in enumerate(coords, 1):
            if i % 4 == 0:
                f.write(atom_line(serial, "CB", "A", i, rng.uniform(-100, 100, 3)))
                serial += 1
            f.write(atom_line(serial, "CA", "A", i, point))
            serial += 1
        f.write(atom_line(serial, "CA", "B", 999, rng.uniform(-100, 100, 3)))
        f.write("END\n")


def parse_and_check(binary, pdb_path):
    try:
        result = subprocess.run(
            [binary, pdb_path], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The C program timed out after 10 seconds.")

    assert result.returncode == 0, (
        f"Program exited with non-zero status code: {result.returncode}\n"
        f"Stderr: {result.stderr}"
    )

    match = re.search(r"Radius:\s*([0-9.]+)", result.stdout)
    assert match, (
        "Could not find 'Radius: <float>' in output.\n"
        f"Output was: {result.stdout}"
    )
    assert re.fullmatch(
        r"\s*Radius:\s*[0-9]+(?:\.[0-9]+)?\s*", result.stdout
    ), f"Output was not in the required format: {result.stdout!r}"

    agent_radius = float(match.group(1))
    expected_radius = compute_expected_radius(extract_ca_chain_a(pdb_path))
    error = abs(agent_radius - expected_radius)
    assert error <= 0.001, (
        "Radius error is too high.\n"
        f"Expected: {expected_radius:.6f}\n"
        f"Got:      {agent_radius:.6f}\n"
        f"Error:    {error:.6f} (Threshold: 0.001)"
    )


def test_01_files_exist_and_source_builds():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Submitted executable must be a compiled ELF binary."

    assert not filecmp.cmp(BINARY, "/app/circle_fitter", shallow=False), (
        "Submission must not be byte-identical to the supplied reference binary."
    )

    source_text = open(SOURCE, "r", errors="replace").read()
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", " ", source_text, flags=re.S)
    code_only = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', " ", without_comments)
    forbidden_calls = r"\b(?:system|popen|fork|vfork|execl|execle|execlp|execv|execve|execvp|posix_spawn|posix_spawnp)\s*\("
    assert not re.search(forbidden_calls, code_only), (
        "The C implementation must perform the fit itself, not launch another program."
    )
    assert "/app/circle_fitter" not in without_comments and "oracle.py" not in without_comments, (
        "The submitted source must not delegate to the supplied oracle."
    )

    result = subprocess.run(
        [
            "gcc", "-O2", SOURCE, "-o", REBUILT,
            "-llapacke", "-llapack", "-lblas", "-lm",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "Source did not compile cleanly.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_02_circle_fitting_accuracy_on_unseen_inputs():
    assert os.path.isfile(REBUILT), "Verifier rebuild was not produced."

    seed = int.from_bytes(os.urandom(16), "little")
    rng = np.random.default_rng(seed)
    cases = [
        (11, rng.uniform(3.0, 8.0), 2.2 * np.pi, 0.025),
        (19, rng.uniform(9.0, 18.0), 2.0 * np.pi, 0.12),
        (31, rng.uniform(20.0, 35.0), 1.45 * np.pi, 0.20),
        (43, rng.uniform(5.0, 25.0), 1.15 * np.pi, 0.08),
    ]

    oracle_path = "/app/circle_fitter"
    hidden_oracle_path = "/tmp/circle_fitter.hidden"
    os.replace(oracle_path, hidden_oracle_path)
    try:
        for index, (count, radius, arc, noise) in enumerate(cases):
            pdb_path = f"/tmp/test_eval_{index}.pdb"
            write_case(pdb_path, rng, count, radius, arc, noise)
            parse_and_check(BINARY, pdb_path)
            parse_and_check(REBUILT, pdb_path)
    finally:
        os.replace(hidden_oracle_path, oracle_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
