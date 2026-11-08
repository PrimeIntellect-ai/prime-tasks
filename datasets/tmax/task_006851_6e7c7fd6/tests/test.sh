#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import json
import os
import shutil
import subprocess
import sys

import pytest

PROJECT = "/home/user/wsee"
BUILD = os.path.join(PROJECT, "build")
RESULT = os.path.join(PROJECT, "evaluation_result.txt")


@pytest.fixture(scope="session", autouse=True)
def run_orchestrator_from_clean_state():
    orchestrator = os.path.join(PROJECT, "orchestrator.py")
    assert os.path.isfile(orchestrator), "orchestrator.py is missing."

    shutil.rmtree(BUILD, ignore_errors=True)
    try:
        os.remove(RESULT)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [sys.executable, orchestrator],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        "orchestrator.py failed when run from a clean state:\n" + completed.stdout
    )


def load_compiler():
    path = os.path.join(PROJECT, "compiler.py")
    assert os.path.isfile(path), "compiler.py is missing."
    spec = importlib.util.spec_from_file_location("submitted_wsee_compiler", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "compile_rule", None)), "compile_rule is missing."
    return module


def condition(left, operator, right):
    return {
        "type": "condition",
        "left": left,
        "operator": operator,
        "right": right,
    }


def test_compiler_conditions_and_operators():
    compiler = load_compiler()
    cases = [
        ("req.ip_version == 6", condition("req.ip_version", "==", 6)),
        ("req.payload_size < 731", condition("req.payload_size", "<", 731)),
        ("req.contains_sql > 2", condition("req.contains_sql", ">", 2)),
        ("  req.payload_size   ==   4097  ", condition("req.payload_size", "==", 4097)),
    ]
    for expression, expected in cases:
        encoded = compiler.compile_rule(expression)
        assert isinstance(encoded, str), "compile_rule must return a JSON string."
        assert json.loads(encoded) == expected


def test_compiler_and_is_binary_and_left_associative():
    compiler = load_compiler()
    a = condition("req.ip_version", "==", 4)
    b = condition("req.payload_size", "<", 987)
    c = condition("req.contains_sql", "==", 0)
    expected = {
        "type": "logical",
        "operator": "AND",
        "left": {
            "type": "logical",
            "operator": "AND",
            "left": a,
            "right": b,
        },
        "right": c,
    }
    expression = (
        "req.ip_version == 4 AND req.payload_size < 987 "
        "AND req.contains_sql == 0"
    )
    assert json.loads(compiler.compile_rule(expression)) == expected


def test_orchestrator_contains_required_integration_steps():
    path = os.path.join(PROJECT, "orchestrator.py")
    source = open(path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=path)

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])

    assert "subprocess" in imported, "orchestrator.py must use the subprocess module."
    assert "ctypes" in imported, "orchestrator.py must use ctypes."
    assert "compiler" in imported, "orchestrator.py must import compiler.py."
    assert "ENABLE_STRICT_MODE" in source and "ON" in source
    assert "compile_rule" in source
    assert "evaluate_ast" in source
    assert "req.ip_version == 4 AND req.payload_size < 1000 AND req.contains_sql == 0" in source

    struct_classes = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.ClassDef)
        and any(
            (isinstance(base, ast.Attribute) and base.attr == "Structure")
            or (isinstance(base, ast.Name) and base.id == "Structure")
            for base in node.bases
        )
    ]
    assert struct_classes, "orchestrator.py must define a ctypes.Structure for WebRequest."
    for field in ("ip_version", "payload_size", "contains_sql"):
        assert field in source, f"WebRequest is missing the {field} field."


def test_libwsee_compiled():
    so_path = "/home/user/wsee/build/libwsee.so"
    assert os.path.isfile(so_path), f"Expected compiled shared library at {so_path} does not exist."


def test_strict_security_flag():
    build_dir = "/home/user/wsee/build"
    assert os.path.isdir(build_dir), f"Build directory {build_dir} does not exist."

    found_strict = False
    for root, dirs, files in os.walk(build_dir):
        for file in files:
            # Check makefiles, ninja files, or cmake files for the flag
            if file.endswith(".make") or file == "build.ninja" or file == "CMakeCache.txt" or file == "flags.make":
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                        if "STRICT_SECURITY" in content or "ENABLE_STRICT_MODE" in content:
                            found_strict = True
                            break
                except Exception:
                    pass
        if found_strict:
            break

    assert found_strict, "Could not find -DSTRICT_SECURITY or ENABLE_STRICT_MODE in the CMake build files. The conditional build flag was not properly implemented or passed."


def test_strict_security_macro_is_used_to_compile_wsee_target():
    candidates = []
    for root, _, files in os.walk(BUILD):
        normalized = root.replace("\\", "/")
        if "/CMakeFiles/wsee.dir" in normalized:
            for name in files:
                if name.endswith(".make") or name in ("flags.make", "build.ninja"):
                    candidates.append(os.path.join(root, name))
    build_ninja = os.path.join(BUILD, "build.ninja")
    if os.path.isfile(build_ninja):
        candidates.append(build_ninja)

    contents = []
    for path in candidates:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            contents.append(handle.read())
    assert any("STRICT_SECURITY" in content for content in contents), (
        "The wsee shared-library target was not compiled with STRICT_SECURITY."
    )


def test_shared_library_loads_and_evaluate_ast_runs():
    compiler = load_compiler()
    so_path = os.path.join(BUILD, "libwsee.so")
    library = ctypes.CDLL(so_path)

    class WebRequest(ctypes.Structure):
        _fields_ = [
            ("ip_version", ctypes.c_int),
            ("payload_size", ctypes.c_int),
            ("contains_sql", ctypes.c_int),
        ]

    evaluate = library.evaluate_ast
    evaluate.argtypes = [ctypes.c_char_p, ctypes.POINTER(WebRequest)]
    evaluate.restype = ctypes.c_int

    rule = "req.ip_version == 4 AND req.payload_size < 1000 AND req.contains_sql == 0"
    encoded = compiler.compile_rule(rule).encode("utf-8")
    assert evaluate(encoded, ctypes.byref(WebRequest(4, 800, 0))) == 1
    assert evaluate(encoded, ctypes.byref(WebRequest(4, 1000, 0))) == 0
    assert evaluate(encoded, ctypes.byref(WebRequest(4, 800, 1))) == 0
    assert evaluate(None, ctypes.byref(WebRequest(4, 800, 0))) == -1


def test_evaluation_result():
    result_path = "/home/user/wsee/evaluation_result.txt"
    assert os.path.isfile(result_path), f"Evaluation result file {result_path} is missing. orchestrator.py might not have run or failed."

    with open(result_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "1", f"Expected evaluation_result.txt to contain exactly '1', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
