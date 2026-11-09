#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import secrets
import shutil
import subprocess
from fractions import Fraction

import pytest

BASE_DIR = "/home/user/vector_api"


def expected_dot(v1, v2):
    p1 = v1.split("]", 1)[-1].strip().split()
    p2 = v2.split("]", 1)[-1].strip().split()
    total = sum((Fraction(a) * Fraction(b) for a, b in zip(p1, p2)), Fraction(0))
    return f"{total.numerator}/{total.denominator}"


def make_cases(count=5):
    cases = {}
    for i in range(count):
        size = 2 + secrets.randbelow(4)
        left = []
        right = []
        for j in range(size):
            n1 = -(1 + secrets.randbelow(30)) if j == 0 else secrets.randbelow(61) - 30
            n2 = secrets.randbelow(61) - 30
            d1 = 1 + secrets.randbelow(12)
            d2 = 1 + secrets.randbelow(12)
            left.append(f"{n1}/{d1}")
            right.append(f"{n2}/{d2}")
        case_id = f"hidden_{i}_{secrets.token_hex(5)}"
        cases[case_id] = {
            "v1": f"[{size}] " + " ".join(left),
            "v2": f"[{size}] " + " ".join(right),
        }
    return cases


def run_integration(script):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BASE_DIR + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    return subprocess.run(
        ["python3", script],
        cwd=BASE_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def test_c_engine_patched():
    c_file = os.path.join(BASE_DIR, "vector_math.c")
    assert os.path.isfile(c_file), f"File {c_file} is missing."

    with open(c_file, "r") as f:
        content = f.read()

    assert "%d/%u" in content, "The C engine vector_math.c does not appear to be patched. Missing '%d/%u' in sscanf."
    assert "%u/%u" not in content, "The C engine vector_math.c still contains the buggy '%u/%u' sscanf format."


def test_shared_library_built():
    so_file = os.path.join(BASE_DIR, "libvector.so")
    assert os.path.isfile(so_file), f"Shared library {so_file} was not built."
    with open(so_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{so_file} is not an ELF shared-library artifact."


def test_integration_script_exists():
    py_file = os.path.join(BASE_DIR, "test_integration.py")
    assert os.path.isfile(py_file), f"Integration script {py_file} is missing."
    with open(py_file, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"Integration script is not valid Python: {exc}")
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "Integration script does not import ctypes."


def test_results_json_correct():
    test_cases_file = os.path.join(BASE_DIR, "test_cases.json")
    results_file = os.path.join(BASE_DIR, "test_results.json")

    assert os.path.isfile(test_cases_file), f"Test cases file {test_cases_file} is missing."
    assert os.path.isfile(results_file), f"Results file {results_file} is missing."

    with open(test_cases_file, "r") as f:
        test_cases = json.load(f)

    expected_results = {}
    for case_id, data in test_cases.items():
        v1_str = data["v1"].split("]", 1)[-1].strip()
        v2_str = data["v2"].split("]", 1)[-1].strip()

        v1_parts = v1_str.split()
        v2_parts = v2_str.split()

        total = Fraction(0)
        for p1, p2 in zip(v1_parts, v2_parts):
            total += Fraction(p1) * Fraction(p2)

        expected_results[case_id] = f"{total.numerator}/{total.denominator}"

    with open(results_file, "r") as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Results file {results_file} is not valid JSON.")

    assert actual_results == expected_results, f"Results in {results_file} do not match the expected math output. Expected: {expected_results}, Actual: {actual_results}"


def test_shared_library_executes_hidden_cases():
    so_file = os.path.join(BASE_DIR, "libvector.so")
    try:
        library = ctypes.CDLL(so_file)
    except OSError as exc:
        pytest.fail(f"Could not load {so_file} as a shared library: {exc}")

    assert hasattr(library, "dot_product"), "Shared library does not export dot_product."
    dot_product = library.dot_product
    dot_product.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    dot_product.restype = ctypes.c_char_p

    for data in make_cases(6).values():
        answer = dot_product(data["v1"].encode(), data["v2"].encode())
        assert answer is not None, "dot_product returned a null pointer."
        actual = answer.decode("utf-8")
        expected = expected_dot(data["v1"], data["v2"])
        assert actual == expected, (
            f"dot_product returned {actual!r} for {data}, expected {expected!r}."
        )


def test_integration_script_runs_and_calls_library(tmp_path):
    script = os.path.join(BASE_DIR, "test_integration.py")
    cases_path = os.path.join(BASE_DIR, "test_cases.json")
    results_path = os.path.join(BASE_DIR, "test_results.json")
    library_path = os.path.join(BASE_DIR, "libvector.so")

    with open(cases_path, "rb") as f:
        original_cases = f.read()
    original_results = None
    if os.path.isfile(results_path):
        with open(results_path, "rb") as f:
            original_results = f.read()

    library_backup = tmp_path / "submitted_libvector.so"
    shutil.copy2(library_path, library_backup)

    try:
        hidden_cases = make_cases(5)
        hidden_expected = {
            case_id: expected_dot(data["v1"], data["v2"])
            for case_id, data in hidden_cases.items()
        }
        with open(cases_path, "w") as f:
            json.dump(hidden_cases, f)
        if os.path.exists(results_path):
            os.unlink(results_path)

        completed = run_integration(script)
        assert completed.returncode == 0, (
            "Integration script failed on hidden inputs.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(results_path), "Integration script did not create test_results.json."
        with open(results_path, "r") as f:
            actual = json.load(f)
        assert actual == hidden_expected, (
            f"Integration script produced incorrect hidden results. Expected {hidden_expected}, got {actual}."
        )

        shim_cases = {}
        markers = {}
        for i in range(3):
            case_id = f"probe_{i}_{secrets.token_hex(5)}"
            v1 = f"[2] -{2 + i}/3 {5 + i}/7"
            v2 = f"[2] {11 + i}/5 -{13 + i}/9"
            shim_cases[case_id] = {"v1": v1, "v2": v2}
            markers[case_id] = f"ctypes_probe_{secrets.token_hex(16)}"

        clauses = []
        for case_id, data in shim_cases.items():
            v1_literal = json.dumps(data["v1"])
            v2_literal = json.dumps(data["v2"])
            marker_literal = json.dumps(markers[case_id])
            clauses.append(
                f"if (strcmp(v1, {v1_literal}) == 0 && strcmp(v2, {v2_literal}) == 0) "
                f"return strdup({marker_literal});"
            )

        shim_source = tmp_path / "vector_probe.c"
        shim_library = tmp_path / "libvector_probe.so"
        shim_source.write_text(
            "#include <string.h>\n#include <stdlib.h>\n"
            "char* dot_product(const char* v1, const char* v2) {\n"
            + "\n".join(clauses)
            + '\nreturn strdup("unexpected_probe_input");\n}\n'
        )
        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", str(shim_library), str(shim_source)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"Verifier probe library failed to compile: {compile_result.stderr}"

        replacement = os.path.join(BASE_DIR, f".libvector_probe_{secrets.token_hex(6)}.so")
        shutil.copy2(shim_library, replacement)
        os.replace(replacement, library_path)

        with open(cases_path, "w") as f:
            json.dump(shim_cases, f)
        if os.path.exists(results_path):
            os.unlink(results_path)

        completed = run_integration(script)
        assert completed.returncode == 0, (
            "Integration script failed while exercising the ctypes boundary.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(results_path), "Integration script did not create results from the probe library."
        with open(results_path, "r") as f:
            probe_actual = json.load(f)
        assert probe_actual == markers, (
            "Integration script did not obtain its result strings from libvector.so via the integration boundary. "
            f"Expected probe values {markers}, got {probe_actual}."
        )
    finally:
        with open(cases_path, "wb") as f:
            f.write(original_cases)
        if original_results is None:
            if os.path.exists(results_path):
                os.unlink(results_path)
        else:
            with open(results_path, "wb") as f:
                f.write(original_results)
        restore_path = os.path.join(BASE_DIR, f".libvector_restore_{secrets.token_hex(6)}.so")
        shutil.copy2(library_backup, restore_path)
        os.replace(restore_path, library_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
