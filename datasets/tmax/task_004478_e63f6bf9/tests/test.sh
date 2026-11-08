#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import secrets
import shutil
import subprocess

PROJECT = "/home/user/project"
C_DIR = os.path.join(PROJECT, "c_src")


def run_pytest(test_file):
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return subprocess.run(
        ["python3", "-m", "pytest", "-q", test_file],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )


def clear_wrapper_cache():
    cache = os.path.join(PROJECT, "__pycache__")
    if os.path.isdir(cache):
        for name in os.listdir(cache):
            if name.startswith("eval_wrapper."):
                os.unlink(os.path.join(cache, name))


def test_c_code_fixed():
    c_file = os.path.join(C_DIR, "libevaluator.c")
    assert os.path.isfile(c_file), f"File {c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert "a * b" in content, "The C code does not seem to have been fixed to perform multiplication (a * b)."


def test_makefile_fixed_and_builds_from_scratch():
    makefile = os.path.join(C_DIR, "Makefile")
    assert os.path.isfile(makefile), f"File {makefile} is missing."
    with open(makefile, "r") as f:
        content = f.read()
    assert "-fPIC" in content, "Makefile is missing the -fPIC flag."
    assert "-shared" in content, "Makefile is missing the -shared flag."

    for name in ("libevaluator.o", "libevaluator.so"):
        path = os.path.join(C_DIR, name)
        if os.path.lexists(path):
            os.unlink(path)
    result = subprocess.run(
        ["make"], cwd=C_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"


def test_library_built_and_functional():
    so_file = os.path.join(C_DIR, "libevaluator.so")
    assert os.path.isfile(so_file), f"Shared library {so_file} was not built."
    with open(so_file, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{so_file} is not a valid ELF file."

    lib = ctypes.CDLL(so_file)
    fn = lib.evaluate_op
    fn.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
    fn.restype = ctypes.c_int
    cases = [
        (0, 137, -52, 85),
        (1, -311, 89, -400),
        (2, -17, 23, -391),
        (2, 19, 0, 0),
        (3, 101, 9, 11),
        (3, -101, 9, -11),
        (3, 101, -9, -11),
        (3, 7, 0, 0),
    ]
    for op, a, b, expected in cases:
        assert fn(op, a, b) == expected, (op, a, b, expected, fn(op, a, b))


def test_results_correct():
    results_file = os.path.join(PROJECT, "results.txt")
    assert os.path.isfile(results_file), f"Results file {results_file} is missing."
    with open(results_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ["42", "58", "72", "12", "-30", "0"]
    assert lines == expected, f"Results in {results_file} do not match the expected output. Got: {lines}"


def trunc_div(a, b):
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def test_parser_exists_runs_and_handles_unseen_inputs():
    parser = os.path.join(PROJECT, "parser.py")
    expressions = os.path.join(PROJECT, "expressions.txt")
    results = os.path.join(PROJECT, "results.txt")
    assert os.path.isfile(parser), f"File {parser} is missing."

    old_expressions = open(expressions, "rb").read()
    old_results = open(results, "rb").read() if os.path.exists(results) else None
    operations = ["ADD", "SUB", "MUL", "DIV"]
    rows = []
    expected = []
    for op in operations:
        for _ in range(6):
            a = secrets.randbelow(10001) - 5000
            b = secrets.randbelow(199) - 99
            rows.append((op, a, b))
            if op == "ADD":
                expected.append(a + b)
            elif op == "SUB":
                expected.append(a - b)
            elif op == "MUL":
                expected.append(a * b)
            else:
                expected.append(trunc_div(a, b))
    rows.extend([("DIV", secrets.randbelow(5000) + 1, 0), ("MUL", -37, 41)])
    expected.extend([0, -1517])
    # Randomize the order so the parser cannot rely on the shipped six-line layout.
    for i in range(len(rows) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        rows[i], rows[j] = rows[j], rows[i]
        expected[i], expected[j] = expected[j], expected[i]

    try:
        with open(expressions, "w") as f:
            for op, a, b in rows:
                f.write(f"{op} {a} {b}\n")
        if os.path.exists(results):
            os.unlink(results)
        proc = subprocess.run(
            ["python3", parser], cwd=PROJECT,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert proc.returncode == 0, f"parser.py failed:\n{proc.stdout}\n{proc.stderr}"
        assert os.path.isfile(results), "parser.py did not create results.txt"
        with open(results) as f:
            actual_lines = [line.strip() for line in f]
        assert actual_lines == [str(x) for x in expected], \
            f"parser.py produced incorrect results for generated expressions: {actual_lines}"
    finally:
        with open(expressions, "wb") as f:
            f.write(old_expressions)
        if old_results is None:
            if os.path.exists(results):
                os.unlink(results)
        else:
            with open(results, "wb") as f:
                f.write(old_results)


def test_property_tests_exist_exercise_wrapper_and_reject_bad_math():
    test_file = os.path.join(PROJECT, "test_eval.py")
    wrapper_file = os.path.join(PROJECT, "eval_wrapper.py")
    assert os.path.isfile(test_file), f"Test file {test_file} is missing."
    with open(test_file, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "The test file does not import/use hypothesis."
    assert "given" in content, "The test file does not use hypothesis.given."
    assert "st.integers" in content or "strategies.integers" in content, "The test file does not use integer strategies."
    ast.parse(content)

    result = run_pytest(test_file)
    assert result.returncode == 0, f"pytest on {test_file} failed. Output:\n{result.stdout}\n{result.stderr}"

    original_wrapper = open(wrapper_file, "rb").read()
    log_file = "/tmp/evaluate_op_calls.jsonl"
    instrumented = f'''import json
LOG = {log_file!r}
def evaluate_op(op_code, a, b):
    op_code, a, b = int(op_code), int(a), int(b)
    if not (-1000 <= a <= 1000 and -1000 <= b <= 1000):
        raise AssertionError("Hypothesis operands must be constrained to -1000..1000")
    with open(LOG, "a") as f:
        f.write(json.dumps([op_code, a, b]) + "\\n")
    if op_code == 0: return a + b
    if op_code == 1: return a - b
    if op_code == 2: return a * b
    if op_code == 3: return 0 if b == 0 else int(a / b)
    return 0
'''
    mutant_template = '''
MUTANT = {mutant!r}
def evaluate_op(op_code, a, b):
    op_code, a, b = int(op_code), int(a), int(b)
    if op_code == 0:
        value = a + b
        return value + 1 if MUTANT == "ADD" else value
    if op_code == 1:
        value = a - b
        return value + 1 if MUTANT == "SUB" else value
    if op_code == 2:
        value = a * b
        return value + 1 if MUTANT == "MUL" else value
    if op_code == 3:
        if b == 0:
            return 1 if MUTANT == "DIV_ZERO" else 0
        value = int(a / b)
        return value + 1 if MUTANT == "DIV" else value
    return 0
'''

    try:
        if os.path.exists(log_file):
            os.unlink(log_file)
        with open(wrapper_file, "w") as f:
            f.write(instrumented)
        clear_wrapper_cache()
        observed = run_pytest(test_file)
        assert observed.returncode == 0, \
            f"Property tests did not pass while exercising evaluate_op:\n{observed.stdout}\n{observed.stderr}"
        assert os.path.isfile(log_file), "The tests never called eval_wrapper.evaluate_op."
        with open(log_file) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert {c[0] for c in calls} >= {0, 1, 2, 3}, "The tests do not exercise all four operation codes."
        for op in range(4):
            pairs = {(c[1], c[2]) for c in calls if c[0] == op}
            assert len(pairs) >= 3, f"Operation {op} was not exercised on varying generated integers."
        assert any(c[0] == 3 and c[2] == 0 for c in calls), "DIV-by-zero behavior is not tested."
        assert any(c[0] == 3 and c[2] != 0 for c in calls), "Nonzero DIV behavior is not tested."

        for mutant in ("ADD", "SUB", "MUL", "DIV", "DIV_ZERO"):
            with open(wrapper_file, "w") as f:
                f.write(mutant_template.format(mutant=mutant))
            clear_wrapper_cache()
            bad = run_pytest(test_file)
            assert bad.returncode != 0, \
                f"test_eval.py failed to detect an incorrect {mutant} implementation."
    finally:
        with open(wrapper_file, "wb") as f:
            f.write(original_wrapper)
        clear_wrapper_cache()
        if os.path.exists(log_file):
            os.unlink(log_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
