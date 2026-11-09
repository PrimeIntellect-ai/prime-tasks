#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import subprocess


def compute_gd(X, Y, Z, alpha=0.01, iters=1000, lam=0.5):
    w1, w2, b = 0.0, 0.0, 0.0
    m = len(X)
    if m == 0:
        return 0.0, 0.0, 0.0
    for _ in range(iters):
        dw1, dw2, db = 0.0, 0.0, 0.0
        for i in range(m):
            pred = w1 * X[i] + w2 * Y[i] + b
            err = pred - Z[i]
            dw1 += err * X[i]
            dw2 += err * Y[i]
            db += err
        dw1 = dw1 / m + lam * w1
        dw2 = dw2 / m + lam * w2
        db = db / m
        w1 -= alpha * dw1
        w2 -= alpha * dw2
        b -= alpha * db
    return w1, w2, b


def parse_pdb(filepath):
    X, Y, Z = [], [], []
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith("ATOM  ") or line.startswith("HETATM"):
                try:
                    x = float(line[30:38].strip())
                    y = float(line[38:46].strip())
                    z = float(line[46:54].strip())
                    X.append(x)
                    Y.append(y)
                    Z.append(z)
                except ValueError:
                    pass
    return X, Y, Z


def expected_results():
    expected_lines = []
    for filepath in sorted(glob.glob('/home/user/pdb_data/*.pdb')):
        X, Y, Z = parse_pdb(filepath)
        w1, w2, b = compute_gd(X, Y, Z)
        expected_lines.append(
            f"{os.path.basename(filepath)}: w1: {w1:.4f}, w2: {w2:.4f}, b: {b:.4f}"
        )
    return expected_lines


def assert_results_content():
    expected_lines = expected_results()
    with open('/home/user/results.txt', 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in results.txt, got {len(actual_lines)}"
    for expected, actual in zip(expected_lines, actual_lines):
        assert actual == expected, f"Expected line '{expected}', but got '{actual}'"


def pdb_line(record, serial, x, y, z):
    base = f"{record:<6}{serial:5d}  C   GLY A   1    "
    assert len(base) == 30
    return base + f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n"


def test_files_exist():
    assert os.path.isfile('/home/user/fit_plane.c'), '/home/user/fit_plane.c does not exist'
    assert os.path.isfile('/home/user/process_data.sh'), '/home/user/process_data.sh does not exist'
    assert os.access('/home/user/process_data.sh', os.X_OK), '/home/user/process_data.sh is not executable'
    assert os.path.isfile('/home/user/results.txt'), '/home/user/results.txt does not exist'


def test_results_content():
    assert_results_content()


def test_c_source_compiles_and_handles_unseen_inputs(tmp_path):
    binary = tmp_path / 'fit_plane_from_source'
    subprocess.run(
        ['gcc', '-O2', '/home/user/fit_plane.c', '-o', str(binary), '-lm'],
        check=True, timeout=20
    )
    assert binary.read_bytes().startswith(b'\x7fELF')

    rng = secrets.SystemRandom()
    coords = []
    for _ in range(7):
        coords.append((rng.randint(-6, 6), rng.randint(-6, 6), rng.randint(-8, 8)))

    pdb = tmp_path / 'unseen.pdb'
    with open(pdb, 'w') as f:
        f.write('REMARK    1       9.000   9.000   9.000\n')
        for i, (x, y, z) in enumerate(coords, 1):
            f.write(pdb_line('ATOM' if i % 2 else 'HETATM', i, x, y, z))
        f.write('ATOMX     9  C   GLY A   1       9.000   9.000   9.000\n')

    X, Y, Z = parse_pdb(pdb)
    for alpha, iters, lam in [(0.007, 317, 0.23), (0.013, 89, 0.7)]:
        expected = compute_gd(X, Y, Z, alpha, iters, lam)
        proc = subprocess.run(
            [str(binary), str(pdb), str(alpha), str(iters), str(lam)],
            check=True, text=True, capture_output=True, timeout=10
        )
        actual = proc.stdout.strip()
        assert re.fullmatch(r'w1: -?\d+\.\d{4}, w2: -?\d+\.\d{4}, b: -?\d+\.\d{4}', actual)
        assert actual == f'w1: {expected[0]:.4f}, w2: {expected[1]:.4f}, b: {expected[2]:.4f}'

    assert subprocess.run([str(binary)], capture_output=True, timeout=5).returncode != 0
    assert subprocess.run(
        [str(binary), str(pdb), '0.01', '10', '0.5', 'extra'],
        capture_output=True, timeout=5
    ).returncode != 0


def test_process_script_rebuilds_and_processes_unseen_file():
    rng = secrets.SystemRandom()
    fixture = f"/home/user/pdb_data/verify_{secrets.token_hex(6)}.pdb"
    with open(fixture, 'w') as f:
        for i in range(1, 6):
            x = rng.randint(-4, 5)
            y = rng.randint(-4, 5)
            z = rng.randint(-7, 7)
            f.write(pdb_line('HETATM' if i % 2 else 'ATOM', i, x, y, z))

    for path in ['/home/user/fit_plane', '/home/user/results.txt']:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        ['/home/user/process_data.sh'], cwd='/home/user', check=True,
        text=True, capture_output=True, timeout=30
    )

    assert os.path.isfile('/home/user/fit_plane')
    assert os.access('/home/user/fit_plane', os.X_OK)
    with open('/home/user/fit_plane', 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/fit_plane was not compiled as a native executable'
    assert os.path.isfile('/home/user/results.txt')
    assert_results_content()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
