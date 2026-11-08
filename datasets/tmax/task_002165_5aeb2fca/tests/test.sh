#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import py_compile
import random
import secrets
import subprocess
import sys
import tempfile

import pytest

SANITIZER_PATH = "/home/user/sanitizer.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
WRAPPER_PATH = "/app/wrapper.py"
BINARY_PATH = "/app/matrix_eig_solver.bin"


def run_sanitizer(filepath, timeout=5):
    return subprocess.run(
        [sys.executable, SANITIZER_PATH, filepath],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer script not found at {SANITIZER_PATH}"
    py_compile.compile(SANITIZER_PATH, doraise=True)


def test_sanitizer_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    if not clean_files:
        pytest.fail(f"No JSON files found in clean corpus: {CLEAN_CORPUS_DIR}")

    failed_files = []
    for filepath in clean_files:
        result = run_sanitizer(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0). Offending files: {', '.join(failed_files)}")


def test_sanitizer_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    if not evil_files:
        pytest.fail(f"No JSON files found in evil corpus: {EVIL_CORPUS_DIR}")

    failed_files = []
    for filepath in evil_files:
        result = run_sanitizer(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the sanitizer (exit code != 1). Offending files: {', '.join(failed_files)}")


def test_sanitizer_on_neutral_paths_and_generated_matrices(tmp_path):
    # First copy the visible examples to names and directories containing no labels.
    cases = []
    for source, expected in [
        (os.path.join(CLEAN_CORPUS_DIR, "data1.json"), 0),
        (os.path.join(EVIL_CORPUS_DIR, "data1.json"), 1),
    ]:
        destination = tmp_path / (secrets.token_hex(12) + ".json")
        destination.write_bytes(open(source, "rb").read())
        cases.append((str(destination), expected))

    # The solver flaw is singularity. Build fresh, unpredictable full-rank matrices
    # using strict diagonal dominance, and singular matrices using duplicate rows.
    rng = random.SystemRandom()
    for _ in range(16):
        n = rng.randint(2, 6)
        safe = []
        for i in range(n):
            row = [rng.randint(-7, 7) for _ in range(n)]
            off_sum = sum(abs(row[j]) for j in range(n) if j != i)
            row[i] = off_sum + rng.randint(1, 7)
            safe.append(row)

        unsafe = [row[:] for row in safe]
        unsafe[-1] = unsafe[rng.randrange(0, n - 1)][:]

        for matrix, expected in ((safe, 0), (unsafe, 1)):
            path = tmp_path / (secrets.token_hex(16) + ".json")
            path.write_text(json.dumps(matrix), encoding="utf-8")
            cases.append((str(path), expected))

    rng.shuffle(cases)
    failures = []
    for path, expected in cases:
        result = run_sanitizer(path)
        if result.returncode != expected:
            failures.append((os.path.basename(path), expected, result.returncode, result.stderr.decode(errors="replace")[-200:]))
    assert not failures, f"Sanitizer misclassified generated matrices: {failures[:5]}"


def test_dependencies_resolved_in_user_environment():
    probe = r'''
import importlib.metadata as md
import json
import numpy
import scipy
import pandas
names = ["numpy", "scipy", "pandas"]
print(json.dumps({n: {"version": md.version(n), "location": str(md.distribution(n).locate_file(""))} for n in names}))
'''
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", "-c", probe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Dependencies do not import as user: {result.stderr}"
    info = json.loads(result.stdout.strip().splitlines()[-1])
    for name in ("numpy", "scipy", "pandas"):
        assert name in info
        assert os.path.realpath(info[name]["location"]).startswith("/home/user/"), f"{name} was not installed in the local user environment"

    check = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", "-m", "pip", "check"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert check.returncode == 0, f"Installed dependency set remains inconsistent: {check.stdout}\n{check.stderr}"


def test_wrapper_boundary_and_convergence_repairs():
    assert os.path.isfile(WRAPPER_PATH)
    source = open(WRAPPER_PATH, encoding="utf-8").read()
    compact = "".join(source.split())
    assert "raw_data[:,:-1]" not in compact, "The last-column truncation is still present"
    assert "error-=1e-6" not in compact, "The original non-convergent decrement loop is still present"

    probe = r'''
import importlib.util
import json
import numpy as np
spec = importlib.util.spec_from_file_location("repaired_wrapper", "/app/wrapper.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
raw = np.array([[1.0, 20.0, 300.0], [4.0, 50.0, 600.0], [7.0, 80.0, 900.0]])
out = np.asarray(module.smooth_data(raw))
assert out.shape == raw.shape, (out.shape, raw.shape)
assert np.isfinite(out).all()
print(json.dumps(out.tolist()))
'''
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", "-c", probe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=4,
    )
    assert result.returncode == 0, f"Repaired wrapper failed, timed out, or truncated data: {result.stderr}"


def test_mre_artifact_exists_and_runs(tmp_path):
    candidates = []
    for root in ("/home/user", "/app"):
        for path in glob.glob(root + "/**/*.py", recursive=True):
            if os.path.realpath(path) in (os.path.realpath(SANITIZER_PATH), os.path.realpath(WRAPPER_PATH)):
                continue
            try:
                source = open(path, encoding="utf-8").read()
            except (OSError, UnicodeError):
                continue
            lower = source.lower()
            if "matrix_eig_solver.bin" in source and ("subprocess" in lower or "os.system" in lower or "popen" in lower):
                candidates.append(path)

    assert candidates, "No MRE script that invokes matrix_eig_solver.bin was created"
    sample = tmp_path / (secrets.token_hex(10) + ".json")
    sample.write_text(json.dumps([[1, 1], [1, 1]]), encoding="utf-8")

    runnable = []
    errors = []
    for path in candidates:
        try:
            py_compile.compile(path, doraise=True)
        except Exception as exc:
            errors.append(f"{path}: {exc}")
            continue
        for args in ([], [str(sample)]):
            try:
                result = subprocess.run(
                    [sys.executable, path] + args,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                if result.returncode == 0:
                    runnable.append(path)
                    break
            except subprocess.TimeoutExpired:
                errors.append(f"{path}: timed out")
    assert runnable, f"MRE artifact was not runnable: {errors}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
