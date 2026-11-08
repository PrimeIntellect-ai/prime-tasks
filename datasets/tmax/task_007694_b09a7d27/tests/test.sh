#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/calc.py"
OUTPUT_PATH = "/home/user/output.txt"


def collatz_max(limit):
    maximum = 0
    for start in range(1, limit + 1):
        value = start
        steps = 0
        while value != 1:
            value = value // 2 if value % 2 == 0 else 3 * value + 1
            steps += 1
        maximum = max(maximum, steps)
    return maximum


def run_script(argument):
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    return subprocess.run(
        ["python", SCRIPT_PATH, str(argument)],
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_requirements_txt():
    """Retain the original requirements assertion."""
    req_path = "/home/user/requirements.txt"
    assert os.path.isfile(req_path), f"{req_path} does not exist."
    with open(req_path, "r") as f:
        content = f.read().lower()
    assert "pydantic" in content, "requirements.txt does not contain 'pydantic'."


def test_requirements_declares_pydantic_package():
    try:
        from packaging.requirements import Requirement
    except ImportError:
        from pip._vendor.packaging.requirements import Requirement

    found = False
    with open("/home/user/requirements.txt", "r") as req_file:
        for raw_line in req_file:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            try:
                requirement = Requirement(line)
            except Exception:
                continue
            if requirement.name.lower() == "pydantic":
                found = True
                break
    assert found, "requirements.txt must contain an actual pydantic requirement."


def test_calc_is_executable_and_uses_pydantic_model():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), "calc.py is not executable."

    with open(SCRIPT_PATH, "r") as source_file:
        tree = ast.parse(source_file.read(), filename=SCRIPT_PATH)

    module_aliases = set()
    base_model_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pydantic":
                    module_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module and node.module.split(".")[0] == "pydantic":
            if node.name if False else False:
                pass
            for alias in node.names:
                if alias.name == "BaseModel":
                    base_model_aliases.add(alias.asname or alias.name)

    assert module_aliases or base_model_aliases, "calc.py must import pydantic."

    model_names = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.ClassDef):
            continue
        for base in node.bases:
            direct_base = isinstance(base, ast.Name) and base.id in base_model_aliases
            qualified_base = (
                isinstance(base, ast.Attribute)
                and base.attr == "BaseModel"
                and isinstance(base.value, ast.Name)
                and base.value.id in module_aliases
            )
            if direct_base or qualified_base:
                model_names.add(node.name)

    assert model_names, "calc.py must define a Pydantic BaseModel."

    model_used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in model_names:
            model_used = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr in {"model_validate", "parse_obj", "validate"}
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in model_names
        ):
            model_used = True
    assert model_used, "The Pydantic model is defined but never used for validation."


def test_calc_py_validation_error():
    """Retain the original N > 5000 assertions."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    result = subprocess.run(
        ["python", SCRIPT_PATH, "6000"], capture_output=True, text=True
    )
    assert result.returncode == 1, "Script did not exit with code 1 for invalid input."
    assert "Validation Error" in result.stdout.strip() or "Validation Error" in result.stderr.strip(), \
        "Script did not output 'Validation Error' for invalid input."


def test_calc_py_validation_error_zero():
    """Retain the original N < 1 assertions."""
    result = subprocess.run(
        ["python", SCRIPT_PATH, "0"], capture_output=True, text=True
    )
    assert result.returncode == 1, "Script did not exit with code 1 for invalid input."
    assert "Validation Error" in result.stdout.strip() or "Validation Error" in result.stderr.strip(), \
        "Script did not output 'Validation Error' for invalid input."


@pytest.mark.parametrize("arguments", [[], ["abc"], ["1.5"], ["-1"], ["5001"], ["10", "11"]])
def test_invalid_inputs_have_exact_output(arguments):
    result = subprocess.run(
        ["python", SCRIPT_PATH, *arguments],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 1
    assert result.stdout == "Validation Error\n"
    assert result.stderr == ""


def test_calc_py_valid_10():
    """Retain the original N=10 assertions."""
    result = run_script(10)
    assert result.returncode == 0, f"Script failed for N=10 with error: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r") as f:
        output_val = f.read().strip()
    assert output_val == "19", f"Expected output 19 for N=10, got '{output_val}'."


def test_calc_py_valid_1000():
    """Retain the original N=1000 assertions."""
    result = run_script(1000)
    assert result.returncode == 0, f"Script failed for N=1000 with error: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r") as f:
        output_val = f.read().strip()
    assert output_val == "178", f"Expected output 178 for N=1000, got '{output_val}'."


def test_random_valid_inputs_against_derived_answers():
    rng = secrets.SystemRandom()
    candidates = [n for n in range(1, 5001) if n not in {10, 1000}]
    limits = rng.sample(candidates, 12)

    for limit in limits:
        result = run_script(limit)
        assert result.returncode == 0, (
            f"Script failed for N={limit}: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(OUTPUT_PATH), f"output.txt was not created for N={limit}."
        with open(OUTPUT_PATH, "r") as output_file:
            actual = output_file.read().strip()
        expected = str(collatz_max(limit))
        assert actual == expected, f"Expected {expected} for N={limit}, got {actual!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
