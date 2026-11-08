#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import h5py
import matplotlib.image as mpimg
import numpy as np
import pytest

HOME = "/home/user"


def parse_pdb(filename):
    atoms = []
    with open(filename, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16].strip()
                if "CA" in atom_name:
                    atoms.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
    return atoms


def calc_dist(atoms):
    n = len(atoms)
    mat = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            dx = atoms[i][0] - atoms[j][0]
            dy = atoms[i][1] - atoms[j][1]
            dz = atoms[i][2] - atoms[j][2]
            mat[i][j] = math.sqrt(dx * dx + dy * dy + dz * dz)
    return mat


def lu_decompose(mat, n, eps):
    for i in range(n):
        mat[i][i] += eps
    u_diag = [0.0] * n
    for i in range(n):
        for j in range(i, n):
            s = sum(mat[i][k] * mat[k][j] for k in range(i))
            mat[i][j] -= s
        for j in range(i + 1, n):
            s = sum(mat[j][k] * mat[k][i] for k in range(i))
            if mat[i][i] == 0.0:
                raise ValueError("Zero pivot")
            mat[j][i] = (mat[j][i] - s) / mat[i][i]
        u_diag[i] = mat[i][i]
    return u_diag


def pearson(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))
    den_x = sum((x[i] - mean_x) ** 2 for i in range(n))
    den_y = sum((y[i] - mean_y) ** 2 for i in range(n))
    return num / math.sqrt(den_x * den_y)


def write_pdb(path, atoms):
    with open(path, "w") as f:
        for serial, (x, y, z) in enumerate(atoms, 1):
            line = [" "] * 80
            line[0:6] = "ATOM  "
            line[6:11] = f"{serial:5d}"
            line[12:16] = " CA "
            line[17:20] = "ALA"
            line[21] = "A"
            line[22:26] = f"{serial:4d}"
            line[30:38] = f"{x:8.3f}"
            line[38:46] = f"{y:8.3f}"
            line[46:54] = f"{z:8.3f}"
            line[76:78] = " C"
            f.write("".join(line) + "\n")


def read_u_diag(path, expected_n):
    assert os.path.isfile(path), f"HDF5 output not found at {path}"
    with h5py.File(path, "r") as h5:
        assert "/U_diag" in h5, f"{path} does not contain root dataset /U_diag"
        obj = h5["/U_diag"]
        assert isinstance(obj, h5py.Dataset), "/U_diag is not an HDF5 dataset"
        assert obj.shape == (expected_n,), f"Unexpected /U_diag shape: {obj.shape}"
        assert np.issubdtype(obj.dtype, np.floating), "/U_diag is not floating point"
        return np.asarray(obj[...], dtype=float)


def assert_h5_values(path, atoms, eps):
    actual = read_u_diag(path, len(atoms))
    expected = np.asarray(lu_decompose(calc_dist(atoms), len(atoms), eps))
    np.testing.assert_allclose(actual, expected, rtol=1e-8, atol=1e-8)


def run_analyzer(executable, pdb, output, epsilon_marker):
    cmd = [executable, pdb, output]
    eps = 0.0
    if epsilon_marker is not None:
        eps = epsilon_marker
        cmd.append(format(eps, ".17g"))
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15)
    assert result.returncode == 0, (
        f"{executable} failed on a valid PDB (exit {result.returncode}):\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    atoms = parse_pdb(pdb)
    assert_h5_values(output, atoms, eps)


def test_executable_exists():
    exe_path = "/home/user/analyze_struct"
    assert os.path.isfile(exe_path), f"Compiled executable not found at {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File at {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyze_struct is not a compiled ELF executable"


def test_h5_files_exist():
    h5_a = "/home/user/A_eps0.01.h5"
    h5_b = "/home/user/B_eps0.01.h5"
    assert os.path.isfile(h5_a), f"HDF5 output not found at {h5_a}"
    assert os.path.isfile(h5_b), f"HDF5 output not found at {h5_b}"


def test_python_script_and_plot_exist():
    script_path = "/home/user/compare.py"
    plot_path = "/home/user/plot.png"
    assert os.path.isfile(script_path), f"Python script not found at {script_path}"
    assert os.path.isfile(plot_path), f"Plot image not found at {plot_path}"


def test_correlation_value():
    corr_file = "/home/user/correlation.txt"
    assert os.path.isfile(corr_file), f"Correlation output file not found at {corr_file}"
    atoms_a = parse_pdb("/home/user/structA.pdb")
    atoms_b = parse_pdb("/home/user/structB.pdb")
    expected_corr = pearson(
        lu_decompose(calc_dist(atoms_a), len(atoms_a), 0.01),
        lu_decompose(calc_dist(atoms_b), len(atoms_b), 0.01),
    )
    with open(corr_file, "r") as f:
        content = f.read().strip()
    try:
        student_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse correlation value from {corr_file}. Content was: '{content}'")
    assert abs(student_val - expected_corr) < 1e-3, (
        f"Correlation value in {corr_file} is {student_val}, "
        f"but expected approximately {expected_corr:.4f}."
    )


def test_fixture_hdf5_contents():
    atoms_a = parse_pdb("/home/user/structA.pdb")
    atoms_b = parse_pdb("/home/user/structB.pdb")
    assert_h5_values("/home/user/A_eps0.01.h5", atoms_a, 0.01)
    assert_h5_values("/home/user/B_eps0.01.h5", atoms_b, 0.01)


def test_source_compiles_and_analyzers_work_on_derived_inputs():
    source = "/home/user/analyze_struct.c"
    assert os.path.isfile(source), f"C source not found at {source}"
    rng = secrets.SystemRandom()
    atoms = []
    for i in range(6):
        atoms.append((
            round(i * 0.71 + rng.uniform(-0.18, 0.18), 3),
            round((i % 3) * 0.83 + rng.uniform(-0.18, 0.18), 3),
            round((i % 2) * 0.47 + rng.uniform(-0.18, 0.18), 3),
        ))
    epsilon = rng.uniform(0.21, 0.79)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "analyze_struct_rebuilt")
        build = subprocess.run(
            ["h5cc", source, "-O2", "-o", rebuilt, "-lm"],
            cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30,
        )
        assert build.returncode == 0, (
            f"analyze_struct.c does not compile with HDF5:\n{build.stdout}\n{build.stderr}"
        )
        pdb = os.path.join(td, "derived.pdb")
        one_pdb = os.path.join(td, "one_atom.pdb")
        write_pdb(pdb, atoms)
        write_pdb(one_pdb, [(1.125, -2.25, 3.5)])

        for index, executable in enumerate(("/home/user/analyze_struct", rebuilt)):
            run_analyzer(executable, pdb, os.path.join(td, f"derived_{index}.h5"), epsilon)
            # With one atom, default epsilon=0 is well-defined and must produce [0].
            run_analyzer(executable, one_pdb, os.path.join(td, f"default_{index}.h5"), None)
            # A separate value verifies that the optional argument affects the diagonal.
            run_analyzer(executable, one_pdb, os.path.join(td, f"epsilon_{index}.h5"), 0.347)


def validate_plot(path):
    assert os.path.isfile(path), f"Plot image not found at {path}"
    assert os.path.getsize(path) > 100, "plot.png is empty or not a meaningful image"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "plot.png is not a PNG file"
    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1


def run_compare_and_check(expected):
    corr_path = os.path.join(HOME, "correlation.txt")
    plot_path = os.path.join(HOME, "plot.png")
    for path in (corr_path, plot_path):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ["python3", os.path.join(HOME, "compare.py")], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30,
    )
    assert result.returncode == 0, (
        f"compare.py failed (exit {result.returncode}):\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(corr_path), "compare.py did not create correlation.txt"
    with open(corr_path, "r") as f:
        text = f.read().strip()
    assert re.fullmatch(r"[+-]?\d+\.\d{4}", text), (
        f"correlation.txt must contain a value with exactly four decimal places; got {text!r}"
    )
    assert text == f"{expected:.4f}", f"Expected {expected:.4f}, got {text}"
    validate_plot(plot_path)


def test_compare_script_behavior_on_derived_hdf5_data():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    a = rng.normal(size=9)
    b = 0.35 * a + rng.normal(size=9)
    expected_custom = float(np.corrcoef(a, b)[0, 1])

    path_a = os.path.join(HOME, "A_eps0.01.h5")
    path_b = os.path.join(HOME, "B_eps0.01.h5")
    atoms_a = parse_pdb(os.path.join(HOME, "structA.pdb"))
    atoms_b = parse_pdb(os.path.join(HOME, "structB.pdb"))
    expected_final = pearson(
        lu_decompose(calc_dist(atoms_a), len(atoms_a), 0.01),
        lu_decompose(calc_dist(atoms_b), len(atoms_b), 0.01),
    )

    with tempfile.TemporaryDirectory() as td:
        backup_a = os.path.join(td, "A.h5")
        backup_b = os.path.join(td, "B.h5")
        shutil.copy2(path_a, backup_a)
        shutil.copy2(path_b, backup_b)
        try:
            with h5py.File(path_a, "w") as h5:
                h5.create_dataset("/U_diag", data=a)
            with h5py.File(path_b, "w") as h5:
                h5.create_dataset("/U_diag", data=b)
            run_compare_and_check(expected_custom)
        finally:
            shutil.copy2(backup_a, path_a)
            shutil.copy2(backup_b, path_b)

    # Execute once more on the required final files and leave all requested artifacts valid.
    run_compare_and_check(expected_final)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
