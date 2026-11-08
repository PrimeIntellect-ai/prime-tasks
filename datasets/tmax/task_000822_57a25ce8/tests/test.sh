#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.metadata
import os
import random
import re
import shutil
import stat
import subprocess
import sys
import tempfile

PROJECT_DIR = "/home/user/project"


def test_success_log_output():
    log_path = os.path.join(PROJECT_DIR, "success.log")
    assert os.path.isfile(log_path), f"File {log_path} is missing. Did you run the app and redirect output?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "Result: 35" in content, f"Expected 'Result: 35' in {log_path}, but got: {content}"


def test_build_artifacts_exist():
    app_path = os.path.join(PROJECT_DIR, "app")
    lib_path = os.path.join(PROJECT_DIR, "libmathops.so")
    assert os.path.isfile(app_path), f"Executable {app_path} is missing. Did build.py run successfully?"
    assert os.path.isfile(lib_path), f"Shared library {lib_path} is missing."


def test_hypothesis_test_file():
    test_path = os.path.join(PROJECT_DIR, "test_semver.py")
    assert os.path.isfile(test_path), f"Test file {test_path} is missing."
    with open(test_path, "r") as f:
        content = f.read()
    assert "hypothesis" in content, "The test file does not seem to import or use 'hypothesis'."
    assert "@given" in content or "given(" in content, "The test file does not seem to use the @given decorator from hypothesis."
    assert "compare_versions" in content, "The test file does not call compare_versions."
    matches = re.findall(r"compare_versions\s*\(", content)
    assert len(matches) >= 1, "Expected compare_versions to be used in the hypothesis test."


def test_sym_emulator_fixed_source():
    sym_path = os.path.join(PROJECT_DIR, "sym_emulator.py")
    assert os.path.isfile(sym_path), f"File {sym_path} is missing."
    with open(sym_path, "r") as f:
        content = f.read()
    assert "STRONG_RESOLVED" in content, "sym_emulator.py doesn't seem to contain STRONG_RESOLVED transitions."
    assert "pass" not in content.split("elif state == 'WEAK_RESOLVED':")[-1].split("elif")[0], "sym_emulator.py still seems to have the missing transition (pass) for WEAK_RESOLVED."


def oracle_compare(v1, v2):
    def parse(v):
        core, sep, prerelease = v.partition("-")
        nums = tuple(int(x) for x in core.split("."))
        return nums, prerelease if sep else None

    n1, p1 = parse(v1)
    n2, p2 = parse(v2)
    if n1 != n2:
        return -1 if n1 < n2 else 1
    if p1 == p2:
        return 0
    if p1 is None:
        return 1
    if p2 is None:
        return -1
    return -1 if p1 < p2 else 1


def test_compare_versions_behavior():
    sys.path.insert(0, PROJECT_DIR)
    try:
        from semver_utils import compare_versions
    finally:
        sys.path.pop(0)

    versions = [
        "0.0.0", "1.2.0", "1.10.0", "2.0.0",
        "1.10.0-alpha", "1.10.0-beta", "1.10.0",
        "10.2.3-alpha", "10.2.3-beta", "10.2.3",
    ]
    rng = random.Random(73129)
    for _ in range(150):
        core = f"{rng.randrange(0, 30)}.{rng.randrange(0, 30)}.{rng.randrange(0, 30)}"
        suffix = rng.choice(["", "-alpha", "-beta"])
        versions.append(core + suffix)

    for v1 in versions:
        for v2 in versions:
            actual = compare_versions(v1, v2)
            assert actual in (-1, 0, 1), f"compare_versions returned invalid value {actual!r}"
            expected = oracle_compare(v1, v2)
            assert actual == expected, f"compare_versions({v1!r}, {v2!r}) returned {actual}, expected {expected}"
            assert actual == -compare_versions(v2, v1), f"Anti-symmetry failed for {v1!r}, {v2!r}"


def test_submitted_hypothesis_property():
    try:
        importlib.metadata.version("hypothesis")
    except importlib.metadata.PackageNotFoundError:
        raise AssertionError("hypothesis is not installed as a Python package")

    test_path = os.path.join(PROJECT_DIR, "test_semver.py")
    normal = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", test_path],
        cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=90,
    )
    assert normal.returncode == 0, "Submitted Hypothesis test did not pass:\n" + normal.stdout

    # A real anti-symmetry property must reject this deliberately non-antisymmetric comparator.
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(test_path, os.path.join(td, "test_semver.py"))
        with open(os.path.join(td, "semver_utils.py"), "w") as f:
            f.write("def compare_versions(v1, v2):\n    return 1\n")
        env = os.environ.copy()
        env["PYTHONPATH"] = td
        mutant = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "test_semver.py"],
            cwd=td, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=90,
        )
        assert mutant.returncode != 0, "Submitted test does not detect a comparator that violates anti-symmetry"


def test_symbol_resolver_behavior():
    sys.path.insert(0, PROJECT_DIR)
    try:
        from sym_emulator import SymbolResolver
    finally:
        sys.path.pop(0)

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("VERSION test\nWEAK target_symbol\nSTRONG target_symbol\n")
        path = f.name
    try:
        result = SymbolResolver().parse_and_resolve(path, "test")
    finally:
        os.unlink(path)
    assert result.get("target_symbol") == "STRONG_RESOLVED", "A weak symbol was not upgraded when a strong definition was encountered"


def test_clean_build_and_real_artifacts():
    app_path = os.path.join(PROJECT_DIR, "app")
    lib_path = os.path.join(PROJECT_DIR, "libmathops.so")
    os.remove(app_path)
    os.remove(lib_path)

    build = subprocess.run(
        [sys.executable, "build.py"], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
    )
    assert build.returncode == 0, "python build.py failed:\n" + build.stdout
    assert os.path.isfile(app_path), "build.py did not create app"
    assert os.path.isfile(lib_path), "build.py did not create libmathops.so"
    assert os.stat(app_path).st_mode & stat.S_IXUSR, "app is not executable"
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app is not a compiled ELF executable"
    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmathops.so is not an ELF shared library"

    library = ctypes.CDLL(lib_path)
    library.advanced_calculate.argtypes = [ctypes.c_int, ctypes.c_int]
    library.advanced_calculate.restype = ctypes.c_int
    assert library.advanced_calculate(5, 7) == 35
    assert library.advanced_calculate(6, 9) == 54

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT_DIR
    run = subprocess.run(
        [app_path], cwd=PROJECT_DIR, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    assert run.returncode == 0, f"Compiled app failed: {run.stderr}"
    assert run.stdout.strip() == "Result: 35", f"Unexpected app output: {run.stdout!r}"

    with open(os.path.join(PROJECT_DIR, "success.log"), "r") as f:
        logged = f.read().strip()
    assert logged == run.stdout.strip(), "success.log is not the final output produced by the application"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
