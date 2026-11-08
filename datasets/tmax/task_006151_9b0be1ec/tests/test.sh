#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

ORIGINAL_PROTEIN = b'''HEADER    EXTRACELLULAR MATRIX                    01-JAN-20   1XYZ
TITLE     TEST STRUCTURE FOR SPATIAL DOMAIN DECOMPOSITION
ATOM      1  N   GLY A   1      12.000  10.500   5.100  1.00  0.00           N
ATOM      2  CA  GLY A   1      12.500  11.500   6.100  1.00  0.00           C
ATOM      3  C   GLY A   1      13.500  12.500   5.100  1.00  0.00           C
ATOM      4  O   GLY A   1      14.500  12.500   4.100  1.00  0.00           O
ATOM      5  N   ALA A   2      12.000  10.500   5.100  1.00  0.00           N  <- duplicate coords
ATOM      6  CA  ALA A   2      15.500  13.500   7.100  1.00  0.00           C
ATOM      7  C   ALA A   2      13.500  12.500   5.100  1.00  0.00           C  <- duplicate coords
END
'''


def expected_clean_pdb():
    source_path = "/home/user/protein.pdb"
    assert os.path.isfile(source_path), f"Missing file: {source_path}"
    with open(source_path, "rb") as f:
        source = f.read()
    assert source == ORIGINAL_PROTEIN, "protein.pdb was modified"

    seen = set()
    retained = []
    for raw_line in source.splitlines(keepends=True):
        line = raw_line[:-1] if raw_line.endswith(b"\n") else raw_line
        if line.endswith(b"\r"):
            line = line[:-1]

        if line.startswith(b"ATOM  ") or line.startswith(b"HETATM"):
            if len(line) >= 54:
                coord = line[30:54]
                if coord in seen:
                    continue
                seen.add(coord)
        retained.append(raw_line)

    return b"".join(retained)


def test_clean_pdb_exists_and_filtered():
    path = "/home/user/clean.pdb"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "rb") as f:
        actual = f.read()
    expected = expected_clean_pdb()
    assert actual == expected, (
        "clean.pdb must exactly preserve every non-duplicate record and retain "
        "the first ATOM/HETATM record for each coordinate"
    )

    lines = actual.decode("utf-8").splitlines()

    # Retain the original verifier's header/footer assertions.
    assert any(line.startswith("HEADER") for line in lines), "clean.pdb missing HEADER line"
    assert any(line.startswith("TITLE") for line in lines), "clean.pdb missing TITLE line"
    assert any(line.startswith("END") for line in lines), "clean.pdb missing END line"

    coords_seen = set()
    atom_count = 0
    for line in lines:
        if line.startswith("ATOM  ") or line.startswith("HETATM"):
            atom_count += 1
            if len(line) >= 54:
                coord = line[30:54]
                assert coord not in coords_seen, f"Duplicate coordinates found in clean.pdb: {coord}"
                coords_seen.add(coord)

    assert atom_count == 5, f"Expected 5 ATOM lines in clean.pdb, found {atom_count}"


def test_solution_txt_exists_and_correct():
    path = "/home/user/solution.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "rb") as f:
        submitted_output = f.read()

    result = subprocess.run(
        ["go", "run", "/home/user/matrix_solver.go", "/home/user/clean.pdb"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, (
        "matrix_solver.go did not run successfully on clean.pdb:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )

    expected_output = (
        b"Matrix factorization successful.\n"
        b"Domain decomposed into 8x8x8 mesh.\n"
        b"Valid atoms processed: 5\n"
        b"Trace: 15.7079\n"
    )
    assert result.stdout == expected_output, "matrix_solver.go produced unexpected factorization output"
    assert submitted_output == result.stdout, (
        "solution.txt is not the output produced by running matrix_solver.go on clean.pdb"
    )

    content = submitted_output.decode("utf-8")
    # Retain the original verifier's output assertions.
    assert "Matrix factorization successful." in content, "solution.txt missing success message"
    assert "Domain decomposed into 8x8x8 mesh." in content, "solution.txt missing domain decomposition message"
    assert "Valid atoms processed: 5" in content, "solution.txt missing or incorrect valid atoms count"
    assert "Trace: 15.7079" in content, "solution.txt missing or incorrect trace value"

    # Ensure executing the submitted program did not alter either input artifact.
    with open("/home/user/clean.pdb", "rb") as f:
        assert f.read() == expected_clean_pdb(), "matrix_solver.go altered clean.pdb"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
