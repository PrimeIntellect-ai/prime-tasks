#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import pstats
import re
import subprocess

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/md_analysis.py"
PDB_PATH = "/home/user/protein_frame.pdb"
RESULT_PATH = "/home/user/energy_result.txt"
PROFILE_PATH = "/home/user/profile.prof"


def compute_expected_energy(path=PDB_PATH):
    """Recompute the expected energy independently using the standard library."""
    atoms = []
    with open(path, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                name = line[12:16].strip()
                if name == "CA":
                    atoms.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))

    energies = []
    for i in range(len(atoms)):
        xi, yi, zi = atoms[i]
        for j in range(i + 1, len(atoms)):
            xj, yj, zj = atoms[j]
            dx, dy, dz = xi - xj, yi - yj, zi - zj
            r2 = dx * dx + dy * dy + dz * dz
            r6 = r2 * r2 * r2
            if r6 > 0:
                energies.append((1.0 / (r6 * r6)) - (1.0 / r6))
    return math.fsum(energies)


def assert_result(expected):
    assert os.path.isfile(RESULT_PATH), f"Missing file: {RESULT_PATH}"
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{8}", content), \
        f"Energy result '{content}' is not formatted to exactly 8 decimal places."
    assert math.isclose(float(content), expected, rel_tol=1e-5, abs_tol=1e-5), \
        f"Calculated energy {content} does not match expected energy {expected}."


def assert_profile_is_for_script(profile_path=PROFILE_PATH):
    assert os.path.isfile(profile_path), f"Missing profiling output: {profile_path}"
    try:
        stats = pstats.Stats(profile_path)
    except Exception as exc:
        pytest.fail(f"Failed to parse {profile_path} as a pstats file: {exc}")
    assert stats.total_calls > 0 or len(stats.stats) > 0, "Profile file is empty or invalid."
    profiled_files = {os.path.realpath(key[0]) for key in stats.stats}
    assert os.path.realpath(SCRIPT_PATH) in profiled_files, \
        "The profile does not contain execution of /home/user/md_analysis.py."


def test_energy_result_file():
    assert os.path.isfile(RESULT_PATH), f"Missing file: {RESULT_PATH}"
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{8}", content), \
        f"Energy result '{content}' is not formatted to exactly 8 decimal places."


def test_energy_value():
    with open(RESULT_PATH, "r") as f:
        student_val = float(f.read().strip())
    expected_val = compute_expected_energy()
    assert math.isclose(student_val, expected_val, rel_tol=1e-5, abs_tol=1e-5), \
        f"Calculated energy {student_val} does not match expected energy {expected_val}."


def test_profile_exists():
    assert_profile_is_for_script()
    assert os.path.getmtime(PROFILE_PATH) >= os.path.getmtime(SCRIPT_PATH), \
        "profile.prof predates the submitted script and therefore does not profile the final script."


def test_script_updated():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "concurrent.futures" not in content, "Script still contains concurrent.futures."
    assert "ThreadPoolExecutor" not in content, "Script still contains ThreadPoolExecutor."
    assert "import numpy" in content or "from numpy" in content, \
        "Script does not appear to import numpy."

    tree = ast.parse(content, filename=SCRIPT_PATH)
    forbidden_loops = (ast.For, ast.AsyncFor, ast.While, ast.ListComp,
                       ast.SetComp, ast.DictComp, ast.GeneratorExp)
    found = [type(node).__name__ for node in ast.walk(tree) if isinstance(node, forbidden_loops)]
    assert not found, f"Python loops/comprehensions remain in the script: {found}"

    forbidden_calls = {"map", "filter"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            assert node.func.id not in forbidden_calls, \
                f"Python iteration via {node.func.id}() is not vectorized."
        if isinstance(node, ast.Attribute):
            assert node.attr not in {"vectorize", "frompyfunc", "apply_along_axis", "nditer"}, \
                f"numpy.{node.attr} is not a vectorized pairwise calculation."


def _write_fixture(seed, count):
    rng = np.random.default_rng(seed)
    side = int(np.ceil(count ** (1.0 / 3.0)))
    coords = []
    for k in range(count):
        x = (k % side) * 1.31
        y = ((k // side) % side) * 1.37
        z = (k // (side * side)) * 1.43
        coords.append(np.array([x, y, z]) + rng.uniform(-0.04, 0.04, 3))

    with open(PDB_PATH, "w") as f:
        f.write("REMARK verifier-generated input\n")
        serial = 1
        for residue, xyz in enumerate(coords, 1):
            x, y, z = xyz
            f.write(f"ATOM  {serial:5d}  CA  ALA A {residue:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
            serial += 1
            # Decoys exercise both the exact record-prefix and exact atom-name rules.
            if residue % 7 == 0:
                f.write(f"ATOM  {serial:5d}  CB  ALA A {residue:4d}    {x+0.2:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
                serial += 1
            if residue % 11 == 0:
                f.write(f"HETATM{serial:5d}  CA  ALA A {residue:4d}    {x:8.3f}{y+0.2:8.3f}{z:8.3f}  1.00  0.00           C  \n")
                serial += 1


def _snapshot(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def _restore(path, data):
    if data is None:
        if os.path.exists(path):
            os.remove(path)
    else:
        with open(path, "wb") as f:
            f.write(data)


def test_script_executes_on_unseen_inputs_and_profile_is_genuine():
    saved = {path: _snapshot(path) for path in (PDB_PATH, RESULT_PATH, PROFILE_PATH)}
    try:
        # Two verifier-generated inputs prevent a fixed or precomputed answer from passing.
        for seed, count, profiled in ((int.from_bytes(os.urandom(8), "little"), 47, False),
                                      (int.from_bytes(os.urandom(8), "little"), 59, True)):
            _write_fixture(seed, count)
            expected = compute_expected_energy()
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)

            if profiled:
                if os.path.exists(PROFILE_PATH):
                    os.remove(PROFILE_PATH)
                command = ["python3", "-m", "cProfile", "-o", PROFILE_PATH, SCRIPT_PATH]
            else:
                command = ["python3", SCRIPT_PATH]

            completed = subprocess.run(command, cwd="/home/user", text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       timeout=20)
            assert completed.returncode == 0, \
                f"Submitted script failed when executed:\n{completed.stderr}"
            assert_result(expected)
            if profiled:
                assert_profile_is_for_script()
    finally:
        for path, data in saved.items():
            _restore(path, data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
