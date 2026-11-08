#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/expr_ffi"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
BINARY_PATH = os.path.join(PROJECT_DIR, "target/release/expr_ffi")
CI_SCRIPT_PATH = os.path.join(PROJECT_DIR, "ci_check.sh")
C_SOURCE = os.path.join(PROJECT_DIR, "src/libexpr.c")

INSTRUMENTED_C = r'''#include <stdio.h>
#include <stdlib.h>
int evaluate(const char* expr) {
    const char* marker = getenv("EXPR_EVAL_MARKER");
    if (marker != NULL) {
        FILE* f = fopen(marker, "a");
        if (f != NULL) {
            fprintf(f, "%s\n", expr != NULL ? expr : "");
            fclose(f);
        }
    }
    return 0;
}
'''


def run_binary(content, expected, require_evaluate=False):
    token = secrets.token_hex(12)
    input_path = os.path.join(tempfile.gettempdir(), f"expr_input_{token}.txt")
    marker_path = os.path.join(tempfile.gettempdir(), f"expr_marker_{token}.txt")
    with open(input_path, "w", encoding="utf-8") as f:
        f.write(content)

    env = os.environ.copy()
    env["EXPR_EVAL_MARKER"] = marker_path
    try:
        result = subprocess.run([BINARY_PATH, input_path], env=env, capture_output=True, text=True)
        assert result.returncode == expected, (
            f"Unexpected exit code for {content!r}: expected {expected}, got {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        if require_evaluate:
            assert os.path.isfile(marker_path), "A safe expression was not passed to C evaluate()."
            with open(marker_path, encoding="utf-8") as f:
                observed = f.read().strip()
            assert observed == content.strip(), "evaluate() was not called with the sanitized input expression."
        else:
            assert not os.path.exists(marker_path), "An unsafe expression reached C evaluate()."
    finally:
        for path in (input_path, marker_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def random_valid_expression(rng, depth=0):
    if depth >= 5 or rng.random() < 0.32:
        return str(rng.randint(0, 9999))
    left = random_valid_expression(rng, depth + 1)
    op = rng.choice(["+", "-", "*", "/"])
    if op == "/":
        right = str(rng.randint(1, 9999))
        if rng.random() < 0.5:
            right = "(" + right + ")"
    else:
        right = random_valid_expression(rng, depth + 1)
    spaces1 = " " * rng.randint(0, 2)
    spaces2 = " " * rng.randint(0, 2)
    expression = left + spaces1 + op + spaces2 + right
    if rng.random() < 0.75:
        expression = "(" + expression + ")"
    return expression


def output_has_status(output, basename, status):
    return any(basename in line and re.search(rf"\b{status}\b", line) for line in output.splitlines())


def test_01_cargo_build_release_and_static_c_linkage():
    """Build release mode and prove build.rs compiles/links src/libexpr.c as expr_c."""
    with open(C_SOURCE, "w", encoding="utf-8") as f:
        f.write(INSTRUMENTED_C)

    subprocess.run(["cargo", "clean"], cwd=PROJECT_DIR, check=True, capture_output=True, text=True)
    result = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, f"Cargo build failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), f"Binary not found at {BINARY_PATH} after successful build."

    archives = glob.glob(os.path.join(PROJECT_DIR, "target/release/build/**/out/libexpr_c.a"), recursive=True)
    assert archives, "Cargo did not produce the required static archive libexpr_c.a from build.rs."
    members = subprocess.run(["ar", "t", archives[0]], capture_output=True, text=True, check=True).stdout
    assert members.strip(), "The expr_c static archive is empty."

    run_binary("17 + (8 * 3)\n", 0, require_evaluate=True)
    run_binary("1 ++ 2\n", 1, require_evaluate=False)


def test_02_generated_parser_and_sanitizer_cases():
    """Exercise generated paths and expressions rather than only the shipped corpus."""
    rng = random.Random(secrets.randbits(128))
    valid = [
        "0\n",
        "123456789\n",
        "1 + 2 * (3 - 4)\n",
        "10 / (2)\n",
        "(" * 15 + "7" + ")" * 15 + "\n",
        "  ( 20 - 3 ) * 4 / 2  \n",
    ]
    valid.extend(random_valid_expression(rng) + "\n" for _ in range(40))

    invalid = [
        "(" * 16 + "1" + ")" * 16 + "\n",
        "1 / 0\n",
        "1/(0)\n",
        "8 / (((0)))\n",
        "1 ++ 2\n",
        "1 +* 2\n",
        "1 */ 2\n",
        "1 -- 2\n",
        "+ 1\n",
        "1 +\n",
        "()\n",
        "(1 + 2\n",
        "1 + 2)\n",
        "1 2\n",
        "(1)(2)\n",
        "1 + abc\n",
        "1 ^ 2\n",
        "\n",
    ]

    for expression in valid:
        run_binary(expression, 0, require_evaluate=True)
    for expression in invalid:
        run_binary(expression, 1, require_evaluate=False)


def test_03_adversarial_corpus_evil():
    """Verify that all files in the evil corpus are rejected (exit code 1)."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in the evil corpus."
    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))
    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_04_adversarial_corpus_clean():
    """Verify that all files in the clean corpus are accepted (exit code 0)."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in the clean corpus."
    modified_files = []
    for filepath in clean_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            modified_files.append(os.path.basename(filepath))
    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified (failed to parse): {', '.join(modified_files)}")


def test_05_ci_script_builds_iterates_reports_and_fails_on_mismatch():
    """Verify CI builds release, checks every file, reports PASS/FAIL, and propagates failures."""
    assert os.path.isfile(CI_SCRIPT_PATH), f"CI script missing: {CI_SCRIPT_PATH}"

    token = secrets.token_hex(10)
    clean_path = os.path.join(CLEAN_CORPUS_DIR, f"generated_clean_{token}.txt")
    evil_path = os.path.join(EVIL_CORPUS_DIR, f"generated_evil_{token}.txt")
    with open(clean_path, "w", encoding="utf-8") as f:
        f.write("91 + (7 * 6)\n")
    with open(evil_path, "w", encoding="utf-8") as f:
        f.write("(" * 16 + "5" + ")" * 16 + "\n")

    try:
        shutil.rmtree(os.path.join(PROJECT_DIR, "target"), ignore_errors=True)
        result = subprocess.run(["bash", CI_SCRIPT_PATH], cwd=PROJECT_DIR, capture_output=True, text=True)
        output = result.stdout + "\n" + result.stderr
        assert result.returncode == 0, (
            f"CI script failed with exit code {result.returncode}:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert os.path.isfile(BINARY_PATH), "CI script did not create the release binary."
        archives = glob.glob(os.path.join(PROJECT_DIR, "target/release/build/**/out/libexpr_c.a"), recursive=True)
        assert archives, "CI script did not perform the required Cargo build of expr_c."

        all_files = []
        for directory in (CLEAN_CORPUS_DIR, EVIL_CORPUS_DIR):
            all_files.extend(os.path.join(directory, name) for name in os.listdir(directory)
                             if os.path.isfile(os.path.join(directory, name)))
        for path in all_files:
            assert output_has_status(output, os.path.basename(path), "PASS"), (
                f"CI output did not print PASS for {os.path.basename(path)}. Output:\n{output}"
            )

        with open(clean_path, "w", encoding="utf-8") as f:
            f.write("4 ++ 9\n")
        failed = subprocess.run(["bash", CI_SCRIPT_PATH], cwd=PROJECT_DIR, capture_output=True, text=True)
        failed_output = failed.stdout + "\n" + failed.stderr
        assert failed.returncode != 0, "CI script returned success when a clean-corpus test failed."
        assert output_has_status(failed_output, os.path.basename(clean_path), "FAIL"), (
            f"CI output did not print FAIL for the mismatched file. Output:\n{failed_output}"
        )
    finally:
        for path in (clean_path, evil_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
