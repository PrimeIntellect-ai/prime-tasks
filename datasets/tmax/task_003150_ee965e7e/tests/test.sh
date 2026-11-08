#!/bin/bash
mkdir -p /logs/verifier
rm -f /home/user/zz_verifier_test.go
trap 'rm -f /home/user/zz_verifier_test.go' EXIT

cat <<'PY_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import shutil
import subprocess

import pytest

HOME = "/home/user"
CLIB = "/home/user/clib"
ENV = os.environ.copy()
ENV["LD_LIBRARY_PATH"] = CLIB + (":" + ENV["LD_LIBRARY_PATH"] if ENV.get("LD_LIBRARY_PATH") else "")


def run(cmd, cwd=HOME, timeout=60):
    return subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True, timeout=timeout)


def assert_ok(result, description):
    assert result.returncode == 0, f"{description} failed:\n{result.stdout}\n{result.stderr}"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def hw_score(seed):
    return (seed * 42) ^ 0xAA


def trunc_div(a, b):
    value = abs(a) // abs(b)
    return -value if (a < 0) != (b < 0) else value


def reference_rpn(expr, seed):
    stack = []
    for token in expr.split(" "):
        if token == "HW":
            stack.append(hw_score(seed))
        elif token in {"+", "-", "*", "/"}:
            right = stack.pop()
            left = stack.pop()
            if token == "+":
                stack.append(left + right)
            elif token == "-":
                stack.append(left - right)
            elif token == "*":
                stack.append(left * right)
            else:
                stack.append(trunc_div(left, right))
        else:
            stack.append(int(token))
    assert len(stack) == 1
    return stack[0]


def test_complete_submission():
    library = os.path.join(CLIB, "libhwscore.so")
    pipeline = os.path.join(HOME, "pipeline.go")
    fixture = os.path.join(HOME, "pipeline_test.go")
    results = os.path.join(HOME, "eval_results.txt")
    rules = os.path.join(HOME, "rules.txt")

    # Preserve the original existence and artifact-kind assertions.
    assert os.path.isfile(library), f"Shared library {library} does not exist. Did you fix the Makefile and run make?"
    if shutil.which("file"):
        output = subprocess.check_output(["file", library], text=True)
        assert "shared object" in output, f"{library} is not a valid shared object."
    assert os.path.isfile(pipeline), f"Go source file {pipeline} does not exist."
    assert os.path.isfile(fixture), f"Go test file {fixture} does not exist."

    # The Makefile must be able to recreate the library from a clean artifact state.
    for artifact in (library, os.path.join(CLIB, "hwscore.o")):
        try:
            os.remove(artifact)
        except FileNotFoundError:
            pass
    make_result = run(["make", "-B"], cwd=CLIB)
    assert_ok(make_result, "make -B")
    assert os.path.isfile(library), "make did not create /home/user/clib/libhwscore.so"
    if shutil.which("file"):
        output = subprocess.check_output(["file", library], text=True)
        assert "shared object" in output, f"{library} is not a valid shared object."

    # Exercise the exported C function on verifier-selected seeds.
    loaded = ctypes.CDLL(library)
    get_hw_score = loaded.get_hw_score
    get_hw_score.argtypes = [ctypes.c_int]
    get_hw_score.restype = ctypes.c_int
    rng = random.SystemRandom()
    for seed in [1, 2, 7, rng.randint(20, 10000), rng.randint(10001, 20000)]:
        assert get_hw_score(seed) == hw_score(seed), f"get_hw_score({seed}) returned an incorrect value"

    original_rules = "5 3 + HW *\nHW 10 - 2 /\n15 HW +\n100 2 / HW * 10 -\n"
    with open(rules, "r") as f:
        assert f.read() == original_rules, "rules.txt no longer contains the supplied rules"

    # Actually run the requested program, then retain the original exact result assertion.
    fixed_run = run(["go", "run", "pipeline.go"])
    assert_ok(fixed_run, "go run pipeline.go on the supplied rules")
    assert os.path.isfile(results), f"Results file {results} does not exist. Did you run your Go program?"
    expected_fixed = ["1024", "122", "227", "90"]
    actual_fixed = read_nonempty_lines(results)
    assert actual_fixed == expected_fixed, f"Contents of {results} do not match the expected results. Got {actual_fixed}, expected {expected_fixed}."

    # Replace the rules temporarily with unpredictable valid expressions and derive
    # their answers independently, preventing a fixed output file from passing.
    a = lambda: rng.randint(2, 80)
    d = lambda: rng.randint(2, 9)
    divisor = d()
    quotient = a()
    expressions = [
        f"{a()} {a()} + HW *",
        f"HW {a()} + {d()} /",
        f"{a()} HW + {a()} *",
        f"{divisor * quotient} {divisor} / HW * {a()} -",
        f"HW HW + {a()} -",
        f"{a()} {a()} * {a()} + {d()} /",
        f"{a()} {a()} + {a()} * HW +",
        f"HW {a()} * {a()} + {d()} /",
    ]
    rng.shuffle(expressions)
    expected_dynamic = [str(reference_rpn(expr, i)) for i, expr in enumerate(expressions, 1)]
    try:
        with open(rules, "w") as f:
            f.write("\n".join(expressions) + "\n")
        try:
            os.remove(results)
        except FileNotFoundError:
            pass
        dynamic_run = run(["go", "run", "pipeline.go"])
        assert_ok(dynamic_run, "go run pipeline.go on verifier-generated rules")
        assert os.path.isfile(results), "pipeline.go did not create eval_results.txt"
        actual_dynamic = read_nonempty_lines(results)
        assert actual_dynamic == expected_dynamic, (
            f"Evaluator returned {actual_dynamic} for verifier-generated rules; expected {expected_dynamic}"
        )
    finally:
        with open(rules, "w") as f:
            f.write(original_rules)

    # Retain the required agent-authored test execution and ensure the fixture
    # contains at least two discoverable tests that exercise EvaluateRPN.
    with open(fixture, "r") as f:
        fixture_source = f.read()
    assert "EvaluateRPN" in fixture_source, "pipeline_test.go does not exercise EvaluateRPN"
    listed = run(["go", "test", "-list", "^Test", "pipeline_test.go", "pipeline.go"])
    assert_ok(listed, "listing tests in pipeline_test.go")
    test_names = [line for line in listed.stdout.splitlines() if re.fullmatch(r"Test[0-9A-Za-z_]+", line.strip())]
    assert len(test_names) >= 2, f"pipeline_test.go must define at least two tests; found {test_names}"
    agent_tests = run(["go", "test", "pipeline_test.go", "pipeline.go"])
    assert_ok(agent_tests, "go test pipeline_test.go pipeline.go")

    # Independently call the dependency-injected evaluator with verifier mocks.
    verifier_test = os.path.join(HOME, "zz_verifier_test.go")
    with open(verifier_test, "w") as f:
        f.write(r'''package main

import (
    "fmt"
    "math/rand"
    "testing"
    "time"
)

func TestVerifierEvaluateRPNWithInjectedHW(t *testing.T) {
    r := rand.New(rand.NewSource(time.Now().UnixNano()))
    for i := 0; i < 20; i++ {
        a := r.Intn(500) + 1
        b := r.Intn(500) + 1
        c := r.Intn(100) + 1
        hw := r.Intn(1000) + 1000
        seed := r.Intn(10000) + 1
        calls := 0
        mock := func(gotSeed int) int {
            calls++
            if gotSeed != seed {
                t.Fatalf("HW mock received seed %d, want %d", gotSeed, seed)
            }
            return hw
        }
        expr := fmt.Sprintf("%d %d + HW * %d -", a, b, c)
        if got, want := EvaluateRPN(expr, mock, seed), (a+b)*hw-c; got != want {
            t.Fatalf("EvaluateRPN(%q) = %d, want %d", expr, got, want)
        }
        if calls != 1 {
            t.Fatalf("HW mock called %d times, want 1", calls)
        }

        calls = 0
        expr = fmt.Sprintf("HW HW + %d /", c)
        if got, want := EvaluateRPN(expr, mock, seed), (hw+hw)/c; got != want {
            t.Fatalf("EvaluateRPN(%q) = %d, want %d", expr, got, want)
        }
        if calls != 2 {
            t.Fatalf("HW mock called %d times, want 2", calls)
        }
    }
}
''')
    independent = run(["go", "test", "pipeline.go", "zz_verifier_test.go"])
    assert_ok(independent, "independent EvaluateRPN tests")
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
