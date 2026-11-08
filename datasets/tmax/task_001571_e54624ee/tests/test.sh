#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import random
import runpy
import subprocess
import sys

SO_FILE = "/home/user/libmatheval.so"
PY_FILE = "/home/user/test_integration.py"
OUT_FILE = "/home/user/math_output.txt"
EXPRESSION = b"100 5 / 4 2 * + 2 /"


def test_shared_library_exists():
    """Test that the compiled Go shared library exists."""
    assert os.path.isfile(SO_FILE), f"Expected shared library {SO_FILE} is missing. Did you compile the Go code?"
    with open(SO_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_FILE} is not an ELF shared library."


def test_integration_script_exists_and_valid():
    """Test that the Python integration script exists and imports ctypes."""
    assert os.path.isfile(PY_FILE), f"Expected Python script {PY_FILE} is missing."

    with open(PY_FILE, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        assert False, f"Python script {PY_FILE} contains a syntax error: {e}"

    imports_ctypes = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "ctypes":
                    imports_ctypes = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == "ctypes":
                imports_ctypes = True

    assert imports_ctypes, f"Python script {PY_FILE} does not import 'ctypes'."


def _evaluate_library(expression):
    helper = r'''
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.EvaluateRPN
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_double
print(repr(fn(sys.argv[2].encode("ascii"))))
'''
    result = subprocess.run(
        [sys.executable, "-c", helper, SO_FILE, expression],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        "The shared library could not be loaded or EvaluateRPN could not be called:\n"
        + result.stderr
    )
    return float(result.stdout.strip())


def test_shared_library_exports_working_evaluator():
    """Load the library and exercise its exported C ABI on derived test cases."""
    rng = random.Random(90421)
    cases = []
    for _ in range(8):
        a = rng.randint(-30, 30)
        b = rng.randint(1, 20)
        c = rng.randint(1, 12)
        choice = rng.randrange(4)
        if choice == 0:
            cases.append((f"{a} {b} + {c} *", (a + b) * c))
        elif choice == 1:
            cases.append((f"{a} {b} - {c} /", (a - b) / c))
        elif choice == 2:
            cases.append((f"{a} {b} * {c} +", a * b + c))
        else:
            cases.append((f"{a} {b} {c} + /", a / (b + c)))

    for expression, expected in cases:
        actual = _evaluate_library(expression)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"EvaluateRPN({expression!r}) returned {actual}, expected {expected}."
        )


def test_integration_script_ctypes_contract(monkeypatch):
    """Run the script against an instrumented ctypes loader and verify its ABI use."""
    loaded_paths = []
    calls = []

    class FakeFunction:
        def __init__(self):
            self.argtypes = None
            self.restype = None

        def __call__(self, *args):
            calls.append((args, self.argtypes, self.restype))
            return 14.0

    class FakeLibrary:
        def __init__(self):
            self.EvaluateRPN = FakeFunction()

        def __getitem__(self, name):
            if name == "EvaluateRPN":
                return self.EvaluateRPN
            raise AttributeError(name)

    def fake_loader(path, *args, **kwargs):
        loaded_paths.append(os.fsdecode(path))
        return FakeLibrary()

    monkeypatch.setattr(ctypes, "CDLL", fake_loader)
    monkeypatch.setattr(ctypes.cdll, "LoadLibrary", fake_loader)
    monkeypatch.setattr(ctypes.cdll, "_dlltype", fake_loader)

    try:
        runpy.run_path(PY_FILE, run_name="__main__")
    except SystemExit as exc:
        assert exc.code in (None, 0), f"Integration script exited with status {exc.code}."

    assert SO_FILE in loaded_paths, f"The script did not load {SO_FILE} through ctypes."

    valid_call = False
    for args, argtypes, restype in calls:
        if len(args) != 1:
            continue
        value = args[0]
        if isinstance(value, ctypes.c_char_p):
            value = value.value
        try:
            configured_args = list(argtypes) if argtypes is not None else None
        except TypeError:
            configured_args = None
        if (
            value == EXPRESSION
            and configured_args == [ctypes.c_char_p]
            and restype is ctypes.c_double
        ):
            valid_call = True
            break

    assert valid_call, (
        "The script must configure EvaluateRPN.argtypes as [ctypes.c_char_p], "
        "restype as ctypes.c_double, and call it with the required expression."
    )


def test_execute_integration_script():
    """Execute the submitted script with the real shared library."""
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)
    result = subprocess.run(
        [sys.executable, PY_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Integration script failed with status {result.returncode}:\n{result.stderr}"
    )
    assert os.path.isfile(OUT_FILE), (
        f"Expected output file {OUT_FILE} is missing. Did you run your Python script?"
    )


def test_math_output():
    """Test that the output file exists and contains the correct result."""
    assert os.path.isfile(OUT_FILE), f"Expected output file {OUT_FILE} is missing. Did you run your Python script?"

    with open(OUT_FILE, "r") as f:
        content = f.read().strip()

    assert content == "14.0", f"Expected output to be '14.0', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
