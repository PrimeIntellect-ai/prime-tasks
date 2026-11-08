#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import subprocess
import sys
import uuid

SCRIPT_PATH = "/home/user/generate_fixture.py"
FIXTURE_PATH = "/home/user/test_fixture.py"
TRACE_PATH = "/home/user/asm_trace.s"
TARGETS_PATH = "/home/user/build_targets.json"


def test_generate_fixture_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."


def test_test_fixture_file_exists():
    assert os.path.isfile(FIXTURE_PATH), f"Expected output file {FIXTURE_PATH} does not exist."


def expected_targets(trace_text, targets):
    requirements = []
    conflicts = []

    for line in trace_text.splitlines():
        match = re.search(r";\s*(REQUIRE|CONFLICT)\s+(.+?)\s*$", line)
        if not match:
            continue
        kind, body = match.groups()
        parts = body.split()
        if kind == "REQUIRE":
            if len(parts) == 3:
                requirements.append((parts[0], parts[1], parts[2]))
            else:
                assert len(parts) == 2
                requirements.append((parts[0], None, parts[1]))
        else:
            assert len(parts) == 2
            conflicts.append((parts[0], parts[1]))

    def satisfies(target):
        for key, operator, raw_value in requirements:
            actual = target[key]
            if operator is None:
                if isinstance(actual, list):
                    ok = raw_value in actual
                else:
                    ok = str(actual) == raw_value
            else:
                expected = int(raw_value) if isinstance(actual, int) else raw_value
                operations = {
                    ">=": lambda a, b: a >= b,
                    "<=": lambda a, b: a <= b,
                    ">": lambda a, b: a > b,
                    "<": lambda a, b: a < b,
                    "==": lambda a, b: a == b,
                    "!=": lambda a, b: a != b,
                }
                assert operator in operations
                ok = operations[operator](actual, expected)
            if not ok:
                return False

        for key, raw_value in conflicts:
            actual = target[key]
            triggered = raw_value in actual if isinstance(actual, list) else str(actual) == raw_value
            if triggered:
                return False
        return True

    return sorted(target["name"] for target in targets if satisfies(target))


def run_and_check(trace_text, targets):
    with open(TRACE_PATH, "w", encoding="utf-8") as f:
        f.write(trace_text)
    with open(TARGETS_PATH, "w", encoding="utf-8") as f:
        json.dump(targets, f)

    if os.path.exists(FIXTURE_PATH):
        os.remove(FIXTURE_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"generate_fixture.py failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(FIXTURE_PATH), "generate_fixture.py did not create test_fixture.py"

    module_name = "generated_fixture_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(module_name, FIXTURE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        raise AssertionError(f"Failed to import {FIXTURE_PATH}: {exc}") from exc
    finally:
        sys.modules.pop(module_name, None)

    assert hasattr(module, "valid_targets"), "The function 'valid_targets' is missing from test_fixture.py"
    fixture_function = module.valid_targets
    assert hasattr(fixture_function, "_pytestfixturefunction"), (
        "valid_targets must be decorated with @pytest.fixture"
    )
    wrapped_function = getattr(fixture_function, "__wrapped__", None)
    assert callable(wrapped_function), "Could not inspect the decorated fixture function"

    try:
        actual = wrapped_function()
    except Exception as exc:
        raise AssertionError(f"Evaluating valid_targets raised an exception: {exc}") from exc

    expected = expected_targets(trace_text, targets)
    assert actual == expected, f"Expected valid_targets to return {expected}, but got {actual}"
    assert actual == sorted(actual), "Target names are not sorted alphabetically"


def test_test_fixture_content():
    assert os.path.isfile(FIXTURE_PATH), "Fixture file missing. Run generate_fixture.py before verification."

    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        original_trace = f.read()
    with open(TARGETS_PATH, "r", encoding="utf-8") as f:
        original_targets_text = f.read()
    original_targets = json.loads(original_targets_text)

    suffix = uuid.uuid4().hex[:10]
    case_one_trace = """.text
_start:
    ; REQUIRE MEM >= 3000
    ; REQUIRE CPU_EXT NEON
    ; CONFLICT CPU_EXT MIPS
"""
    case_one_targets = [
        {"name": "Alpha_" + suffix, "MEM": 3000, "CPU_EXT": ["NEON", "ARM64"]},
        {"name": "Beta_" + suffix, "MEM": 2999, "CPU_EXT": ["NEON", "ARM64"]},
        {"name": "Gamma_" + suffix, "MEM": 7000, "CPU_EXT": ["NEON", "MIPS"]},
        {"name": "Delta_" + suffix, "MEM": 8000, "CPU_EXT": ["ARM64"]},
    ]

    case_two_trace = """.text
_start:
    ; REQUIRE MEM >= 1024
    ; REQUIRE CPU_EXT ARM64
    ; CONFLICT CPU_EXT VFPV3
"""
    case_two_targets = [
        {"name": "Zulu_" + suffix, "MEM": 4096, "CPU_EXT": ["ARM64", "NEON"]},
        {"name": "Able_" + suffix, "MEM": 1024, "CPU_EXT": ["ARM64"]},
        {"name": "Low_" + suffix, "MEM": 512, "CPU_EXT": ["ARM64"]},
        {"name": "Conflict_" + suffix, "MEM": 8192, "CPU_EXT": ["ARM64", "VFPV3"]},
    ]

    try:
        run_and_check(original_trace, original_targets)
        run_and_check(case_one_trace, case_one_targets)
        run_and_check(case_two_trace, case_two_targets)
    finally:
        with open(TRACE_PATH, "w", encoding="utf-8") as f:
            f.write(original_trace)
        with open(TARGETS_PATH, "w", encoding="utf-8") as f:
            f.write(original_targets_text)
        subprocess.run(
            [sys.executable, SCRIPT_PATH],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
            check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
