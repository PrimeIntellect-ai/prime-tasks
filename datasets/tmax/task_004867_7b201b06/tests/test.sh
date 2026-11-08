#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import random
import re
import shutil
import subprocess
import sys

PROJECT_DIR = "/home/user/project"


def _extension_files():
    suffixes = tuple(importlib.machinery.EXTENSION_SUFFIXES)
    return [
        path for path in glob.glob(os.path.join(PROJECT_DIR, "calc_ext*"))
        if os.path.isfile(path) and path.endswith(suffixes)
    ]


def _exercise_extension():
    rng = random.Random(731942)
    cases = [[], [0], [1, -1], [1000, -1000, 37], list(range(-50, 51))]
    for _ in range(40):
        cases.append([rng.randint(-1000, 1000) for _ in range(rng.randint(0, 200))])

    script = r'''
import importlib.machinery
import json
import os
import sys
sys.path.insert(0, sys.argv[1])
import calc_ext
assert isinstance(calc_ext.__loader__, importlib.machinery.ExtensionFileLoader), calc_ext.__loader__
module_path = os.path.realpath(calc_ext.__file__)
assert os.path.dirname(module_path) == os.path.realpath(sys.argv[1]), module_path
for values in json.loads(sys.argv[2]):
    actual = calc_ext.sum_array(values)
    expected = sum(values)
    assert actual == expected, (values, actual, expected)
'''
    result = subprocess.run(
        [sys.executable, "-c", script, PROJECT_DIR, json.dumps(cases)],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, "calc_ext failed behavioral checks:\n" + result.stdout


def test_extension_built():
    files = os.listdir(PROJECT_DIR)
    so_files = [f for f in files if f.startswith("calc_ext") and f.endswith(".so")]
    assert len(so_files) > 0, "The C-extension was not built in-place (no .so file found in the project directory)."


def test_existing_extension_is_real_and_works():
    extensions = _extension_files()
    assert extensions, "No loadable calc_ext extension artifact was built in-place."
    assert any(open(path, "rb").read(4) == b"\x7fELF" for path in extensions), \
        "The calc_ext artifact is not a real compiled shared object."
    _exercise_extension()


def test_libcalc_c_fixed():
    file_path = os.path.join(PROJECT_DIR, "libcalc.c")
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "i <= len" not in content, "The memory safety bug (i <= len) is still present in libcalc.c."
    assert "i < len" in content or "i<len" in content or "i!=len" in content, "libcalc.c does not seem to have the corrected loop bounds."


def test_setup_py_fixed():
    file_path = os.path.join(PROJECT_DIR, "setup.py")
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "libcalc.c" in content, "setup.py was not updated to include 'libcalc.c' in the sources list."


def test_test_calc_py_has_property_based_tests():
    file_path = os.path.join(PROJECT_DIR, "test_calc.py")
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "@given" in content, "test_calc.py does not contain the '@given' decorator for hypothesis tests."
    assert "hypothesis" in content, "test_calc.py does not seem to import hypothesis."


def test_test_log_txt_passed():
    file_path = os.path.join(PROJECT_DIR, "test_log.txt")
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Tests might not have been run or output not captured."

    with open(file_path, "r") as f:
        content = f.read()

    assert re.search(r"\b1 passed\b", content), "test_log.txt does not indicate that exactly 1 test passed."


def test_clean_rebuild_and_actual_pytest_run():
    for path in glob.glob(os.path.join(PROJECT_DIR, "calc_ext*.so")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    shutil.rmtree(os.path.join(PROJECT_DIR, "build"), ignore_errors=True)

    build = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, "Extension build failed:\n" + build.stdout

    extensions = _extension_files()
    assert extensions, "A clean build did not produce an importable extension file."
    assert any(open(path, "rb").read(4) == b"\x7fELF" for path in extensions), \
        "A clean build did not produce a real ELF shared object."
    _exercise_extension()

    log_path = os.path.join(PROJECT_DIR, "test_log.txt")
    with open(log_path, "w") as log:
        test_run = subprocess.run(
            [sys.executable, "-m", "pytest", "test_calc.py"],
            cwd=PROJECT_DIR,
            text=True,
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    assert test_run.returncode == 0, "The submitted property-based test failed when actually run."
    with open(log_path, "r") as f:
        output = f.read()
    assert re.search(r"\b1 passed\b", output), "The actual pytest run did not report exactly 1 passed test."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
