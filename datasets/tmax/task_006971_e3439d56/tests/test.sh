#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

ARTIFACTS = "/home/user/artifacts"
NAMES = ["node", "edge", "vertex", "graph", "tree"]


def test_runner_c_exists():
    assert os.path.isfile("/home/user/artifacts/runner.c"), "runner.c is missing. You must write the C program."


def test_result_log_exists():
    assert os.path.isfile("/home/user/artifacts/result.log"), "result.log is missing. Your program must generate this file."


def test_result_log_content():
    expected_order = "Order: tree, node, graph, edge, vertex"
    expected_state = "Final State: 0xAF250DAF"

    with open("/home/user/artifacts/result.log", "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "result.log must contain at least two lines of output."
    assert lines[0] == expected_order, f"The first line of result.log is incorrect. Expected '{expected_order}', got '{lines[0]}'."
    assert lines[1] == expected_state, f"The second line of result.log is incorrect. Expected '{expected_state}', got '{lines[1]}'."


def _compile_runner():
    output = "/tmp/runner_under_test"
    proc = subprocess.run(
        ["gcc", "-std=c11", os.path.join(ARTIFACTS, "runner.c"), "-o", output, "-ldl"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"runner.c failed to compile:\n{proc.stderr}"
    return output


def _make_operation(kind, value):
    if kind == "xor":
        return f"state ^ UINT32_C(0x{value:08X})", lambda state: state ^ value
    if kind == "add":
        return f"state + UINT32_C(0x{value:08X})", lambda state: (state + value) & 0xFFFFFFFF
    if kind == "sub":
        return f"state - UINT32_C(0x{value:08X})", lambda state: (state - value) & 0xFFFFFFFF
    if kind == "mul":
        value |= 1
        return f"state * UINT32_C(0x{value:08X})", lambda state: (state * value) & 0xFFFFFFFF
    shift = 1 + (value % 31)
    return f"(state << {shift}) | (state >> {32 - shift})", lambda state: ((state << shift) | (state >> (32 - shift))) & 0xFFFFFFFF


def _install_case(case_number):
    rng = random.SystemRandom()
    order = list(NAMES)
    rng.shuffle(order)
    token = secrets.token_hex(12)
    load_log = f"/tmp/plugin_load_{token}.log"
    call_log = f"/tmp/plugin_call_{token}.log"

    for path in (load_log, call_log):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # A dependency chain guarantees that this randomized order is the only valid one.
    for index, name in enumerate(order):
        dependency = "" if index == 0 else order[index - 1] + "\n"
        with open(os.path.join(ARTIFACTS, name + ".deps"), "w") as f:
            f.write(dependency)

    operation_kinds = ["xor", "add", "sub", "mul", "rol"]
    rng.shuffle(operation_kinds)
    expected_state = 0x1337

    for index, name in enumerate(order):
        value = secrets.randbits(32)
        expression, transform = _make_operation(operation_kinds[index], value)
        expected_state = transform(expected_state) & 0xFFFFFFFF
        source = f'''#include <stdint.h>
#include <stdio.h>

__attribute__((constructor)) static void record_load(void) {{
    FILE *f = fopen("{load_log}", "a");
    if (f) {{ fputs("{name}\\n", f); fclose(f); }}
}}

uint32_t process_chunk(uint32_t state) {{
    FILE *f = fopen("{call_log}", "a");
    if (f) {{ fputs("{name}\\n", f); fclose(f); }}
    return {expression};
}}
'''
        source_path = f"/tmp/{name}_{token}.c"
        with open(source_path, "w") as f:
            f.write(source)
        proc = subprocess.run(
            ["gcc", "-shared", "-fPIC", source_path, "-o", os.path.join(ARTIFACTS, "lib" + name + ".so")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert proc.returncode == 0, f"Could not build verifier plugin {name}:\n{proc.stderr}"

    return order, expected_state, load_log, call_log


def _read_events(path):
    assert os.path.isfile(path), f"Expected runtime event log {path} was not created"
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def test_runner_compiles_parses_dependencies_and_executes_plugins():
    executable = _compile_runner()

    # Run independent randomized graphs and implementations so a precomputed log
    # or hard-coded original ordering/state cannot satisfy the verifier.
    for case_number in range(2):
        order, expected_state, load_log, call_log = _install_case(case_number)
        result_path = os.path.join(ARTIFACTS, "result.log")
        try:
            os.unlink(result_path)
        except FileNotFoundError:
            pass

        proc = subprocess.run(
            [executable],
            cwd=ARTIFACTS,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert proc.returncode == 0, f"runner exited with {proc.returncode}:\n{proc.stderr}"
        assert os.path.isfile(result_path), "Executing the compiled runner did not generate result.log"

        with open(result_path) as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 2, f"result.log must contain exactly two non-empty lines, got: {lines!r}"
        assert lines[0] == "Order: " + ", ".join(order), "runner did not derive the unique order from the .deps files"
        match = re.fullmatch(r"Final State: 0x([0-9A-F]+)", lines[1])
        assert match, "Final State must be hexadecimal using uppercase digits"
        assert int(match.group(1), 16) == expected_state, "runner produced the wrong state for the runtime-generated plugins"

        assert _read_events(load_log) == order, "shared libraries were not dynamically loaded in dependency order"
        assert _read_events(call_log) == order, "process_chunk was not executed once for each plugin in dependency order"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
