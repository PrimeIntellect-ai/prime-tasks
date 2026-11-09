#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import subprocess
import tempfile

GO_SOURCE = "/home/user/evaluate.go"
B64_PATH = "/home/user/pipeline_data.b64"
VARS_PATH = "/home/user/vars.json"
RESULT_PATH = "/home/user/result.txt"


def evaluate_rpn(expr, variables):
    stack = []
    for token in expr.split():
        if token in ['+', '-', '*', '/']:
            b = stack.pop()
            a = stack.pop()
            if token == '+':
                stack.append(a + b)
            elif token == '-':
                stack.append(a - b)
            elif token == '*':
                stack.append(a * b)
            else:
                stack.append(a // b)
        elif token in variables:
            stack.append(variables[token])
        else:
            stack.append(int(token))
    return stack[0]


def test_evaluate_go_exists():
    assert os.path.isfile(GO_SOURCE), "The Go program /home/user/evaluate.go does not exist."


def test_result_txt_correct():
    assert os.path.isfile(RESULT_PATH), f"The result file {RESULT_PATH} does not exist."
    assert os.path.isfile(B64_PATH), f"Input file {B64_PATH} missing."
    assert os.path.isfile(VARS_PATH), f"Input file {VARS_PATH} missing."

    with open(B64_PATH, 'r') as f:
        encoded_expr = f.read().strip()
    expr = base64.b64decode(encoded_expr).decode('utf-8')

    with open(VARS_PATH, 'r') as f:
        variables = json.load(f)

    expected_result = str(evaluate_rpn(expr, variables))
    with open(RESULT_PATH, 'r') as f:
        actual_result = f.read().strip()

    assert actual_result == expected_result, (
        f"Expected result {expected_result}, but got {actual_result} in {RESULT_PATH}."
    )


def test_compiled_program_handles_dynamic_inputs():
    fd, executable = tempfile.mkstemp(prefix="evaluate_submission_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)

    build = subprocess.run(
        ["go", "build", "-o", executable, GO_SOURCE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"evaluate.go did not compile:\n{build.stderr}"

    with open(B64_PATH, "rb") as f:
        original_b64 = f.read()
    with open(VARS_PATH, "rb") as f:
        original_vars = f.read()

    rng = random.SystemRandom()
    cases = []
    for i in range(12):
        names = [f"metric_{i}_{rng.randrange(1 << 40):010x}_{j}" for j in range(5)]
        variables = {
            names[0]: rng.randint(-10000, 10000),
            names[1]: rng.randint(-500, 500),
            names[2]: rng.randint(-50, 50),
            names[3]: rng.randint(-1000, 1000),
            names[4]: rng.randint(1, 97),
        }
        literal = rng.randint(-40, 40)
        if i % 2 == 0:
            # ((((a + b) * literal) - c) / positive_d)
            expr = f"{names[0]} {names[1]} + {literal} * {names[2]} - {names[4]} /"
        else:
            # (a + (b * c)) - (d / positive_e)
            expr = f"{names[0]} {names[1]} {names[2]} * + {names[3]} {names[4]} / -"
        cases.append((expr, variables))

    # Explicitly exercise Python-style floor division for a negative dividend.
    neg_name = f"negative_{rng.randrange(1 << 48):012x}"
    div_name = f"divisor_{rng.randrange(1 << 48):012x}"
    cases.append((f"{neg_name} {div_name} /", {neg_name: -rng.randint(2, 10000), div_name: rng.randint(2, 97)}))

    try:
        for expr, variables in cases:
            with open(B64_PATH, "w") as f:
                f.write(base64.b64encode(expr.encode("utf-8")).decode("ascii"))
            with open(VARS_PATH, "w") as f:
                json.dump(variables, f)
            if os.path.exists(RESULT_PATH):
                os.unlink(RESULT_PATH)

            run = subprocess.run(
                [executable],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert run.returncode == 0, f"Compiled program failed for expression {expr!r}:\n{run.stderr}"
            assert os.path.isfile(RESULT_PATH), "Compiled program did not create /home/user/result.txt"

            expected = str(evaluate_rpn(expr, variables))
            with open(RESULT_PATH, "r") as f:
                actual = f.read().strip()
            assert actual == expected, f"For expression {expr!r}, expected {expected}, got {actual}"
    finally:
        with open(B64_PATH, "wb") as f:
            f.write(original_b64)
        with open(VARS_PATH, "wb") as f:
            f.write(original_vars)
        subprocess.run([executable], cwd="/home/user", stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10, check=False)
        if os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
