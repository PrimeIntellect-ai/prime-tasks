#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import subprocess
import tempfile
import pytest

ROOT = "/home/user/pr-review"


def test_passed_txt_content():
    path = "/home/user/pr-review/passed.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the Python script?"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        "5.5+4.5 == 10.0 >= 9.0",
        "7.1+3.2 == 10.3 >= 10.0"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, "The contents of passed.txt do not match the expected filtered results. Check your C library logic and Python ABI setup."


def test_evaluate_c_memory_leak_fixed():
    path = "/home/user/pr-review/evaluate.c"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    # Check if expr_copy is freed
    assert re.search(r"free\s*\(\s*expr_copy\s*\)", content), "Memory leak not fixed in evaluate.c. You need to free the allocated string before returning."


def test_check_constraints_py_abi_fixed():
    path = "/home/user/pr-review/check_constraints.py"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    assert "restype" in content and "c_double" in content, "ABI mismatch not fixed in check_constraints.py. You need to set the correct restype."
    assert "argtypes" in content, "ABI mismatch not fixed in check_constraints.py. You need to set the correct argtypes."


def _attr_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def test_abi_assignments_are_real_code():
    path = os.path.join(ROOT, "check_constraints.py")
    tree = ast.parse(open(path, encoding="utf-8").read(), filename=path)
    restype_ok = False
    argtypes_ok = False
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        for target in targets:
            name = _attr_name(target)
            if name == "lib.eval_expr.restype" and _attr_name(value) == "ctypes.c_double":
                restype_ok = True
            if name == "lib.eval_expr.argtypes" and isinstance(value, (ast.List, ast.Tuple)):
                argtypes_ok = len(value.elts) == 1 and _attr_name(value.elts[0]) == "ctypes.c_char_p"
    assert restype_ok, "lib.eval_expr.restype must be assigned ctypes.c_double in executable code"
    assert argtypes_ok, "lib.eval_expr.argtypes must be assigned [ctypes.c_char_p] in executable code"


def test_script_and_submitted_library_on_independent_input(tmp_path):
    library = os.path.join(ROOT, "libeval.so")
    assert os.path.isfile(library), "libeval.so is missing"
    data = tmp_path / "independent_data.txt"
    rows = [
        ("123.125+0.625", 123.7),
        ("2.25+3.5", 5.8),
        ("0.125+0.25", 0.3),
        ("41.75+0.5", 50.0),
    ]
    data.write_text("".join(f"{expr},{threshold}\n" for expr, threshold in rows), encoding="utf-8")
    proc = subprocess.run(
        ["python3", os.path.join(ROOT, "check_constraints.py"), str(data)],
        text=True, capture_output=True, timeout=20
    )
    assert proc.returncode == 0, proc.stderr
    expected = []
    for expr, threshold in rows:
        left, right = expr.split("+", 1)
        result = float(left) + float(right)
        if result >= threshold:
            expected.append(f"{expr} == {result} >= {threshold}")
    actual = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    assert actual == expected, "The Python script did not correctly call libeval.so on independent input"


def test_built_library_and_source_are_leak_free(tmp_path):
    source = os.path.join(ROOT, "evaluate.c")
    submitted = os.path.join(ROOT, "libeval.so")
    rebuilt = tmp_path / "libeval_from_source.so"
    build = subprocess.run(
        ["gcc", "-shared", "-o", str(rebuilt), "-fPIC", source],
        text=True, capture_output=True, timeout=20
    )
    assert build.returncode == 0, build.stderr

    harness_c = tmp_path / "leak_harness.c"
    harness = tmp_path / "leak_harness"
    harness_c.write_text(r'''#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
typedef double (*eval_fn)(const char *);
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (!h) { fprintf(stderr, "%s\n", dlerror()); return 3; }
    eval_fn fn = (eval_fn)dlsym(h, "eval_expr");
    if (!fn) return 4;
    for (int i = 0; i < 2000; ++i) {
        double a = fn("123.125+0.625");
        double b = fn("not_an_addition");
        if (a < 123.749999 || a > 123.750001 || b != 0.0) return 5;
    }
    if (dlclose(h) != 0) return 6;
    return 0;
}
''', encoding="utf-8")
    compile_harness = subprocess.run(
        ["gcc", "-o", str(harness), str(harness_c), "-ldl"],
        text=True, capture_output=True, timeout=20
    )
    assert compile_harness.returncode == 0, compile_harness.stderr

    for library in (submitted, str(rebuilt)):
        proc = subprocess.run([
            "valgrind", "--quiet", "--leak-check=full",
            "--show-leak-kinds=definite", "--errors-for-leak-kinds=definite",
            "--error-exitcode=99", str(harness), library
        ], text=True, capture_output=True, timeout=60)
        assert proc.returncode == 0, f"Library {library} is incorrect or leaks memory:\n{proc.stdout}\n{proc.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
