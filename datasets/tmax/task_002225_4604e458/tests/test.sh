#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
BUILD = f"{HOME}/build_system.py"
FORMULAS = f"{HOME}/formulas.txt"
ARTIFACTS = [
    f"{HOME}/impl.c",
    f"{HOME}/impl.py",
    f"{HOME}/impl_bin",
    f"{HOME}/validation.json",
]


def run_build():
    result = subprocess.run(
        ["python3", BUILD], cwd=HOME, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Running {BUILD} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def run_integer_program(path, x):
    result = subprocess.run(
        [path, str(x)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Running {path} {x} failed with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    try:
        return int(result.stdout.strip())
    except ValueError:
        assert False, f"Output of {path} {x} is not an integer: '{result.stdout.strip()}'"


def load_compute(path):
    module_name = f"generated_impl_{secrets.token_hex(8)}"
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None, f"Cannot import {path}."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "compute"), f"{path} does not define compute."
    assert callable(module.compute), f"compute in {path} is not callable."
    return module.compute


def test_build_system_script_exists():
    path = "/home/user/build_system.py"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_build_system_generates_artifacts_when_executed():
    for path in ARTIFACTS:
        if os.path.lexists(path):
            assert not os.path.isdir(path), f"Expected artifact path {path} is a directory."
            os.unlink(path)
    run_build()
    for path in ARTIFACTS:
        assert os.path.isfile(path), f"Running build_system.py did not generate {path}."


def test_generated_c_file_exists():
    path = "/home/user/impl.c"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_generated_py_file_exists():
    path = "/home/user/impl.py"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_executable_exists():
    path = "/home/user/impl_bin"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert stat.S_ISREG(os.stat(path).st_mode), f"File {path} is not a regular file."


def test_validation_json_correct():
    path = "/home/user/validation.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    expected_data = {
        "ALPHA": 49,
        "BETA": 83,
        "c_results": [35, -7, -37, -49, -37],
        "py_results": [35, -7, -37, -49, -37],
        "match": True
    }

    for key in expected_data:
        assert key in data, f"Key '{key}' missing from validation.json."
        assert data[key] == expected_data[key], f"Value for '{key}' in validation.json is incorrect. Expected {expected_data[key]}, got {data[key]}."


def test_c_executable_functionality():
    path = "/home/user/impl_bin"
    expected_results = [35, -7, -37, -49, -37]

    for i, x in enumerate(range(1, 6)):
        output_val = run_integer_program(path, x)
        assert output_val == expected_results[i], f"Expected {path} {x} to output {expected_results[i]}, got {output_val}."


def test_dynamic_parsing_generation_and_both_implementations():
    with open(FORMULAS, "r") as f:
        original_formulas = f.read()

    rng = secrets.SystemRandom()
    while True:
        a = rng.randint(10, 70)
        b = rng.randint(2, 9)
        c = rng.randint(10, 25)
        d = rng.randint(1, 8)
        multiplier = rng.randint(2, 5)
        offset = rng.randint(4, 30)
        alpha = a + b * (c - d)
        beta = alpha * multiplier - offset
        if (alpha, beta) != (49, 83):
            break

    changed_formulas = (
        f"ALPHA = {a} + {b} * ({c} - {d})\n"
        f"BETA = ALPHA * {multiplier} - {offset}\n"
        "compute(x) = x * x * x - ALPHA * x + BETA\n"
    )

    try:
        with open(FORMULAS, "w") as f:
            f.write(changed_formulas)

        run_build()

        with open(f"{HOME}/impl.c", "r") as f:
            c_source = f.read()
        assert c_source.strip(), "Generated impl.c is empty."
        assert "main" in c_source, "Generated impl.c does not contain a C program entry point."

        with open(f"{HOME}/impl.py", "r") as f:
            py_source = f.read()
        try:
            py_tree = ast.parse(py_source, filename=f"{HOME}/impl.py")
        except SyntaxError as exc:
            assert False, f"Generated impl.py is not valid Python: {exc}"
        assert any(
            isinstance(node, ast.FunctionDef) and node.name == "compute"
            for node in ast.walk(py_tree)
        ), "Generated impl.py does not contain def compute(x)."

        source_binary = "/tmp/impl_compiled_from_generated_source"
        compile_result = subprocess.run(
            ["gcc", f"{HOME}/impl.c", "-o", source_binary],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            "Generated impl.c does not compile independently.\n"
            f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )

        compute = load_compute(f"{HOME}/impl.py")
        xs = [-17, -8, -1, 0, 6, 11, 19]
        while len(xs) < 10:
            candidate = rng.randint(-40, 40)
            if candidate not in xs and candidate not in range(1, 6):
                xs.append(candidate)

        for x in xs:
            expected = x * x * x - alpha * x + beta
            assert run_integer_program(f"{HOME}/impl_bin", x) == expected
            assert run_integer_program(source_binary, x) == expected
            py_value = compute(x)
            assert py_value == expected, f"impl.py compute({x}) returned {py_value}, expected {expected}."

        with open(f"{HOME}/validation.json", "r") as f:
            dynamic_data = json.load(f)
        expected_loop = [x * x * x - alpha * x + beta for x in range(1, 6)]
        expected_dynamic = {
            "ALPHA": alpha,
            "BETA": beta,
            "c_results": expected_loop,
            "py_results": expected_loop,
            "match": True,
        }
        for key, value in expected_dynamic.items():
            assert key in dynamic_data, f"Key '{key}' missing after rebuilding with changed formulas."
            assert dynamic_data[key] == value, (
                f"Dynamic validation value for '{key}' is incorrect. "
                f"Expected {value}, got {dynamic_data[key]}."
            )
    finally:
        with open(FORMULAS, "w") as f:
            f.write(original_formulas)
        run_build()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
