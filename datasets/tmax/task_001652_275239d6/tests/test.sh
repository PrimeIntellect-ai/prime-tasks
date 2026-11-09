#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys

import pytest

PROJECT_DIR = "/home/user/legacy_project"
LOG_FILE = "/home/user/migration_result.log"


@pytest.fixture(scope="session", autouse=True)
def build_extension():
    setup_path = os.path.join(PROJECT_DIR, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py does not exist at {setup_path}."

    shutil.rmtree(os.path.join(PROJECT_DIR, "build"), ignore_errors=True)
    for name in os.listdir(PROJECT_DIR):
        if name.startswith("fastcalc") and any(name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES):
            os.remove(os.path.join(PROJECT_DIR, name))

    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Extension build failed:\n{result.stdout}"

    artifacts = [
        os.path.join(PROJECT_DIR, name)
        for name in os.listdir(PROJECT_DIR)
        if name.startswith("fastcalc")
        and any(name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
    ]
    assert artifacts, "setup.py did not build an in-place fastcalc extension module."
    assert all(os.path.isfile(path) for path in artifacts)


def run_python(code, timeout=30):
    return subprocess.run(
        [sys.executable, "-I", "-c", code],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_setup_py_exists():
    setup_path = os.path.join(PROJECT_DIR, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py does not exist at {setup_path}."


def test_fastcalc_is_importable_extension_and_calculates_metric():
    rng = random.Random(72419)
    cases = [
        [],
        [7.25],
        [1, 2, 3, 4],
        [-8.5, 2.25, 19.75, -3.0],
        [rng.uniform(-10000.0, 10000.0) for _ in range(257)],
    ]
    expected = [0.0 if not values else math.fsum(values) / len(values) for values in cases]

    code = f'''\
import importlib.machinery
import json
import os
import sys
sys.path.insert(0, {PROJECT_DIR!r})
import fastcalc
assert isinstance(fastcalc.__loader__, importlib.machinery.ExtensionFileLoader)
assert os.path.realpath(fastcalc.__file__).startswith(os.path.realpath({PROJECT_DIR!r}) + os.sep)
cases = {cases!r}
before = [list(v) for v in cases]
results = [fastcalc.calculate_metric(v) for v in cases]
assert cases == before
print(json.dumps(results))
'''
    result = run_python(code)
    assert result.returncode == 0, f"Import or calculate_metric failed:\n{result.stderr}"
    actual = json.loads(result.stdout)
    assert len(actual) == len(expected)
    for got, want in zip(actual, expected):
        assert isinstance(got, (int, float))
        assert math.isclose(got, want, rel_tol=1e-12, abs_tol=1e-12), (got, want)


def test_calculate_metric_repeated_calls_do_not_leak_allocation():
    # Set the address-space limit after creating the input. An implementation that
    # leaks its size*sizeof(double) work buffer on every call exhausts this budget.
    code = f'''\
import os
import resource
import sys
sys.path.insert(0, {PROJECT_DIR!r})
import fastcalc
data = [float(i) for i in range(300000)]
page = os.sysconf("SC_PAGE_SIZE")
with open("/proc/self/statm", "r") as f:
    current_vmem = int(f.read().split()[0]) * page
resource.setrlimit(resource.RLIMIT_AS, (current_vmem + 128 * 1024 * 1024,) * 2)
expected = (len(data) - 1) / 2.0
for _ in range(80):
    value = fastcalc.calculate_metric(data)
    if abs(value - expected) > 1e-9:
        raise AssertionError((value, expected))
print("ok")
'''
    result = run_python(code, timeout=45)
    assert result.returncode == 0, (
        "calculate_metric failed under repeated calls; its temporary allocation "
        f"may be leaked or accessed unsafely.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert result.stdout.strip() == "ok"


def test_migration_result_log():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    with open(LOG_FILE, 'r') as f:
        content = f.read().strip()
    assert content == "Computed Metric: 5.5", f"Expected log content to be 'Computed Metric: 5.5', but got '{content}'."

    result = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "process.py")],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"process.py failed:\n{result.stderr}"
    assert result.stdout == "Computed Metric: 5.5\n", f"Unexpected process.py output: {result.stdout!r}"
    with open(LOG_FILE, "r") as f:
        logged = f.read()
    assert logged == result.stdout, "migration_result.log is not the exact output generated by process.py."


def test_fastcalc_c_fixed():
    c_file = os.path.join(PROJECT_DIR, "fastcalc.c")
    assert os.path.isfile(c_file), f"{c_file} does not exist."

    with open(c_file, 'r') as f:
        content = f.read()

    # Check Python 3 initialization
    assert "Py_InitModule" not in content, "fastcalc.c still contains deprecated Py_InitModule."
    assert "PyModuleDef" in content, "fastcalc.c must contain PyModuleDef for Python 3 initialization."

    # Check memory safety fixes
    assert "i <= size" not in content, "fastcalc.c still contains the off-by-one bug (i <= size)."
    assert "i < size" in content, "fastcalc.c should use 'i < size' for the loop bounds."
    assert "free(" in content, "fastcalc.c must free the allocated memory to prevent memory leaks."


def test_process_py_fixed():
    py_file = os.path.join(PROJECT_DIR, "process.py")
    assert os.path.isfile(py_file), f"{py_file} does not exist."

    with open(py_file, 'r') as f:
        content = f.read()

    assert "xrange" not in content, "process.py still contains 'xrange' which is Python 2 specific."
    assert "range" in content, "process.py should use 'range' instead of 'xrange'."

    # Check for print function vs statement
    assert re.search(r'print\s*\(', content), "process.py must use the Python 3 print() function."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
