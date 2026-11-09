#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import filecmp
import json
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

SRC_DIR = "/home/user/src"
SOURCE = os.path.join(SRC_DIR, "rpn.c")
MAKEFILE = os.path.join(SRC_DIR, "Makefile")
AGENT = os.path.join(SRC_DIR, "rpn_calc")
ORACLE = "/app/rpn_oracle"
SCRIPT = "/home/user/test.sh"


def generate_rpn(rng):
    while True:
        num_ops = rng.randint(1, 15)
        tokens = []
        stack = []
        ops_left = num_ops
        operands_left = num_ops + 1
        valid = True

        while ops_left > 0 or operands_left > 0:
            choices = []
            if operands_left > 0:
                choices.append("push")
            if ops_left > 0 and len(stack) >= 2:
                choices.append("op")
            if not choices:
                valid = False
                break

            if rng.choice(choices) == "push":
                value = rng.randint(-1000, 1000)
                tokens.append(str(value))
                stack.append(value)
                operands_left -= 1
            else:
                op = rng.choice(["+", "-", "*", "/"])
                b = stack.pop()
                a = stack.pop()
                if op == "/":
                    if b == 0:
                        valid = False
                        break
                    result = abs(a) // abs(b)
                    if (a < 0) != (b < 0):
                        result = -result
                elif op == "+":
                    result = a + b
                elif op == "-":
                    result = a - b
                else:
                    result = a * b

                if not (-1000000000 <= result <= 1000000000):
                    valid = False
                    break
                stack.append(result)
                tokens.append(op)
                ops_left -= 1

        if valid and len(stack) == 1:
            return " ".join(tokens), stack[0]


def valid_rpn(expr):
    depth = 0
    values = []
    for token in expr.split():
        if token in {"+", "-", "*", "/"}:
            if depth < 2:
                return False
            b = values.pop()
            a = values.pop()
            if token == "/" and b == 0:
                return False
            if token == "+":
                value = a + b
            elif token == "-":
                value = a - b
            elif token == "*":
                value = a * b
            else:
                value = abs(a) // abs(b)
                if (a < 0) != (b < 0):
                    value = -value
            values.append(value)
            depth -= 1
        else:
            if not re.fullmatch(r"[+-]?\d+", token):
                return False
            value = int(token)
            if not (-2147483648 <= value <= 2147483647):
                return False
            values.append(value)
            depth += 1
    return depth == 1


def run_program(path, expr):
    return subprocess.run([path, expr], capture_output=True, text=True, timeout=5)


def test_01_files_exist_and_build_from_source():
    assert os.path.isfile(SOURCE), "rpn.c is missing."
    assert os.path.isfile(MAKEFILE), "Makefile is missing."
    assert os.path.exists(AGENT), "rpn_calc executable was not built."
    assert os.access(AGENT, os.X_OK), "rpn_calc is not executable."
    assert os.path.isfile(SCRIPT), "test.sh script is missing."
    assert os.access(SCRIPT, os.X_OK), "test.sh is not executable."

    os.unlink(AGENT)
    built = subprocess.run(["make"], cwd=SRC_DIR, capture_output=True, text=True, timeout=30)
    assert built.returncode == 0, "make failed:\n%s\n%s" % (built.stdout, built.stderr)
    assert os.path.isfile(AGENT), "make did not create rpn_calc."
    assert os.access(AGENT, os.X_OK), "make did not create an executable rpn_calc."
    assert not filecmp.cmp(AGENT, ORACLE, shallow=False), "rpn_calc is a byte-for-byte copy of the oracle."

    direct = "/tmp/rpn_source_build"
    compiled = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", direct],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, "rpn.c does not compile independently:\n%s" % compiled.stderr
    assert os.access(direct, os.X_OK)


def test_02_original_fuzz_equivalence_and_derived_answers():
    assert os.path.exists(ORACLE), "Oracle missing."
    assert os.path.exists(AGENT), "Agent binary missing."
    rng = random.Random(42)
    cases = [generate_rpn(rng) for _ in range(500)]

    for expr, expected in cases:
        oracle_proc = run_program(ORACLE, expr)
        agent_proc = run_program(AGENT, expr)
        assert oracle_proc.returncode == agent_proc.returncode, (
            "Return code mismatch on input: %r\nOracle: %s\nAgent: %s"
            % (expr, oracle_proc.returncode, agent_proc.returncode)
        )
        if oracle_proc.returncode == 0:
            assert oracle_proc.stdout.strip() == agent_proc.stdout.strip(), (
                "Output mismatch on input: %r\nOracle: %s\nAgent: %s"
                % (expr, oracle_proc.stdout.strip(), agent_proc.stdout.strip())
            )
            assert agent_proc.stdout.strip() == str(expected), (
                "Incorrect output on input %r: expected %s, got %s"
                % (expr, expected, agent_proc.stdout.strip())
            )


def test_03_repaired_source_works_without_oracle():
    direct = "/tmp/rpn_source_build"
    assert os.access(direct, os.X_OK)
    hidden = "/app/.rpn_oracle.hidden_by_verifier"
    assert not os.path.exists(hidden)
    os.rename(ORACLE, hidden)
    try:
        rng = random.Random(91723)
        for _ in range(200):
            expr, expected = generate_rpn(rng)
            for program in (AGENT, direct):
                proc = run_program(program, expr)
                assert proc.returncode == 0, "%s failed on %r" % (program, expr)
                assert proc.stdout.strip() == str(expected), (
                    "%s produced %r for %r; expected %s"
                    % (program, proc.stdout.strip(), expr, expected)
                )
    finally:
        os.rename(hidden, ORACLE)


def install_wrapper(path, real_path, log_path, role):
    wrapper = """#!/usr/bin/env python3
import json, os, sys
with open(%r, 'a') as f:
    f.write(json.dumps([%r, sys.argv[1:]]) + '\\n')
os.execv(%r, [%r] + sys.argv[1:])
""" % (log_path, role, real_path, real_path)
    with open(path, "w") as f:
        f.write(wrapper)
    os.chmod(path, 0o755)


def run_orchestration_once(log_path):
    open(log_path, "w").close()
    proc = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=60)
    assert proc.returncode == 0, "test.sh exited unsuccessfully:\n%s\n%s" % (proc.stdout, proc.stderr)
    assert re.search(r"(?m)^PASS$", proc.stdout), "test.sh did not print PASS."
    assert not re.search(r"(?m)^FAIL$", proc.stdout), "test.sh printed FAIL."

    records = []
    with open(log_path) as f:
        for line in f:
            records.append(json.loads(line))

    by_role = {"agent": [], "oracle": []}
    for role, args in records:
        assert role in by_role
        assert len(args) == 1, "%s must receive each expression as one argument" % role
        assert valid_rpn(args[0]), "test.sh generated invalid RPN: %r" % args[0]
        by_role[role].append(args[0])

    assert len(by_role["agent"]) >= 5, "test.sh ran rpn_calc fewer than 5 times."
    assert len(by_role["oracle"]) >= 5, "test.sh ran the oracle fewer than 5 times."
    assert collections.Counter(by_role["agent"]) == collections.Counter(by_role["oracle"]), (
        "test.sh did not run both programs on the same expressions."
    )
    return by_role["agent"]


def test_04_test_script_really_orchestrates_random_comparisons():
    calc_real = AGENT + ".verifier-real"
    oracle_real = ORACLE + ".verifier-real"
    log_path = "/tmp/rpn_orchestration_calls.jsonl"
    assert not os.path.exists(calc_real) and not os.path.exists(oracle_real)
    os.rename(AGENT, calc_real)
    os.rename(ORACLE, oracle_real)
    try:
        install_wrapper(AGENT, calc_real, log_path, "agent")
        install_wrapper(ORACLE, oracle_real, log_path, "oracle")
        first = run_orchestration_once(log_path)
        second = run_orchestration_once(log_path)
        assert first != second, "test.sh reused a fixed expression list instead of generating random expressions."
    finally:
        if os.path.lexists(AGENT):
            os.unlink(AGENT)
        if os.path.lexists(ORACLE):
            os.unlink(ORACLE)
        os.rename(calc_real, AGENT)
        os.rename(oracle_real, ORACLE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
