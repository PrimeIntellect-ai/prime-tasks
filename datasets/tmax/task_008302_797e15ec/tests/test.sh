#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
import tempfile

import numpy as np

HOME = "/home/user"
SOURCE = os.path.join(HOME, "mf.cpp")
EXECUTABLE = os.path.join(HOME, "mf")
MATRIX = os.path.join(HOME, "matrix.txt")
LOSS_FILE = os.path.join(HOME, "final_loss.txt")


def read_loss(path):
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the executable?"
    content = open(path, "r").read().strip()
    try:
        loss = float(content)
    except ValueError:
        raise AssertionError(f"Content of {path} is not a valid float: '{content}'")
    assert math.isfinite(loss), "Final loss is not finite, indicating numerical instability."
    return loss


def expected_loss(A):
    n = 100
    u = np.full(n, 0.1, dtype=np.float64)
    v = np.full(n, 0.1, dtype=np.float64)
    lr = 0.001
    lam = 0.05

    for _ in range(100):
        err = A - u[:, None] * v[None, :]
        grad_u = -2.0 * np.sum(err * v[None, :], axis=1) + 2.0 * lam * u
        grad_v = -2.0 * np.sum(err * u[:, None], axis=0) + 2.0 * lam * v
        u -= lr * grad_u
        v -= lr * grad_v

    err = A - u[:, None] * v[None, :]
    return float(np.sum(err * err) + lam * (np.sum(u * u) + np.sum(v * v)))


def pragma_loop_bodies(source):
    # Remove comments so commented-out pragmas do not count.
    clean = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    clean = re.sub(r"//[^\n]*", "", clean)
    pragma = re.compile(r"(?m)^\s*#pragma\s+omp\s+parallel\s+for(?:\s|$)")
    bodies = []
    for match in pragma.finditer(clean):
        fm = re.search(r"\bfor\s*\(", clean[match.end():])
        if not fm:
            continue
        start = match.end() + fm.start()
        brace = clean.find("{", start)
        if brace < 0:
            continue
        depth = 0
        for pos in range(brace, len(clean)):
            if clean[pos] == "{":
                depth += 1
            elif clean[pos] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append(clean[brace:pos + 1])
                    break
    return bodies


def write_matrix(A):
    np.savetxt(MATRIX, A, fmt="%.8f")
    return np.loadtxt(MATRIX, dtype=np.float64)


def run_and_check(binary, A, label):
    A_on_disk = write_matrix(A)
    if os.path.exists(LOSS_FILE):
        os.remove(LOSS_FILE)

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    result = subprocess.run(
        [binary], cwd=HOME, env=env, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{label} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    actual = read_loss(LOSS_FILE)
    expected = expected_loss(A_on_disk)
    tolerance = 0.0006 + 1e-8 * abs(expected)
    assert abs(actual - expected) <= tolerance, (
        f"{label} produced loss {actual}, but the independently computed "
        f"regularized 100-iteration loss is {expected}."
    )


def main():
    # Preserve the original verifier's final-loss assertions.
    initial_loss = read_loss(LOSS_FILE)
    assert initial_loss < 50000, (
        f"Final loss {initial_loss} is too high. Regularization may be incorrectly implemented."
    )

    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    source = open(SOURCE, "r").read()
    assert "#pragma omp parallel for" in source, (
        "OpenMP pragma '#pragma omp parallel for' not found in mf.cpp."
    )

    # Both gradient outer loops must have active OpenMP pragmas.
    bodies = pragma_loop_bodies(source)
    assert len(bodies) >= 2, "At least two active OpenMP parallel-for pragmas are required."
    assert any(re.search(r"\bgrad_u\s*\[", body) for body in bodies), (
        "The outer grad_u loop is not parallelized with OpenMP."
    )
    assert any(re.search(r"\bgrad_v\s*\[", body) for body in bodies), (
        "The outer grad_v loop is not parallelized with OpenMP."
    )

    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    linked = subprocess.run(["ldd", EXECUTABLE], capture_output=True, text=True)
    assert "omp" in (linked.stdout + linked.stderr).lower(), (
        "Executable does not seem to be linked with OpenMP (libgomp/libomp not found)."
    )

    original_matrix_bytes = open(MATRIX, "rb").read()
    original_loss_bytes = open(LOSS_FILE, "rb").read()
    rebuilt = tempfile.mktemp(prefix="mf_rebuilt_", dir="/tmp")

    try:
        compile_result = subprocess.run(
            ["g++", "-O2", "-fopenmp", SOURCE, "-o", rebuilt],
            cwd=HOME, capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            "mf.cpp does not compile with g++ -fopenmp.\n" + compile_result.stderr
        )

        original_A = np.loadtxt(MATRIX, dtype=np.float64)
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        secret_A = (
            rng.normal(0.0, 0.35, size=(100, 100))
            + np.outer(rng.normal(0.0, 1.8, 100), rng.normal(0.0, 1.3, 100))
        )
        zero_A = np.zeros((100, 100), dtype=np.float64)

        # Exercise both the submitted executable and a fresh build of the submitted source.
        for binary, name in ((EXECUTABLE, "submitted executable"), (rebuilt, "rebuilt mf.cpp")):
            run_and_check(binary, original_A, name + " on the provided dataset")
            run_and_check(binary, secret_A, name + " on a verifier-generated dataset")
            run_and_check(binary, zero_A, name + " on the regularization test dataset")
    finally:
        with open(MATRIX, "wb") as f:
            f.write(original_matrix_bytes)
        with open(LOSS_FILE, "wb") as f:
            f.write(original_loss_bytes)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
