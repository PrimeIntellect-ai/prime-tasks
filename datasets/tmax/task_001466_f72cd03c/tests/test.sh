#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/validate_plugins.py"
PLAN_PATH = "/home/user/load_plan.json"
RULES_PATH = "/home/user/plugin_rules.txt"
PLUGIN_DIR = "/home/user/plugins"


def run_validator():
    if os.path.exists(PLAN_PATH):
        os.remove(PLAN_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Validator exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def generate_original_plan():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."
    run_validator()


def test_script_exists():
    script_path = "/home/user/validate_plugins.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."


def test_load_plan_exists():
    plan_path = "/home/user/load_plan.json"
    assert os.path.isfile(plan_path), f"Load plan JSON file {plan_path} is missing."


def test_load_plan_content():
    plan_path = "/home/user/load_plan.json"
    try:
        with open(plan_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {plan_path} does not contain valid JSON.")

    expected_data = {
        "libalpha.so": True,
        "libbeta.so": False,
        "libgamma.so": True,
    }

    assert isinstance(data, dict), "Load plan JSON should be a dictionary."
    assert data == expected_data, f"Load plan content is incorrect. Expected {expected_data}, but got {data}."


def build_library(path, elf_class, exported_symbol, token):
    if elf_class == "ELF64":
        source = f"/tmp/{token}.c"
        with open(source, "w") as f:
            f.write(f"void {exported_symbol}(void) {{}}\n")
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", path, source],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    else:
        source = f"/tmp/{token}.s"
        obj = f"/tmp/{token}.o"
        with open(source, "w") as f:
            f.write(
                f".text\n.globl {exported_symbol}\n"
                f".type {exported_symbol}, @function\n"
                f"{exported_symbol}:\n    ret\n"
            )
        subprocess.run(
            ["as", "--32", "-o", obj, source],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            ["ld", "-m", "elf_i386", "-shared", "-o", path, obj],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )


def actual_elf_class(path):
    with open(path, "rb") as f:
        header = f.read(5)
    assert header[:4] == b"\x7fELF", f"Generated test library {path} is not ELF."
    assert header[4] in (1, 2), f"Invalid ELF class byte in {path}."
    return "ELF32" if header[4] == 1 else "ELF64"


def exported_symbols(path):
    result = subprocess.run(
        ["nm", "-D", "--defined-only", path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    symbols = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields:
            symbols.add(fields[-1].split("@", 1)[0])
    return symbols


def test_validator_reacts_to_actual_rules_and_elf_files():
    nonce = uuid.uuid4().hex
    wanted = f"requested_{nonce}"
    decoy = f"decoy_{nonce}"

    # (actual class, expected class, operator, exports requested symbol)
    cases = [
        ("ELF64", "ELF64", "AND", True),
        ("ELF32", "ELF64", "AND", False),
        ("ELF32", "ELF64", "OR", True),
        ("ELF32", "ELF64", "OR", False),
        ("ELF32", "ELF32", "AND", True),
        ("ELF64", "ELF32", "AND", True),
        ("ELF64", "ELF64", "OR", False),
    ]

    specs = []
    for index, (elf_class, expected_class, operator, has_wanted) in enumerate(cases):
        filename = f"libprobe_{nonce}_{index}.so"
        path = os.path.join(PLUGIN_DIR, filename)
        symbol_to_export = wanted if has_wanted else decoy
        build_library(path, elf_class, symbol_to_export, f"{nonce}_{index}")
        specs.append((filename, path, expected_class, operator))

    with open(RULES_PATH, "w") as f:
        for filename, _path, expected_class, operator in specs:
            f.write(f"{filename} : CLASS={expected_class} {operator} SYM={wanted}\n")

    expected = {}
    for filename, path, expected_class, operator in specs:
        class_match = actual_elf_class(path) == expected_class
        has_symbol = wanted in exported_symbols(path)
        expected[filename] = (
            class_match and has_symbol if operator == "AND"
            else class_match or has_symbol
        )

    run_validator()
    assert os.path.isfile(PLAN_PATH), f"Load plan JSON file {PLAN_PATH} is missing after execution."
    try:
        with open(PLAN_PATH, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {PLAN_PATH} does not contain valid JSON after execution.")

    assert isinstance(actual, dict), "Load plan JSON should be a dictionary."
    assert actual == expected, f"Dynamic load plan is incorrect. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
