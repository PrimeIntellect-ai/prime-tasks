#!/bin/bash
set -e
mkdir -p /logs/verifier
export LD_LIBRARY_PATH="/home/user/url_parser/build:${LD_LIBRARY_PATH:-}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import os
import re
import shutil
import stat
import subprocess
import sys

import pytest

RUN_SH = "/home/user/run.sh"
TEST_PY = "/home/user/test_xss.py"
BUILD_DIR = "/home/user/url_parser/build"
SO_PATH = BUILD_DIR + "/libxss_check.so"
REPORT = "/home/user/report.txt"


def test_00_run_sh_exists_and_executable():
    path = RUN_SH
    assert os.path.isfile(path), f"File {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_01_run_sh_performs_required_steps():
    with open(RUN_SH, "r", encoding="utf-8") as f:
        content = f.read()

    assert "url_parser" in content and "build" in content, "run.sh does not use the required build directory"
    assert re.search(r"(^|[;&|[:space:]])cmake([[:space:]]|$)", content), "run.sh does not invoke CMake"
    assert re.search(r"(^|[;&|[:space:]])make([[:space:]]|$)", content), "run.sh does not invoke make"
    assert "LD_LIBRARY_PATH" in content, "run.sh does not configure LD_LIBRARY_PATH"
    assert TEST_PY in content, "run.sh does not execute /home/user/test_xss.py"
    assert REPORT in content and ">" in content, "run.sh does not redirect test output to report.txt"

    if os.path.lexists(BUILD_DIR):
        if os.path.islink(BUILD_DIR) or not os.path.isdir(BUILD_DIR):
            os.unlink(BUILD_DIR)
        else:
            shutil.rmtree(BUILD_DIR)
    if os.path.lexists(REPORT):
        os.unlink(REPORT)

    result = subprocess.run(
        [RUN_SH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"run.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not built."
    assert os.path.isfile(REPORT), f"File {REPORT} does not exist after running run.sh."


def test_02_test_xss_py_exists_and_content():
    path = TEST_PY
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "import ctypes" in content or "from ctypes import" in content, "ctypes module not imported in test_xss.py"
    assert "hypothesis" in content, "hypothesis module not imported in test_xss.py"
    assert "Payload" in content, "Payload struct not defined in test_xss.py"
    assert "@given" in content, "@given decorator not used in test_xss.py"

    tree = ast.parse(content, filename=path)
    hypothesis_tests = set()
    text_strategy_seen = False

    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for decorator in node.decorator_list:
            if not isinstance(decorator, ast.Call):
                continue
            func = decorator.func
            is_given = (
                isinstance(func, ast.Name) and func.id == "given"
            ) or (
                isinstance(func, ast.Attribute) and func.attr == "given"
            )
            if not is_given:
                continue
            hypothesis_tests.add(node.name)
            for child in ast.walk(decorator):
                if isinstance(child, ast.Call):
                    called = child.func
                    if ((isinstance(called, ast.Name) and called.id == "text") or
                            (isinstance(called, ast.Attribute) and called.attr == "text")):
                        text_strategy_seen = True

    assert hypothesis_tests, "No function is actually decorated with hypothesis.given"
    assert text_strategy_seen, "The @given decorator does not use strategies.text()"

    main_calls_test = False
    for node in tree.body:
        if not isinstance(node, ast.If):
            continue
        names = {n.id for n in ast.walk(node.test) if isinstance(n, ast.Name)}
        strings = {n.value for n in ast.walk(node.test) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
        if "__name__" not in names or "__main__" not in strings:
            continue
        called_names = {
            n.func.id for n in ast.walk(node)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
        }
        if called_names & hypothesis_tests:
            main_calls_test = True
            break
    assert main_calls_test, "The __main__ block does not call the Hypothesis test function"


def _load_submission():
    spec = importlib.util.spec_from_file_location("submitted_test_xss", TEST_PY)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_03_harness_structure_and_behavior():
    module = _load_submission()

    Payload = getattr(module, "Payload", None)
    assert isinstance(Payload, type) and issubclass(Payload, ctypes.Structure), "Payload is not a ctypes.Structure"
    assert getattr(Payload, "_fields_", None) == [
        ("content", ctypes.c_char_p),
        ("length", ctypes.c_int),
        ("has_xss", ctypes.c_int),
    ], "Payload fields do not exactly mirror the C struct"

    cfunc_type = getattr(ctypes, "_CFuncPtr")
    owners = []
    target = None
    for value in vars(module).values():
        if isinstance(value, ctypes.CDLL):
            try:
                candidate = getattr(value, "check_xss")
            except AttributeError:
                continue
            if isinstance(candidate, cfunc_type):
                owners.append(value)
                target = candidate

    if target is None:
        for value in vars(module).values():
            if isinstance(value, cfunc_type) and getattr(value, "__name__", "") == "check_xss":
                target = value
                break

    assert target is not None, "test_xss.py did not load the C check_xss function with ctypes"
    assert target.argtypes == [ctypes.POINTER(Payload)], "check_xss.argtypes must be [ctypes.POINTER(Payload)]"
    assert target.restype is None, "check_xss.restype must be None"

    decorated = [
        value for value in vars(module).values()
        if callable(value) and getattr(value, "is_hypothesis_test", False)
    ]
    assert decorated, "No executable Hypothesis test was defined"
    inner = decorated[0].hypothesis.inner_test

    records = []

    def valid_check(arg):
        payload = ctypes.cast(arg, ctypes.POINTER(Payload)).contents
        raw = ctypes.string_at(payload.content, payload.length) if payload.length else b""
        records.append((raw, payload.length, payload.has_xss))
        payload.has_xss = 0

    saved_globals = {}
    saved_owners = []
    try:
        for name, value in list(vars(module).items()):
            if value is target:
                saved_globals[name] = value
                setattr(module, name, valid_check)
        for owner in owners:
            try:
                current = getattr(owner, "check_xss")
                saved_owners.append((owner, current))
                setattr(owner, "check_xss", valid_check)
            except Exception:
                pass

        samples = ["", "plain text", "<script>", "héllo", "a\x00b"]
        for sample in samples:
            records.clear()
            inner(sample)
            assert records, "The property test did not call check_xss"
            raw, length, initial = records[-1]
            encoded = sample.encode()
            assert raw == encoded, "The generated string was not encoded and placed in Payload.content"
            assert length == len(encoded), "Payload.length is not the encoded byte length"
            assert initial == 0, "Payload.has_xss was not initialized to 0"

        def invalid_check(arg):
            payload = ctypes.cast(arg, ctypes.POINTER(Payload)).contents
            payload.has_xss = 2

        for name in saved_globals:
            setattr(module, name, invalid_check)
        for owner, _ in saved_owners:
            setattr(owner, "check_xss", invalid_check)

        with pytest.raises(AssertionError):
            inner("safe input")
    finally:
        for name, value in saved_globals.items():
            setattr(module, name, value)
        for owner, value in saved_owners:
            setattr(owner, "check_xss", value)


def test_04_shared_library_built():
    # Preserve the original shared-library assertion and fallback behavior.
    if not os.path.exists(SO_PATH):
        os.system(RUN_SH)
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not built."


def test_05_report_txt_valid():
    path = REPORT
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    # Preserve the original report assertions.
    assert "AssertionError" not in content, "report.txt contains AssertionError, indicating a test failure."
    assert "Traceback" not in content, "report.txt contains Traceback, indicating an error."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
