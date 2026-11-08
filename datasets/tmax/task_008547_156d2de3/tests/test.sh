#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

SOURCE_FILE = "/home/user/generate_config.c"
EXECUTABLE = "/home/user/generate_config"
HEADER_FILE = "/home/user/build_config.h"
SCHEMA_FILE = "/home/user/schema_v2.txt"
CONSTRAINTS_FILE = "/home/user/constraints.txt"

ORIGINAL_SCHEMA = """API_LEVEL=33
MIN_API=24
RAM_MB=4096
IS_PRO_BUILD=1
CPU_CORES=8
"""

ORIGINAL_CONSTRAINTS = """FEATURE_PRO_UI = IS_PRO_BUILD * FEATURE_ADVANCED
FEATURE_CAMERA_X = API_LEVEL > 30
FEATURE_ADVANCED = FEATURE_CAMERA_X + FEATURE_HEAVY_PROCESSING
FEATURE_HEAVY_PROCESSING = RAM_MB > 2048
HAS_MULTI_CORE = CPU_CORES > 1
LEGACY_SUPPORT = MIN_API < 21
FINAL_SCORE = FEATURE_PRO_UI + HAS_MULTI_CORE
"""


def run_generator():
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Generator exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def compile_and_prepare():
    assert os.path.isfile(SOURCE_FILE), f"Missing C source file: {SOURCE_FILE}"
    assert os.path.isfile(EXECUTABLE), f"Missing compiled executable: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled executable is not an ELF binary: {EXECUTABLE}"

    saved = {}
    for path in (SCHEMA_FILE, CONSTRAINTS_FILE, HEADER_FILE):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", SOURCE_FILE, "-o", EXECUTABLE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, (
            f"Failed to compile {SOURCE_FILE}. "
            f"stdout={compile_result.stdout!r}, stderr={compile_result.stderr!r}"
        )
        assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

        with open(SCHEMA_FILE, "w") as f:
            f.write(ORIGINAL_SCHEMA)
        with open(CONSTRAINTS_FILE, "w") as f:
            f.write(ORIGINAL_CONSTRAINTS)
        if os.path.exists(HEADER_FILE):
            os.remove(HEADER_FILE)
        run_generator()
        yield
    finally:
        for path, contents in saved.items():
            if contents is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)


def test_build_config_exists():
    assert os.path.isfile(HEADER_FILE), f"Missing generated header file: {HEADER_FILE}"


def test_build_config_contents_and_sorting():
    with open(HEADER_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    defines = []
    for line in lines:
        parts = line.split()
        assert len(parts) >= 3, f"Invalid line format in {HEADER_FILE}: '{line}'"
        assert parts[0] == "#define", f"Line does not start with #define: '{line}'"
        var_name = parts[1]
        try:
            value = int(parts[2])
        except ValueError:
            pytest.fail(f"Value for {var_name} is not an integer: '{parts[2]}'")
        defines.append((var_name, value))

    var_names = [d[0] for d in defines]
    sorted_var_names = sorted(var_names)
    assert var_names == sorted_var_names, "The #define directives are not sorted alphabetically by variable name."

    expected_values = {
        "API_LEVEL": 33,
        "CPU_CORES": 8,
        "FEATURE_ADVANCED": 2,
        "FEATURE_CAMERA_X": 1,
        "FEATURE_HEAVY_PROCESSING": 1,
        "FEATURE_PRO_UI": 2,
        "FINAL_SCORE": 3,
        "HAS_MULTI_CORE": 1,
        "IS_PRO_BUILD": 1,
        "LEGACY_SUPPORT": 0,
        "MIN_API": 24,
        "RAM_MB": 4096,
    }

    actual_values = dict(defines)
    for key, expected_val in expected_values.items():
        assert key in actual_values, f"Missing variable in {HEADER_FILE}: {key}"
        assert actual_values[key] == expected_val, f"Incorrect value for {key}. Expected {expected_val}, got {actual_values[key]}"

    for key in actual_values:
        assert key in expected_values, f"Unexpected variable in {HEADER_FILE}: {key}"


def derive_expected(schema_text, constraints_text):
    values = {}
    for line in schema_text.splitlines():
        line = line.strip()
        if line:
            name, value = line.split("=", 1)
            values[name.strip()] = int(value.strip())

    rules = {}
    for line in constraints_text.splitlines():
        line = line.strip()
        if line:
            target, expression = line.split("=", 1)
            op1, operator, op2 = expression.split()
            rules[target.strip()] = (op1, operator, op2)

    visiting = set()

    def resolve(token):
        try:
            return int(token)
        except ValueError:
            pass
        if token in values:
            return values[token]
        assert token in rules, f"Unknown variable in verifier test data: {token}"
        assert token not in visiting, "Cycle in verifier test data"
        visiting.add(token)
        left_name, operator, right_name = rules[token]
        left = resolve(left_name)
        right = resolve(right_name)
        if operator == "+":
            result = left + right
        elif operator == "*":
            result = left * right
        elif operator == ">":
            result = int(left > right)
        elif operator == "<":
            result = int(left < right)
        else:
            raise AssertionError(f"Unexpected operator: {operator}")
        visiting.remove(token)
        values[token] = result
        return result

    for target in rules:
        resolve(target)
    return values


@pytest.mark.parametrize(
    "schema_text,constraints_text",
    [
        (
            "ZETA=7\nALPHA=2\nMID=5\n",
            "OUT = LATER * 3\n"
            "GT = ZETA > MID\n"
            "LATER = ALPHA + MID\n"
            "LT = 4 < LATER\n"
            "MIX = OUT + GT\n"
            "ZERO = 0 * ZETA\n",
        ),
        (
            "BASE_X=3\nBASE_ZERO=0\n",
            "FINAL = CHECK * INVERSE\n"
            "CHECK = FORWARD < 20\n"
            "FORWARD = PRODUCT + 9\n"
            "PRODUCT = START * 4\n"
            "START = BASE_X + 2\n"
            "INVERSE = 100 > FORWARD\n"
            "FALSE_FLAG = BASE_ZERO > 1\n",
        ),
    ],
)
def test_generator_on_varied_inputs(schema_text, constraints_text):
    expected = derive_expected(schema_text, constraints_text)
    with open(SCHEMA_FILE, "w") as f:
        f.write(schema_text)
    with open(CONSTRAINTS_FILE, "w") as f:
        f.write(constraints_text)
    if os.path.exists(HEADER_FILE):
        os.remove(HEADER_FILE)

    run_generator()
    assert os.path.isfile(HEADER_FILE), "Generator did not create build_config.h"

    with open(HEADER_FILE, "r") as f:
        actual_lines = f.readlines()
    expected_lines = [f"#define {name} {expected[name]}\n" for name in sorted(expected)]
    assert actual_lines == expected_lines, (
        "Generated header did not exactly match the values, variables, formatting, "
        "and alphabetical order required for the supplied inputs."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
