#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

EXPECTED_DATASET = ["ACGT", "ACCA", "TGCA", "TGGT"]


def get_seqs():
    seqs_path = "/home/user/data/seqs.txt"
    assert os.path.isfile(seqs_path), f"File {seqs_path} is missing."
    with open(seqs_path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def compute_expected_cov(seqs):
    n = len(seqs)
    mat = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            score = 0.0
            for k in range(min(len(seqs[i]), len(seqs[j]))):
                if seqs[i][k] == seqs[j][k]:
                    score += 1.0
            if i == j:
                score += 10.0
            mat[i][j] = score
    return mat


def compute_cholesky(A):
    n = len(A)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                val = A[i][i] - s
                assert val > 0, "Matrix is not positive definite"
                L[i][j] = math.sqrt(val)
            else:
                L[i][j] = (A[i][j] - s) / L[j][j]
    return L


def compute_integral(seq):
    mapping = {"A": 1, "C": 2, "G": 3, "T": 4}
    vals = [mapping.get(c, 0) for c in seq]
    if len(vals) <= 1:
        return 0.0
    return sum(0.5 * (vals[i] + vals[i + 1]) for i in range(len(vals) - 1))


def test_input_dataset_unchanged_and_nonempty():
    assert get_seqs() == EXPECTED_DATASET, "/home/user/data/seqs.txt was modified"


def test_executable_compiled():
    exe_path = "/home/user/bin/seq_cov"
    assert os.path.isfile(exe_path), f"Executable {exe_path} not found. Did you compile it?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "seq_cov must be a compiled ELF executable"


def test_cov_txt():
    cov_path = "/home/user/output/cov.txt"
    assert os.path.isfile(cov_path), f"Output file {cov_path} not found."
    expected_mat = compute_expected_cov(get_seqs())
    with open(cov_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_mat), f"Expected {len(expected_mat)} rows in cov.txt, got {len(lines)}"
    for i, line in enumerate(lines):
        vals = [float(x) for x in line.split()]
        assert len(vals) == len(expected_mat[i]), f"Expected {len(expected_mat[i])} columns in row {i+1}, got {len(vals)}"
        for j, val in enumerate(vals):
            assert math.isclose(val, expected_mat[i][j], abs_tol=1e-3), f"Mismatch at ({i}, {j}): expected {expected_mat[i][j]}, got {val}"


def test_cholesky_output():
    l_path = "/home/user/output/L_matrix.txt"
    assert os.path.isfile(l_path), f"Output file {l_path} not found."
    expected_L = compute_cholesky(compute_expected_cov(get_seqs()))
    with open(l_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_L), f"Expected {len(expected_L)} rows in L_matrix.txt, got {len(lines)}"
    for i, line in enumerate(lines):
        parts = line.split()
        assert len(parts) == len(expected_L[i]), f"Expected {len(expected_L[i])} columns in row {i+1}, got {len(parts)}"
        for j, part in enumerate(parts):
            assert "." in part and len(part.split(".")[1]) == 4, f"Value {part} not formatted to 4 decimal places."
            val = float(part)
            assert math.isclose(val, expected_L[i][j], abs_tol=1e-3), f"Mismatch at ({i}, {j}): expected {expected_L[i][j]:.4f}, got {val}"


def test_integrals_output():
    int_path = "/home/user/output/integrals.txt"
    assert os.path.isfile(int_path), f"Output file {int_path} not found."
    expected_integrals = [compute_integral(s) for s in get_seqs()]
    with open(int_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_integrals), f"Expected {len(expected_integrals)} lines in integrals.txt, got {len(lines)}"
    for i, line in enumerate(lines):
        assert "." in line and len(line.split(".")[1]) == 1, f"Value {line} not formatted to 1 decimal place."
        val = float(line)
        assert math.isclose(val, expected_integrals[i], abs_tol=1e-3), f"Mismatch at sequence {i+1}: expected {expected_integrals[i]:.1f}, got {val}"


def test_scripts_exist():
    awk_script = "/home/user/scripts/cholesky.awk"
    bash_script = "/home/user/scripts/integrate.sh"
    assert os.path.isfile(awk_script), f"AWK script {awk_script} not found."
    assert os.path.isfile(bash_script), f"Bash script {bash_script} not found."


def test_seq_cov_executes_on_unseen_input():
    alphabet = "ACGT"
    seqs = ["".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(8) + 1))
            for _ in range(secrets.randbelow(5) + 3)]
    expected = compute_expected_cov(seqs)
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("\n".join(seqs) + "\n")
        input_path = f.name
    try:
        proc = subprocess.run(
            ["/home/user/bin/seq_cov", input_path],
            text=True, capture_output=True, timeout=10
        )
    finally:
        os.unlink(input_path)
    assert proc.returncode == 0, f"seq_cov failed: {proc.stderr}"
    expected_text = "\n".join(" ".join(f"{x:.4f}" for x in row) for row in expected) + "\n"
    assert proc.stdout == expected_text, "seq_cov produced incorrect output on an unseen sequence dataset"


def test_cholesky_awk_executes_on_unseen_matrices():
    script = "/home/user/scripts/cholesky.awk"
    for _ in range(2):
        n = secrets.randbelow(4) + 2
        source_L = [[0.0] * n for _ in range(n)]
        for i in range(n):
            for j in range(i + 1):
                source_L[i][j] = float(secrets.randbelow(5) + 2) if i == j else float(secrets.randbelow(7) - 3)
        A = [[sum(source_L[i][k] * source_L[j][k] for k in range(n)) for j in range(n)] for i in range(n)]
        matrix_text = "\n".join(" ".join(str(x) for x in row) for row in A) + "\n"
        expected = compute_cholesky(A)
        proc = subprocess.run(
            ["gawk", "-f", script], input=matrix_text,
            text=True, capture_output=True, timeout=10
        )
        assert proc.returncode == 0, f"cholesky.awk failed: {proc.stderr}"
        lines = proc.stdout.rstrip("\n").splitlines()
        assert len(lines) == n
        for i, line in enumerate(lines):
            assert re.fullmatch(r"-?\d+\.\d{4}( -?\d+\.\d{4})*", line), f"Incorrect formatting: {line!r}"
            parts = line.split(" ")
            assert len(parts) == n
            for j, part in enumerate(parts):
                assert math.isclose(float(part), expected[i][j], abs_tol=1e-3), f"Dynamic Cholesky mismatch at ({i}, {j})"


def test_integrate_script_executes_on_unseen_sequences():
    seq_path = "/home/user/data/seqs.txt"
    output_path = "/home/user/output/integrals.txt"
    with open(seq_path, "rb") as f:
        old_seqs = f.read()
    old_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            old_output = f.read()

    alphabet = "ACGT"
    seqs = ["".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10) + 1))
            for _ in range(secrets.randbelow(5) + 3)]
    expected = [f"{compute_integral(s):.1f}" for s in seqs]
    try:
        with open(seq_path, "w") as f:
            f.write("\n".join(seqs) + "\n")
        if os.path.exists(output_path):
            os.unlink(output_path)
        proc = subprocess.run(
            ["bash", "/home/user/scripts/integrate.sh"],
            cwd="/home/user", text=True, capture_output=True, timeout=10
        )
        assert proc.returncode == 0, f"integrate.sh failed: {proc.stderr}"
        if proc.stdout.strip():
            actual = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        else:
            assert os.path.isfile(output_path), "integrate.sh produced neither stdout nor integrals.txt"
            with open(output_path, "r") as f:
                actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, "integrate.sh produced incorrect integrals on an unseen sequence dataset"
    finally:
        with open(seq_path, "wb") as f:
            f.write(old_seqs)
        if old_output is None:
            if os.path.exists(output_path):
                os.unlink(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
