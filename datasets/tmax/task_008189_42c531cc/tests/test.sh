#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import difflib
import os
import random
import shutil
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/project"
EXPR_EVAL_C = os.path.join(PROJECT_DIR, "expr_eval.c")
LIBCALC_SO = os.path.join(PROJECT_DIR, "libcalc.so")
LIBEXPR_EVAL_SO = os.path.join(PROJECT_DIR, "libexpr_eval.so")
RUN_TEST_PY = os.path.join(PROJECT_DIR, "run_test.py")
DIFF_LOG = os.path.join(PROJECT_DIR, "diff.log")
INPUT_TXT = os.path.join(PROJECT_DIR, "input.txt")
BASELINE_TXT = os.path.join(PROJECT_DIR, "baseline.txt")


def run_script(timeout=15, env=None):
    completed = subprocess.run(
        ["python3", RUN_TEST_PY],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert completed.returncode == 0, (
        f"run_test.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_expr_eval_c_memory_fix():
    """Retain the source-level allocation check from the original verifier."""
    assert os.path.isfile(EXPR_EVAL_C), f"File {EXPR_EVAL_C} is missing."
    with open(EXPR_EVAL_C, "r") as f:
        content = f.read()

    assert "malloc(count)" not in content.replace(" ", ""), \
        "The memory allocation bug (malloc(count)) is still present in expr_eval.c."
    assert "sizeof" in content or "*" in content, \
        "The memory allocation in expr_eval.c does not appear to allocate enough space (missing sizeof multiplier)."


def test_source_is_memory_safe_when_exercised():
    """Compile the submitted C source with ASan and exercise a nontrivial result array."""
    harness = r'''
#include <stdio.h>
#include <stdlib.h>
int* evaluate_expressions(char** exprs, int count);
void free_results(int* results);
int main(void) {
    enum { N = 513 };
    char storage[N][64];
    char *exprs[N];
    int expected[N];
    for (int i = 0; i < N; ++i) {
        int a = i + 31;
        int b = (i % 17) + 1;
        char op;
        switch (i % 4) {
            case 0: op = '+'; expected[i] = a + b; break;
            case 1: op = '-'; expected[i] = a - b; break;
            case 2: op = '*'; expected[i] = a * b; break;
            default: op = '/'; expected[i] = a / b; break;
        }
        snprintf(storage[i], sizeof(storage[i]), "%d%c%d", a, op, b);
        exprs[i] = storage[i];
    }
    int *results = evaluate_expressions(exprs, N);
    if (!results) return 10;
    for (int i = 0; i < N; ++i) {
        if (results[i] != expected[i]) return 20;
    }
    free_results(results);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_c = os.path.join(td, "harness.c")
        executable = os.path.join(td, "harness")
        with open(harness_c, "w") as f:
            f.write(harness)
        built = subprocess.run(
            ["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-O1",
             EXPR_EVAL_C, harness_c, "-o", executable],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert built.returncode == 0, f"Failed to compile expr_eval.c with test harness:\n{built.stderr}"
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        tested = subprocess.run(
            [executable], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
        )
        assert tested.returncode == 0, (
            "The submitted expr_eval.c failed functional/memory-safety testing.\n"
            f"stdout:\n{tested.stdout}\nstderr:\n{tested.stderr}"
        )


def test_libexpr_eval_so_compiled_and_linked_correctly():
    """Retain symbol checks and exercise the submitted shared library."""
    assert os.path.isfile(LIBEXPR_EVAL_SO), f"Shared library {LIBEXPR_EVAL_SO} was not compiled."
    assert os.path.isfile(LIBCALC_SO), f"Shared library {LIBCALC_SO} is missing."

    try:
        output = subprocess.check_output(
            ["nm", "-g", LIBEXPR_EVAL_SO], text=True, stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {LIBEXPR_EVAL_SO}: {e.output}")

    for line in output.splitlines():
        if " parse_op" in line:
            pytest.fail("Symbol 'parse_op' is still exported globally in libexpr_eval.so. It must be encapsulated.")

    probe = r'''
import ctypes, sys
calc = ctypes.CDLL(sys.argv[1], mode=ctypes.RTLD_GLOBAL)
lib = ctypes.CDLL(sys.argv[2])
lib.evaluate_expressions.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int]
lib.evaluate_expressions.restype = ctypes.POINTER(ctypes.c_int)
lib.free_results.argtypes = [ctypes.POINTER(ctypes.c_int)]
lib.free_results.restype = None
values = [b"37+5", b"90-13", b"8*7", b"81/9"]
arr = (ctypes.c_char_p * len(values))(*values)
p = lib.evaluate_expressions(arr, len(values))
assert [p[i] for i in range(len(values))] == [42, 77, 56, 9]
lib.free_results(p)
'''
    checked = subprocess.run(
        ["python3", "-c", probe, LIBCALC_SO, LIBEXPR_EVAL_SO],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    assert checked.returncode == 0, (
        "The compiled shared library did not work correctly when loaded with libcalc.so.\n"
        f"stdout:\n{checked.stdout}\nstderr:\n{checked.stderr}"
    )


def test_run_test_py_exists_and_declares_ffi_types():
    """Retain the existence check and require explicit ctypes signature declarations."""
    assert os.path.isfile(RUN_TEST_PY), f"Python script {RUN_TEST_PY} is missing."
    with open(RUN_TEST_PY, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=RUN_TEST_PY)

    aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Attribute) and value.attr == "evaluate_expressions":
                for target in targets:
                    if isinstance(target, ast.Name):
                        aliases.add(target.id)

    def is_eval_object(node):
        return ((isinstance(node, ast.Attribute) and node.attr == "evaluate_expressions") or
                (isinstance(node, ast.Name) and node.id in aliases))

    has_argtypes = False
    has_restype = False
    for node in ast.walk(tree):
        targets = node.targets if isinstance(node, ast.Assign) else ([node.target] if isinstance(node, ast.AnnAssign) else [])
        for target in targets:
            if isinstance(target, ast.Attribute) and is_eval_object(target.value):
                has_argtypes |= target.attr == "argtypes"
                has_restype |= target.attr == "restype"

    assert has_argtypes, "run_test.py does not set evaluate_expressions.argtypes."
    assert has_restype, "run_test.py does not set evaluate_expressions.restype."


def test_run_test_executes_and_diff_log_correctness():
    """Execute the submitted script, then retain the original fixed-case diff assertion."""
    run_script()
    assert os.path.isfile(DIFF_LOG), f"Diff log file {DIFF_LOG} is missing."

    expected_results = ["9\n", "15\n", "16\n", "17\n"]
    assert os.path.isfile(BASELINE_TXT), f"Baseline file {BASELINE_TXT} is missing."
    with open(BASELINE_TXT, "r") as f:
        baseline = f.readlines()
    expected_diff_str = "".join(difflib.unified_diff(
        baseline, expected_results, fromfile="baseline", tofile="results"
    ))
    with open(DIFF_LOG, "r") as f:
        actual_diff_str = f.read()
    assert actual_diff_str.strip() == expected_diff_str.strip(), \
        f"Contents of {DIFF_LOG} do not match the expected unified diff.\nExpected:\n{expected_diff_str}\nActual:\n{actual_diff_str}"


def test_run_test_uses_both_libraries_evaluator_and_free_on_fresh_data():
    """Replace the libraries temporarily with tracing ABI-compatible libraries and run fresh inputs."""
    rng = random.SystemRandom()
    expressions = []
    results = []
    for _ in range(23):
        a = rng.randrange(20, 500)
        b = rng.randrange(1, 20)
        op = rng.choice(["+", "-", "*", "/"])
        expressions.append(f"{a}{op}{b}")
        results.append({"+": a + b, "-": a - b, "*": a * b, "/": a // b}[op])
    baseline_values = [rng.randrange(-1000, 1000) for _ in range(11)]

    calc_source = r'''
#include <stdio.h>
#include <stdlib.h>
static void log_line(const char *s) {
    const char *p = getenv("TRACE_FILE");
    if (!p) return;
    FILE *f = fopen(p, "a"); if (f) { fprintf(f, "%s\n", s); fclose(f); }
}
__attribute__((constructor)) static void loaded(void) { log_line("CALC_LOADED"); }
int parse_op(int a, int b) { return a * b + 100; }
'''
    expr_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static void log_event(const char *kind, void *ptr, int count) {
    const char *p = getenv("TRACE_FILE");
    if (!p) return;
    FILE *f = fopen(p, "a");
    if (f) { fprintf(f, "%s %p %d\n", kind, ptr, count); fclose(f); }
}
__attribute__((constructor)) static void loaded(void) { log_event("EXPR_LOADED", 0, 0); }
int* evaluate_expressions(char **exprs, int count) {
    int *out = malloc((size_t)count * sizeof(*out));
    if (!out) return NULL;
    for (int i = 0; i < count; ++i) {
        int a = 0, b = 0; char op = 0;
        if (sscanf(exprs[i], "%d%c%d", &a, &op, &b) != 3) out[i] = 0;
        else if (op == '+') out[i] = a + b;
        else if (op == '-') out[i] = a - b;
        else if (op == '*') out[i] = a * b;
        else if (op == '/') out[i] = b ? a / b : 0;
        else out[i] = 0;
    }
    log_event("EVALUATE", out, count);
    return out;
}
void free_results(int *p) {
    log_event("FREE", p, 0);
    free(p);
}
'''

    tracked = [LIBCALC_SO, LIBEXPR_EVAL_SO, INPUT_TXT, BASELINE_TXT, DIFF_LOG]
    saved = {}
    for path in tracked:
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    with tempfile.TemporaryDirectory() as td:
        calc_c = os.path.join(td, "calc.c")
        expr_c = os.path.join(td, "expr.c")
        trace = os.path.join(td, "trace.log")
        with open(calc_c, "w") as f:
            f.write(calc_source)
        with open(expr_c, "w") as f:
            f.write(expr_source)
        try:
            subprocess.check_call(["gcc", "-shared", "-fPIC", calc_c, "-o", LIBCALC_SO])
            subprocess.check_call(["gcc", "-shared", "-fPIC", expr_c, "-o", LIBEXPR_EVAL_SO])
            with open(INPUT_TXT, "w") as f:
                f.write("\n".join(expressions) + "\n")
            baseline_lines = [f"{x}\n" for x in baseline_values]
            with open(BASELINE_TXT, "w") as f:
                f.writelines(baseline_lines)
            if os.path.exists(DIFF_LOG):
                os.unlink(DIFF_LOG)

            env = os.environ.copy()
            env["TRACE_FILE"] = trace
            run_script(env=env)

            assert os.path.isfile(trace), "No library trace was produced by run_test.py."
            trace_lines = open(trace).read().splitlines()
            assert any(line == "CALC_LOADED" for line in trace_lines), "run_test.py did not load libcalc.so."
            assert any(line.startswith("EXPR_LOADED ") for line in trace_lines), "run_test.py did not load libexpr_eval.so."
            eval_events = [line.split() for line in trace_lines if line.startswith("EVALUATE ")]
            free_events = [line.split() for line in trace_lines if line.startswith("FREE ")]
            assert len(eval_events) == 1, "run_test.py did not call evaluate_expressions exactly once."
            assert int(eval_events[0][2]) == len(expressions), "evaluate_expressions received the wrong expression count."
            assert any(event[1] == eval_events[0][1] for event in free_events), \
                "run_test.py did not pass the returned allocation to free_results."

            expected_result_lines = [f"{x}\n" for x in sorted(results)]
            expected_diff = "".join(difflib.unified_diff(
                baseline_lines, expected_result_lines, fromfile="baseline", tofile="results"
            ))
            assert os.path.isfile(DIFF_LOG), "run_test.py did not create diff.log."
            with open(DIFF_LOG, "r") as f:
                actual_diff = f.read()
            assert actual_diff == expected_diff, \
                f"run_test.py produced an incorrect diff for fresh inputs.\nExpected:\n{expected_diff}\nActual:\n{actual_diff}"
        finally:
            for path, data in saved.items():
                if data is None:
                    if os.path.exists(path):
                        os.unlink(path)
                else:
                    with open(path, "wb") as f:
                        f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
