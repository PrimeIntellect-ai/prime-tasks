#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/simulate_mc.sh'
RESULTS_PATH = '/home/user/results.txt'
TEST_PDB_PATH = '/tmp/test.pdb'
TEST_CASES = []

AWK_ORACLE = r'''
BEGIN {
    minX = 1e9; maxX = -1e9;
    minY = 1e9; maxY = -1e9;
    minZ = 1e9; maxZ = -1e9;
}
/^ATOM  / {
    x = substr($0, 31, 8) + 0;
    y = substr($0, 39, 8) + 0;
    z = substr($0, 47, 8) + 0;

    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;

    xs[NR] = x; ys[NR] = y; zs[NR] = z;
}
END {
    if (maxX == minX) { minX -= 0.1; maxX += 0.1; }
    if (maxY == minY) { minY -= 0.1; maxY += 0.1; }
    if (maxZ == minZ) { minZ -= 0.1; maxZ += 0.1; }

    for (a in xs) {
        x = xs[a]; y = ys[a]; z = zs[a];
        ix = int(5 * (x - minX) / (maxX - minX));
        if (ix == 5) ix = 4;
        iy = int(5 * (y - minY) / (maxY - minY));
        if (iy == 5) iy = 4;
        iz = int(5 * (z - minZ) / (maxZ - minZ));
        if (iz == 5) iz = 4;
        occupied[ix "," iy "," iz] = 1;
    }

    occ_count = 0;
    for (cell in occupied) occ_count++;

    srand(42);
    hits = 0;
    for (n = 0; n < 1000; n++) {
        rx = minX + rand() * (maxX - minX);
        ry = minY + rand() * (maxY - minY);
        rz = minZ + rand() * (maxZ - minZ);

        ix = int(5 * (rx - minX) / (maxX - minX));
        if (ix == 5) ix = 4;
        iy = int(5 * (ry - minY) / (maxY - minY));
        if (iy == 5) iy = 4;
        iz = int(5 * (rz - minZ) / (maxZ - minZ));
        if (iz == 5) iz = 4;

        if ((ix "," iy "," iz) in occupied) hits++;
    }

    printf "Occupied Cells: %d\n", occ_count;
    printf "MC Hit Ratio: %.3f\n", hits / 1000;
}
'''


def atom_line(serial, x, y, z):
    return f'ATOM  {serial:5d}  CA  GLY A{serial:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n'


def write_case(path, coordinates, add_distractors=False):
    with open(path, 'w') as f:
        if add_distractors:
            f.write('REMARK    1 COORDINATES BELOW MUST BE IGNORED\n')
            f.write('HETATM    1  O   HOH A   1     999.000 999.000 999.000\n')
            f.write('ATOM  malformed line not in a coordinate record\n')
        for serial, (x, y, z) in enumerate(coordinates, 1):
            f.write(atom_line(serial, x, y, z))
            if add_distractors and serial % 4 == 0:
                f.write('HETATM    9  C   LIG A   9    -999.000-999.000-999.000\n')


def setup_module(module):
    original = '''ATOM      1  N   MET A   1      27.340  24.430   2.952  1.00 50.00           N  
ATOM      2  CA  MET A   1      26.266  25.413   2.842  1.00 50.00           C  
ATOM      3  C   MET A   1      26.913  26.639   2.231  1.00 50.00           C  
ATOM      4  O   MET A   1      27.886  26.463   1.498  1.00 50.00           O  
ATOM      5  CB  MET A   1      25.112  24.880   2.039  1.00 50.00           C  
'''
    with open(TEST_PDB_PATH, 'w') as f:
        f.write(original)
    TEST_CASES.append(TEST_PDB_PATH)

    rng = secrets.SystemRandom()
    case_dir = tempfile.mkdtemp(prefix='mc_cases_')

    general = []
    for _ in range(31):
        general.append((round(rng.uniform(-40, 55), 3),
                        round(rng.uniform(-25, 70), 3),
                        round(rng.uniform(-60, 30), 3)))
    general.extend([general[2], general[7]])
    path = os.path.join(case_dir, secrets.token_hex(8) + '.pdb')
    write_case(path, general, True)
    TEST_CASES.append(path)

    fixed_x = round(rng.uniform(-15, 15), 3)
    zero_x = [(fixed_x, round(-30 + i * 3.7, 3), round(rng.uniform(-20, 45), 3))
              for i in range(19)]
    path = os.path.join(case_dir, secrets.token_hex(8) + '.pdb')
    write_case(path, zero_x, True)
    TEST_CASES.append(path)

    fixed_y = round(rng.uniform(-12, 12), 3)
    fixed_z = round(rng.uniform(-12, 12), 3)
    zero_yz = [(round(-45 + i * 5.25, 3), fixed_y, fixed_z) for i in range(18)]
    path = os.path.join(case_dir, secrets.token_hex(8) + '.pdb')
    write_case(path, zero_yz, True)
    TEST_CASES.append(path)

    same = (round(rng.uniform(-20, 20), 3),
            round(rng.uniform(-20, 20), 3),
            round(rng.uniform(-20, 20), 3))
    path = os.path.join(case_dir, secrets.token_hex(8) + '.pdb')
    write_case(path, [same] * 7, True)
    TEST_CASES.append(path)

    chosen = rng.sample([(i, j, k) for i in range(5) for j in range(5) for k in range(5)],
                        rng.randint(12, 28))
    structured = [(0.0, 0.0, 0.0), (10.0, 10.0, 10.0)]
    structured.extend(((i + 0.35) * 2, (j + 0.45) * 2, (k + 0.55) * 2)
                      for i, j, k in chosen)
    path = os.path.join(case_dir, secrets.token_hex(8) + '.pdb')
    write_case(path, structured, True)
    TEST_CASES.append(path)


def get_expected_results(pdb_path):
    result = subprocess.run(['awk', AWK_ORACLE, pdb_path], capture_output=True,
                            text=True, check=True, timeout=10)
    return result.stdout.strip()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    st = os.stat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f'{SCRIPT_PATH} is not a regular file.'
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {SCRIPT_PATH} is not executable.'


def test_script_execution_and_output():
    for pdb_path in TEST_CASES:
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)

        result = subprocess.run([SCRIPT_PATH, pdb_path], capture_output=True,
                                text=True, timeout=15)
        assert result.returncode == 0, (
            f'Script failed for {pdb_path} with return code {result.returncode}.\n'
            f'Stderr: {result.stderr}')
        assert os.path.exists(RESULTS_PATH), f'Results file {RESULTS_PATH} was not created.'

        with open(RESULTS_PATH) as f:
            actual_content = f.read().strip()
        expected_content = get_expected_results(pdb_path)

        actual_lines = actual_content.splitlines()
        expected_lines = expected_content.splitlines()
        assert len(actual_lines) == 2, (
            f'Expected exactly 2 lines in {RESULTS_PATH}, got {len(actual_lines)}.')

        actual_occ = actual_lines[0].split(':')[-1].strip()
        expected_occ = expected_lines[0].split(':')[-1].strip()
        assert actual_occ == expected_occ, (
            f'Occupied Cells count mismatch for {pdb_path}. '
            f'Expected {expected_occ}, got {actual_occ}.')

        try:
            actual_ratio = float(actual_lines[1].split(':')[-1].strip())
        except ValueError as exc:
            raise AssertionError(f'Invalid MC Hit Ratio for {pdb_path}: {actual_lines[1]}') from exc
        expected_ratio = float(expected_lines[1].split(':')[-1].strip())
        assert abs(actual_ratio - expected_ratio) < 1e-4, (
            f'MC Hit Ratio mismatch for {pdb_path}. '
            f'Expected {expected_ratio}, got {actual_ratio}.')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
