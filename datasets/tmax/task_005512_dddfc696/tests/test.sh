#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

CALC = "/home/user/calc.sh"
PIPELINE = "/home/user/test_pipeline.sh"
TSV = "/home/user/test_cases.tsv"
LOG = "/home/user/pipeline.log"
RNG = random.SystemRandom()


def run_calc(expression):
    return subprocess.run(
        [CALC, expression], capture_output=True, text=True, timeout=5
    )


def make_expression(depth=4):
    if depth <= 0 or RNG.random() < 0.28:
        value = RNG.randint(-100, 100)
        return [str(value)], value

    for _ in range(200):
        left_tokens, left = make_expression(depth - 1)
        right_tokens, right = make_expression(depth - 1)
        op = RNG.choice(["+", "-", "*", "/", "%"])

        if op == "+":
            value = left + right
        elif op == "-":
            value = left - right
        elif op == "*":
            value = left * right
        elif op == "/":
            # Avoid the Python-vs-Bash negative-division distinction while still
            # exercising general integer division.
            if left < 0 or right <= 0:
                continue
            value = left // right
        else:
            if left < 0 or right <= 0:
                continue
            value = left % right

        if abs(value) <= 10**9:
            return left_tokens + right_tokens + [op], value

    value = RNG.randint(-100, 100)
    return [str(value)], value


def randomized_cases(count):
    cases = []

    # Guarantee every operation is covered with values unavailable before the
    # verifier runs.
    a = RNG.randint(-100000, 100000)
    b = RNG.randint(-100000, 100000)
    cases.append((f"{a} {b} +", a + b))
    cases.append((f"{a} {b} -", a - b))
    cases.append((f"{a} {b} *", a * b))
    a = RNG.randint(0, 1000000)
    b = RNG.randint(1, 1000)
    cases.append((f"{a} {b} /", a // b))
    cases.append((f"{a} {b} %", a % b))

    while len(cases) < count:
        tokens, expected = make_expression(RNG.randint(2, 5))
        cases.append((" ".join(tokens), expected))
    return cases


def test_calc_sh_exists_and_executable():
    assert os.path.isfile(CALC), f"Expected Bash script not found at {CALC}"
    assert os.access(CALC, os.X_OK), f"Script {CALC} is not executable"


def test_test_pipeline_sh_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"Expected pipeline script not found at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script {PIPELINE} is not executable"


def test_calc_is_not_reference_file():
    with open(CALC, "rb") as submitted, open("/home/user/legacy_calc.py", "rb") as reference:
        assert submitted.read() != reference.read(), "calc.sh must not be the reference file copied verbatim"


def test_pipeline_log_success():
    assert os.path.isfile(LOG), f"Pipeline log not found at {LOG}"
    with open(LOG, "r") as f:
        content = f.read().strip()
    assert content == "PIPELINE SUCCESS", f"Expected 'PIPELINE SUCCESS' in {LOG}, got '{content}'"


def test_calc_sh_functionality():
    test_cases = [
        ("2 3 +", "5"),
        ("10 5 /", "2"),
        ("7 3 %", "1"),
        ("5 1 2 + 4 * + 3 -", "14"),
        ("100 10 5 * - 2 /", "25"),
        ("15 7 1 1 + - / 3 * 2 %", "1"),
        ("0 5 -", "-5"),
    ]

    for expr, expected in test_cases:
        result = run_calc(expr)
        assert result.returncode == 0, f"Execution of {CALC} failed on expression '{expr}'"
        output = result.stdout.strip()
        assert output == expected, f"For expression '{expr}', expected '{expected}', but got '{output}'"


def test_calc_sh_randomized_functionality():
    for expr, expected in randomized_cases(80):
        result = run_calc(expr)
        assert result.returncode == 0, f"Execution of {CALC} failed on randomized expression '{expr}'"
        assert result.stdout.strip() == str(expected), (
            f"For randomized expression '{expr}', expected '{expected}', "
            f"but got '{result.stdout.strip()}'"
        )


def test_pipeline_failure_behavior(tmp_path):
    failing_tsv = tmp_path / "test_cases.tsv"
    failing_tsv.write_text("2 3 +\t999\n")

    with open(TSV, "r") as f:
        original_tsv = f.read()

    try:
        with open(TSV, "w") as f:
            f.write("2 3 +\t999\n")

        result = subprocess.run([PIPELINE], capture_output=True, timeout=10)
        assert result.returncode != 0, "Pipeline script should exit with non-zero status on failure"

        with open(LOG, "r") as f:
            content = f.read().strip()
        assert content == "PIPELINE FAILED", f"Expected 'PIPELINE FAILED' in {LOG}, got '{content}'"
    finally:
        with open(TSV, "w") as f:
            f.write(original_tsv)
        with open(LOG, "w") as f:
            f.write("PIPELINE SUCCESS\n")


def test_pipeline_with_randomized_tsv():
    with open(TSV, "r") as f:
        original_tsv = f.read()
    original_log = None
    if os.path.exists(LOG):
        with open(LOG, "r") as f:
            original_log = f.read()

    cases = randomized_cases(30)
    good_tsv = "".join(f"{expr}\t{expected}\n" for expr, expected in cases)

    try:
        with open(TSV, "w") as f:
            f.write(good_tsv)

        result = subprocess.run([PIPELINE], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, "Pipeline failed on a dynamically generated valid TSV"
        with open(LOG, "r") as f:
            assert f.read().strip() == "PIPELINE SUCCESS"

        bad_cases = list(cases)
        bad_index = RNG.randrange(len(bad_cases))
        expression, expected = bad_cases[bad_index]
        bad_cases[bad_index] = (expression, expected + RNG.choice([-17, -9, 11, 23]))
        bad_tsv = "".join(f"{expr}\t{answer}\n" for expr, answer in bad_cases)
        with open(TSV, "w") as f:
            f.write(bad_tsv)

        result = subprocess.run([PIPELINE], capture_output=True, text=True, timeout=15)
        assert result.returncode != 0, "Pipeline accepted a randomized TSV containing an incorrect expected output"
        with open(LOG, "r") as f:
            assert f.read().strip() == "PIPELINE FAILED"
    finally:
        with open(TSV, "w") as f:
            f.write(original_tsv)
        with open(LOG, "w") as f:
            f.write(original_log if original_log is not None else "PIPELINE SUCCESS\n")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
