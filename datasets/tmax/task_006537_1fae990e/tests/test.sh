#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/secure-parser"
RESULT_LOG = "/home/user/result.log"
EXPECTED_OUTPUT = "Token: 57"

EXPECTED_MAKEFILE = """CFLAGS=-Wall -Werror -g

test_runner: evaluate.o test_mock.o
\tgcc $(CFLAGS) -o test_runner $^

evaluate.o: evaluate.c ast.h lexer.h parser.h
\tgcc $(CFLAGS) -c evaluate.c

test_mock.o: test_mock.c ast.h lexer.h parser.h
\tgcc $(CFLAGS) -c test_mock.c

clean:
\trm -f *.o test_runner
"""


def run_checked(cmd, **kwargs):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        **kwargs,
    )


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_execute_submission():
    # Preserve the original result.log assertion before rebuilding anything.
    assert os.path.isfile(RESULT_LOG), f"Result log {RESULT_LOG} is missing."
    with open(RESULT_LOG, "r") as f:
        recorded_output = f.read().strip()
    assert recorded_output == EXPECTED_OUTPUT, (
        f"Expected output '{EXPECTED_OUTPUT}', but got '{recorded_output}' in {RESULT_LOG}."
    )

    makefile = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile), f"File {makefile} is missing."
    with open(makefile, "r") as f:
        assert f.read().strip() == EXPECTED_MAKEFILE.strip(), "Makefile was modified."

    # Remove any unrelated pre-created executable, then compile the submitted sources.
    run_checked(["make", "clean"], cwd=PROJECT_DIR)
    run_checked(["make"], cwd=PROJECT_DIR)

    exe_path = os.path.join(PROJECT_DIR, "test_runner")
    assert os.path.isfile(exe_path), f"Executable {exe_path} is missing after make."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    completed = run_checked([exe_path], cwd=PROJECT_DIR)
    actual_output = completed.stdout.strip()
    assert actual_output == EXPECTED_OUTPUT, (
        f"Built test_runner produced {actual_output!r}, expected {EXPECTED_OUTPUT!r}."
    )
    assert recorded_output == actual_output, "result.log does not match the built test_runner output."


def test_result_log_exists_and_correct():
    assert os.path.isfile(RESULT_LOG), f"Result log {RESULT_LOG} is missing."
    with open(RESULT_LOG, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_OUTPUT, f"Expected output '{EXPECTED_OUTPUT}', but got '{content}' in {RESULT_LOG}."


def test_evaluate_c_uses_malloc():
    filepath = os.path.join(PROJECT_DIR, "evaluate.c")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()
    assert "malloc" in content, "evaluate.c does not appear to use malloc to allocate the return value dynamically."
    assert "return &result;" not in content, "evaluate.c still returns the address of a local variable."


def test_test_mock_c_uses_inline_assembly():
    filepath = os.path.join(PROJECT_DIR, "test_mock.c")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()

    # Keep the original checks.
    assert "asm" in content or "__asm__" in content, "test_mock.c does not appear to use inline assembly."
    assert "42" in content, "test_mock.c does not contain the secret key value 42."

    # Ensure those tokens occur in the get_secret_key implementation, not only comments.
    stripped = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    stripped = re.sub(r"//.*", "", stripped)
    match = re.search(r"\bget_secret_key\s*\([^)]*\)\s*\{", stripped)
    assert match, "test_mock.c does not define get_secret_key()."
    start = match.end() - 1
    depth = 0
    end = None
    for i in range(start, len(stripped)):
        if stripped[i] == "{":
            depth += 1
        elif stripped[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    assert end is not None, "Could not parse the get_secret_key() function body."
    body = stripped[start:end + 1]
    assert re.search(r"\b(?:__asm__|__asm|asm)\b", body), "get_secret_key() itself must use inline assembly."
    assert re.search(r"\b42\b", body), "get_secret_key() inline-assembly implementation must produce 42."


def test_test_runner_compiled():
    exe_path = os.path.join(PROJECT_DIR, "test_runner")
    assert os.path.isfile(exe_path), f"Executable {exe_path} is missing. Did you run make?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def test_makefile_unmodified():
    filepath = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED_MAKEFILE.strip(), "Makefile was modified, which was forbidden by the instructions."


def test_headers_compile_independently():
    # In particular, this catches the original circular dependency when lexer.h
    # is the first header included by a translation unit.
    for header in ("ast.h", "lexer.h", "parser.h"):
        source = f'#include "{header}"\nint main(void) {{ return 0; }}\n'
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "header_test.c")
            with open(path, "w") as f:
                f.write(source)
            run_checked([
                "gcc", "-Wall", "-Werror", "-fsyntax-only",
                "-I", PROJECT_DIR, path,
            ])


def test_evaluate_ast_behavior_and_heap_lifetime():
    harness = r'''
#include <stdlib.h>
#include "ast.h"
int *evaluate_ast(ASTNode *node);

int main(void) {
    ASTNode literal1 = {0, 7, NULL, NULL};
    ASTNode literal2 = {0, -3, NULL, NULL};
    int *p1 = evaluate_ast(&literal1);
    int *p2 = evaluate_ast(&literal2);
    if (!p1 || !p2 || p1 == p2 || *p1 != 7 || *p2 != -3) return 1;

    ASTNode left = {0, 10, NULL, NULL};
    ASTNode right = {0, 5, NULL, NULL};
    ASTNode add = {1, 0, &left, &right};
    int *sum = evaluate_ast(&add);
    if (!sum || *sum != 15) return 2;

    free(p1);
    free(p2);
    free(sum);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "evaluate_harness.c")
        exe = os.path.join(td, "evaluate_harness")
        with open(src, "w") as f:
            f.write(harness)
        run_checked([
            "gcc", "-Wall", "-Werror", "-g", "-I", PROJECT_DIR,
            os.path.join(PROJECT_DIR, "evaluate.c"), src, "-o", exe,
        ])
        run_checked([exe])


def test_mock_main_constructs_and_evaluates_required_ast():
    # Replace evaluate_ast only in this instrumentation build. The submitted
    # main must call it with an ADD node whose children hold 10 and 5.
    harness = r'''
#include <stdlib.h>
#include "ast.h"

static int valid_call = 0;

int *checked_evaluate_ast(ASTNode *node) {
    if (node && node->type == 1 && node->left && node->right &&
        node->left->value == 10 && node->right->value == 5) {
        valid_call++;
    }
    int *result = malloc(sizeof(*result));
    if (result) *result = 15;
    return result;
}

int submission_main(void);

int main(void) {
    (void)submission_main();
    return valid_call == 1 ? 0 : 1;
}
'''
    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "test_mock.o")
        src = os.path.join(td, "mock_harness.c")
        exe = os.path.join(td, "mock_harness")
        with open(src, "w") as f:
            f.write(harness)
        run_checked([
            "gcc", "-Wall", "-Werror", "-g", "-I", PROJECT_DIR,
            "-Dmain=submission_main", "-Devaluate_ast=checked_evaluate_ast",
            "-c", os.path.join(PROJECT_DIR, "test_mock.c"), "-o", obj,
        ])
        run_checked([
            "gcc", "-Wall", "-Werror", "-g", "-I", PROJECT_DIR,
            src, obj, "-o", exe,
        ])
        completed = run_checked([exe])
        assert completed.stdout.strip() == EXPECTED_OUTPUT, (
            "Instrumented submitted main did not print the required token."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
