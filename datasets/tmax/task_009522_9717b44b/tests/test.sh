#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -f /home/user/seq_analyzer/verifier_generated_test.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

PROJECT = "/home/user/seq_analyzer"
TEST_FILE = os.path.join(PROJECT, "optimize_test.go")
OPTIMIZE_FILE = os.path.join(PROJECT, "optimize.go")
RESULT_FILE = "/home/user/result.txt"
SEQ_FILE = "/home/user/data/sequences.txt"
TARGET_FILE = "/home/user/data/targets.txt"
BINARY = "/tmp/seq_analyzer_submission"
GENERATED_TEST = os.path.join(PROJECT, "verifier_generated_test.go")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)


def test_optimize_test_exists_and_contains_requirements():
    assert os.path.isfile(TEST_FILE), f"{TEST_FILE} is missing. You need to create the regression test."
    with open(TEST_FILE, "r") as f:
        content = f.read()

    # Preserve the original required-parameter checks.
    assert "1.0" in content and "2.0" in content, "optimize_test.go is missing the required ratios [1.0, 2.0]"
    assert "2.0" in content and "4.0" in content, "optimize_test.go is missing the required targets [2.0, 4.0]"
    assert "0.1" in content, "optimize_test.go is missing the required learning rate 0.1"
    assert "100" in content, "optimize_test.go is missing the required epochs 100"


def test_go_test_passes():
    result = run(["go", "test", "-count=1"], cwd=PROJECT)
    assert result.returncode == 0, f"'go test' failed in {PROJECT}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def _replace_gradient_descent_body(source):
    match = re.search(
        r"func\s+GradientDescent\s*\([^)]*\)\s*float64\s*\{",
        source,
        flags=re.MULTILINE,
    )
    assert match, "Could not locate GradientDescent in optimize.go"
    open_brace = match.end() - 1
    depth = 0
    i = open_brace
    state = "code"
    while i < len(source):
        c = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line_comment"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block_comment"; i += 2; continue
            if c == '"':
                state = "string"; i += 1; continue
            if c == "'":
                state = "rune"; i += 1; continue
            if c == "`":
                state = "raw"; i += 1; continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return source[:open_brace] + "{\n\treturn 0.0\n}" + source[i + 1:]
        elif state == "line_comment":
            if c == "\n": state = "code"
        elif state == "block_comment":
            if c == "*" and nxt == "/": state = "code"; i += 2; continue
        elif state in ("string", "rune"):
            if c == "\\": i += 2; continue
            if (state == "string" and c == '"') or (state == "rune" and c == "'"):
                state = "code"
        elif state == "raw":
            if c == "`": state = "code"
        i += 1
    raise AssertionError("Could not find the end of GradientDescent")


def test_submission_contains_an_effective_regression_test():
    listed = run(["go", "test", "-list", "^Test"], cwd=PROJECT)
    assert listed.returncode == 0, listed.stdout + listed.stderr
    assert re.search(r"(?m)^Test\w+\s*$", listed.stdout), "optimize_test.go does not define a runnable Go Test function"

    with open(OPTIMIZE_FILE, "r") as f:
        original = f.read()
    mutant = _replace_gradient_descent_body(original)
    try:
        with open(OPTIMIZE_FILE, "w") as f:
            f.write(mutant)
        result = run(["go", "test", "-count=1"], cwd=PROJECT)
        combined = result.stdout + result.stderr
        assert result.returncode != 0, "The submitted tests still pass when GradientDescent always returns 0; the regression test is ineffective"
        assert "[build failed]" not in combined, f"Mutant caused a build error instead of a test failure:\n{combined}"
        assert re.search(r"--- FAIL: Test", combined), f"No runnable Test function rejected the broken optimizer:\n{combined}"
    finally:
        with open(OPTIMIZE_FILE, "w") as f:
            f.write(original)


def test_gradient_descent_matches_mse_gradient_on_derived_cases():
    rng = random.SystemRandom()
    cases = []
    for n in (1, 3, 5):
        ratios = [rng.uniform(0.2, 2.5) for _ in range(n)]
        targets = [rng.uniform(-1.0, 5.0) for _ in range(n)]
        a = (2.0 / n) * sum(r * r for r in ratios)
        lr = 0.2 / a
        epochs = rng.randint(12, 35)
        k = 0.0
        for _ in range(epochs):
            grad = (2.0 / n) * sum(r * (k * r - t) for r, t in zip(ratios, targets))
            k -= lr * grad
        cases.append((ratios, targets, lr, epochs, k))

    def go_slice(values):
        return "[]float64{" + ",".join(format(v, ".17g") for v in values) + "}"

    blocks = []
    for idx, (ratios, targets, lr, epochs, expected) in enumerate(cases):
        blocks.append(f'''\n\t{{\n\t\tgot := GradientDescent({go_slice(ratios)}, {go_slice(targets)}, {lr:.17g}, {epochs})\n\t\twant := {expected:.17g}\n\t\tif math.Abs(got-want) > 1e-9 {{\n\t\t\tt.Fatalf("derived case {idx}: got %.15g, want %.15g", got, want)\n\t\t}}\n\t}}''')

    source = '''package main

import (
    "math"
    "testing"
)

func TestVerifierDerivedMSEGradientCases(t *testing.T) {
''' + "".join(blocks) + '''
}
'''
    try:
        with open(GENERATED_TEST, "w") as f:
            f.write(source)
        result = run(["go", "test", "-count=1", "-run", "TestVerifierDerivedMSEGradientCases"], cwd=PROJECT)
        assert result.returncode == 0, f"GradientDescent does not implement the MSE gradient correctly.\n{result.stdout}\n{result.stderr}"
    finally:
        if os.path.exists(GENERATED_TEST):
            os.remove(GENERATED_TEST)


def _expected_k(ratios, targets, lr=0.05, epochs=1000):
    k = 0.0
    n = len(ratios)
    for _ in range(epochs):
        grad = (2.0 / n) * sum(r * (k * r - t) for r, t in zip(ratios, targets))
        k -= lr * grad
    return f"{k:.4f}"


def _run_binary_and_get_result():
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    result = run([BINARY], cwd=PROJECT)
    assert result.returncode == 0, f"Built program failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    file_content = None
    if os.path.isfile(RESULT_FILE):
        with open(RESULT_FILE, "r") as f:
            file_content = f.read()
    if file_content is not None and file_content.strip() != "":
        content = file_content.strip()
    else:
        content = result.stdout.strip()
        assert content, "Program neither wrote result.txt nor emitted a value that can be redirected to it"
        with open(RESULT_FILE, "w") as f:
            f.write(content + "\n")
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", content), f"Program output is not exactly one number with four decimal places: {content!r}"
    return content


def test_built_program_computes_results_from_input_and_restores_required_result():
    build = run(["go", "build", "-o", BINARY, "."], cwd=PROJECT)
    assert build.returncode == 0, f"Project did not build.\nStdout: {build.stdout}\nStderr: {build.stderr}"

    with open(SEQ_FILE, "rb") as f:
        original_sequences = f.read()
    with open(TARGET_FILE, "rb") as f:
        original_targets = f.read()

    rng = random.SystemRandom()
    sequence_cases = [
        (["ATGC", "ATATGC", "ATGGGG"], [1.0, 2.0, 0.5]),
        (["ATATGC", "ATGC", "GCGC", "ATGGGG"], [2.0, 1.0, 0.0, 0.5]),
    ]
    try:
        for sequences, ratios in sequence_cases:
            targets = [rng.uniform(0.25, 5.75) for _ in ratios]
            with open(SEQ_FILE, "w") as f:
                f.write("\n".join(sequences) + "\n")
            with open(TARGET_FILE, "w") as f:
                f.write("\n".join(format(t, ".17g") for t in targets) + "\n")
            got = _run_binary_and_get_result()
            want = _expected_k(ratios, targets)
            assert got == want, f"Built program produced {got} for verifier-derived input; expected {want}"
    finally:
        with open(SEQ_FILE, "wb") as f:
            f.write(original_sequences)
        with open(TARGET_FILE, "wb") as f:
            f.write(original_targets)

    # Execute once more on the required data and preserve the original exact assertion.
    got = _run_binary_and_get_result()
    assert os.path.isfile(RESULT_FILE), f"{RESULT_FILE} is missing. Did you redirect the output or modify main.go?"
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()
    assert content == "0.5455", f"Expected '0.5455' in {RESULT_FILE}, but got '{content}'"
    assert got == "0.5455"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
