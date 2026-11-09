#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import shutil
import signal
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

PROJECT = Path("/home/user/project")
RUN_BATCH = PROJECT / "run_batch.sh"
POLY_EVAL = PROJECT / "bin/poly_eval"
PROJECT_LIB = PROJECT / "lib/libmathops.so"
DATA = PROJECT / "data"


def clean_env(extra=None):
    env = os.environ.copy()
    for key in ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_DEBUG"):
        env.pop(key, None)
    if extra:
        env.update(extra)
    return env


def run_batch(env=None):
    return subprocess.run(
        [str(RUN_BATCH)],
        capture_output=True,
        text=True,
        timeout=15,
        env=env or clean_env(),
    )


def replace_data_dir(files):
    backup = PROJECT / (".data-audit-" + uuid.uuid4().hex)
    DATA.rename(backup)
    DATA.mkdir()
    for name, value in files.items():
        (DATA / name).write_text(f"{value}\n")
    return backup


def restore_data_dir(backup):
    if DATA.exists():
        shutil.rmtree(DATA)
    backup.rename(DATA)


def build_probe_library(output):
    source = output.with_suffix(".c")
    source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>

double calculate_poly(double x, double y) {
    const char *marker = getenv("AUDIT_MARKER");
    if (marker) {
        FILE *f = fopen(marker, "a");
        if (f) {
            fprintf(f, "%.17g %.17g\n", x, y);
            fclose(f);
        }
    }
    const char *ret = getenv("AUDIT_RETURN");
    return ret ? strtod(ret, NULL) : -9999.0;
}
''')
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(output), str(source)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def install_probe_library(tmp_path):
    backup = tmp_path / "libmathops.original.so"
    probe = tmp_path / "libmathops.probe.so"
    shutil.copy2(PROJECT_LIB, backup)
    build_probe_library(probe)
    os.replace(probe, PROJECT_LIB)
    return backup


def restore_project_library(backup):
    os.replace(backup, PROJECT_LIB)


def test_results_log():
    """Preserve the original final-log assertions."""
    log_file = "/home/user/project/results.log"
    assert os.path.isfile(log_file), f"Log file missing: {log_file}"

    with open(log_file, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "input1.txt: 10.280000",
        "input 2.txt: 22.280000"
    ]

    for line in expected_lines:
        assert line in content, f"Expected output '{line}' not found in results.log. Is the script fixed and poly_eval correctly linked?"

    result = run_batch()
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == content, "results.log is not the actual current stdout of run_batch.sh"


def test_verify_c_exists_and_content():
    """Preserve the original source-content assertions."""
    verify_c = "/home/user/project/verify.c"
    assert os.path.isfile(verify_c), f"C file missing: {verify_c}"

    with open(verify_c, "r") as f:
        content = f.read()

    assert "dlopen" in content, "verify.c must use dlopen() to dynamically load the library"
    assert "dlsym" in content, "verify.c must use dlsym() to resolve the function"
    assert "assert" in content, "verify.c must use assert() to validate the result"


def test_verify_c_compiles_and_runs():
    """Preserve the original compile-and-run assertions."""
    verify_c = "/home/user/project/verify.c"
    assert os.path.isfile(verify_c), f"C file missing: {verify_c}"

    out_bin = "/tmp/verify_test"
    compile_cmd = ["gcc", "-o", out_bin, verify_c, "-ldl"]
    compile_result = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_result.returncode == 0, f"verify.c failed to compile:\n{compile_result.stderr}"

    run_result = subprocess.run([out_bin], capture_output=True, text=True)
    assert run_result.returncode == 0, f"verify.c failed to run (crashed or assertion failed):\n{run_result.stderr}\n{run_result.stdout}"


def test_poly_eval_is_elf_and_imports_math_function():
    assert POLY_EVAL.is_file(), "poly_eval is missing"
    file_result = subprocess.run(["file", str(POLY_EVAL)], capture_output=True, text=True)
    assert file_result.returncode == 0
    assert "ELF" in file_result.stdout, "poly_eval must remain an ELF executable"

    dyn = subprocess.run(["readelf", "-d", str(POLY_EVAL)], capture_output=True, text=True)
    assert dyn.returncode == 0, dyn.stderr
    assert "libmathops.so" in dyn.stdout, "poly_eval must dynamically depend on libmathops.so"

    symbols = subprocess.run(["readelf", "-Ws", str(POLY_EVAL)], capture_output=True, text=True)
    assert symbols.returncode == 0, symbols.stderr
    assert any(" UND " in line and "calculate_poly" in line for line in symbols.stdout.splitlines()), \
        "poly_eval must import calculate_poly from its math library"


def test_batch_processes_all_runtime_generated_files():
    rng = random.SystemRandom()
    files = {
        "ordinary-" + uuid.uuid4().hex + ".txt": rng.randint(-80, 80) / 8.0,
        "file with spaces " + uuid.uuid4().hex + ".txt": rng.randint(-80, 80) / 8.0,
        "another spaced " + uuid.uuid4().hex + ".txt": rng.randint(-80, 80) / 8.0,
    }
    backup = replace_data_dir(files)
    try:
        result = run_batch()
        assert result.returncode == 0, result.stderr
        expected = sorted(
            f"{name}: {(value * value) + (2.0 * 3.14):.6f}"
            for name, value in files.items()
        )
        actual = sorted(result.stdout.strip().splitlines())
        assert actual == expected, "run_batch.sh did not process every generated filename exactly once"
    finally:
        restore_data_dir(backup)


def test_batch_really_loads_project_library(tmp_path):
    value = random.SystemRandom().randint(9, 90) / 7.0
    name = "link audit " + uuid.uuid4().hex + ".txt"
    marker = tmp_path / "poly-marker"
    backup_data = replace_data_dir({name: value})
    backup_lib = install_probe_library(tmp_path)
    try:
        env = clean_env({
            "AUDIT_MARKER": str(marker),
            "AUDIT_RETURN": "731.25",
        })
        result = run_batch(env)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == f"{name}: 731.250000"
        assert marker.is_file(), "poly_eval did not call calculate_poly from the project library"
        calls = marker.read_text().strip().splitlines()
        assert calls, "project calculate_poly was not called"
        x, y = map(float, calls[-1].split())
        assert math.isclose(x, value, rel_tol=0, abs_tol=1e-12)
        assert math.isclose(y, 2.0, rel_tol=0, abs_tol=1e-12)
    finally:
        restore_project_library(backup_lib)
        restore_data_dir(backup_data)


def test_verify_c_loads_correct_symbol_with_required_arguments_and_asserts(tmp_path):
    verify_c = PROJECT / "verify.c"
    out_bin = tmp_path / "verify-audit"
    compile_result = subprocess.run(
        ["gcc", "-o", str(out_bin), str(verify_c), "-ldl"],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    backup_lib = install_probe_library(tmp_path)
    marker = tmp_path / "verify-marker"
    try:
        def exercise(return_value):
            if marker.exists():
                marker.unlink()
            env = clean_env({
                "AUDIT_MARKER": str(marker),
                "AUDIT_RETURN": str(return_value),
            })
            result = subprocess.run(
                [str(out_bin)], capture_output=True, text=True, timeout=10, env=env
            )
            assert marker.is_file(), "verify.c did not call the project library's calculate_poly"
            calls = marker.read_text().strip().splitlines()
            assert calls, "verify.c made no calculate_poly call"
            for call in calls:
                x, y = map(float, call.split())
                assert x == 5.0 and y == 3.0, "verify.c must call calculate_poly(5.0, 3.0)"
            return result

        positive = exercise(1.0)
        assert positive.returncode == 0, "verify.c rejected a result greater than zero"

        zero = exercise(0.0)
        assert zero.returncode == -signal.SIGABRT, "verify.c must assert-fail when the result is zero"

        negative = exercise(-1.0)
        assert negative.returncode == -signal.SIGABRT, "verify.c must assert-fail when the result is negative"
    finally:
        restore_project_library(backup_lib)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
