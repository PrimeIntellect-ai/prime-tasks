#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import struct
import subprocess
import textwrap

import pytest

PROJECT = "/home/user/project"
LIB_PATH = os.path.join(PROJECT, "libeval.so")
PROCESSOR_PATH = os.path.join(PROJECT, "processor.py")
DATA_PATH = os.path.join(PROJECT, "data.txt")
LOG_PATH = os.path.join(PROJECT, "output.log")


def run_processor():
    return subprocess.run(
        ["python3", PROCESSOR_PATH],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def read_output():
    with open(LOG_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_makefile_builds_libeval_from_project():
    makefile = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile), f"Makefile {makefile} is missing."
    with open(makefile, "r") as f:
        make_text = f.read()
    assert "src/eval.c" in make_text, "Makefile does not build from src/eval.c."
    assert "libeval.so" in make_text, "Makefile does not define libeval.so as an output."

    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)
    result = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        "Running make in the project failed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LIB_PATH), "make did not create /home/user/project/libeval.so."


def test_libeval_so_exists_and_is_shared_object():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built or does not exist."

    with open(LIB_PATH, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"{LIB_PATH} is not a valid ELF file."
        f.seek(16)
        e_type = struct.unpack("<H", f.read(2))[0]
        assert e_type == 3, f"{LIB_PATH} is not built as a shared object (missing -shared / -fPIC)."

    check = subprocess.run(
        ["python3", "-c", textwrap.dedent(f"""
            import ctypes
            lib = ctypes.CDLL({LIB_PATH!r})
            lib.evaluate.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
            lib.evaluate.restype = ctypes.c_int
            assert lib.evaluate(b'ADD', 19, 23) == 42
            assert lib.evaluate(b'SUB', 7, 12) == -5
            assert lib.evaluate(b'MUL', -6, 9) == -54
            assert lib.evaluate(b'DIV', 50, 2) == 25
            assert lib.evaluate(b'DIV', 50, 0) == 0
        """))],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert check.returncode == 0, (
        "libeval.so could not be loaded or its evaluate symbol behaved incorrectly.\n"
        f"stderr:\n{check.stderr}"
    )


def test_processor_exists_and_declares_ctypes_signature():
    assert os.path.isfile(PROCESSOR_PATH), f"Python processor {PROCESSOR_PATH} is missing."
    with open(PROCESSOR_PATH, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, PROCESSOR_PATH)
    except SyntaxError as exc:
        pytest.fail(f"processor.py is not valid Python: {exc}")

    module_aliases = set()
    type_aliases = {}
    cdll_names = set()
    star_import = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "ctypes":
                    module_aliases.add(alias.asname or "ctypes")
        elif isinstance(node, ast.ImportFrom) and node.module == "ctypes":
            for alias in node.names:
                if alias.name == "*":
                    star_import = True
                else:
                    local = alias.asname or alias.name
                    type_aliases[local] = alias.name
                    if alias.name in ("CDLL", "PyDLL"):
                        cdll_names.add(local)

    assert module_aliases or type_aliases or star_import, "processor.py does not import ctypes."

    def canonical_type(node):
        if isinstance(node, ast.Name):
            if node.id in type_aliases:
                return type_aliases[node.id]
            if star_import:
                return node.id
            return None
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            if node.value.id in module_aliases:
                return node.attr
        return None

    loads_with_ctypes = False
    signatures = {}

    def record_signature(base, attr, value):
        key = ast.dump(base, include_attributes=False)
        entry = signatures.setdefault(key, {})
        if attr == "argtypes" and isinstance(value, (ast.List, ast.Tuple)):
            entry["argtypes"] = [canonical_type(item) for item in value.elts]
        elif attr == "restype":
            entry["restype"] = canonical_type(value)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if (isinstance(node.func.value, ast.Name)
                        and node.func.value.id in module_aliases
                        and node.func.attr in ("CDLL", "PyDLL")):
                    loads_with_ctypes = True
            elif isinstance(node.func, ast.Name) and node.func.id in cdll_names:
                loads_with_ctypes = True

            if (isinstance(node.func, ast.Name) and node.func.id == "setattr"
                    and len(node.args) >= 3 and isinstance(node.args[1], ast.Constant)
                    and node.args[1].value in ("argtypes", "restype")):
                record_signature(node.args[0], node.args[1].value, node.args[2])

        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Attribute) and target.attr in ("argtypes", "restype"):
                    record_signature(target.value, target.attr, node.value)

    assert loads_with_ctypes, "processor.py does not load a library through ctypes.CDLL/PyDLL."
    assert any(
        sig.get("argtypes") == ["c_char_p", "c_int", "c_int"]
        and sig.get("restype") == "c_int"
        for sig in signatures.values()
    ), "processor.py does not set evaluate's argtypes and restype to c_char_p, c_int, c_int -> c_int."


def test_processor_generates_correct_output_for_original_data():
    assert os.path.isfile(DATA_PATH), f"Data file {DATA_PATH} is missing."
    result = run_processor()
    assert result.returncode == 0, (
        "processor.py did not run cleanly.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Output log {LOG_PATH} was not created."

    with open(DATA_PATH, "r") as f:
        data_lines = [line.strip() for line in f if line.strip()]

    expected_output = []
    for i, line in enumerate(data_lines, 1):
        parts = line.split()
        if len(parts) != 3:
            continue
        op, arg1_str, arg2_str = parts
        a = int(arg1_str)
        b = int(arg2_str)
        if op == "ADD":
            res = a + b
        elif op == "SUB":
            res = a - b
        elif op == "MUL":
            res = a * b
        elif op == "DIV":
            res = a // b if b != 0 else 0
        else:
            res = 0
        expected_output.append(f"Line {i}: {op} {a} {b} = {res}")

    actual_output = read_output()
    assert len(actual_output) == len(expected_output), (
        f"Expected {len(expected_output)} lines in output.log, but found {len(actual_output)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_output, expected_output), 1):
        assert actual == expected, f"Mismatch on line {i} of output.log.\nExpected: {expected}\nActual:   {actual}"


def test_processor_really_invokes_evaluate():
    rng = random.SystemRandom()
    salt = rng.randint(10000, 50000)
    probe_source = textwrap.dedent(f"""
        #include <string.h>
        int evaluate(const char* op, int a, int b) {{
            int code = 9;
            if (strcmp(op, "ADD") == 0) code = 1;
            else if (strcmp(op, "SUB") == 0) code = 2;
            else if (strcmp(op, "MUL") == 0) code = 3;
            else if (strcmp(op, "DIV") == 0) code = 4;
            return {salt} + code * 1000 + a * 17 - b * 13;
        }}
    """)
    probe_c = "/tmp/eval_probe.c"
    with open(probe_c, "w") as f:
        f.write(probe_source)
    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", probe_c, "-o", LIB_PATH],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, f"Could not build verifier probe library: {build.stderr}"

    operations = ["ADD", "SUB", "MUL", "DIV", "ADD", "MUL", "SUB", "DIV"]
    rows = []
    for op in operations:
        a = rng.randint(-500, 500)
        b = rng.randint(-500, 500)
        if op == "DIV" and b == 0:
            b = 7
        rows.append((op, a, b))
    with open(DATA_PATH, "w") as f:
        for op, a, b in rows:
            f.write(f"{op} {a} {b}\n")

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = run_processor()
    assert result.returncode == 0, (
        "processor.py failed on verifier-generated input.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "processor.py did not create output.log on generated input."

    codes = {"ADD": 1, "SUB": 2, "MUL": 3, "DIV": 4}
    expected = [
        f"Line {i}: {op} {a} {b} = {salt + codes[op] * 1000 + a * 17 - b * 13}"
        for i, (op, a, b) in enumerate(rows, 1)
    ]
    assert read_output() == expected, (
        "processor.py's output did not reflect the verifier's evaluate implementation; "
        "it must invoke evaluate from libeval.so rather than fabricate results in Python."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
