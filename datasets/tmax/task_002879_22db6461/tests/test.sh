#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import shutil
import subprocess
import tempfile

import pytest

WORKSPACE = "/home/user/workspace"
PROCESSOR = os.path.join(WORKSPACE, "processor.go")
ORIGINAL = os.path.join(WORKSPACE, "processor.go.orig")
ARTIFACT = os.path.join(WORKSPACE, "artifact.txt")
OUTPUT = os.path.join(WORKSPACE, "output.txt")
PATCH = os.path.join(WORKSPACE, "fix.patch")
BINARY = "/tmp/processor_under_test"


def test_output_txt_content():
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing. Did you run your Go program and write the output?"

    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    assert content == "30", f"Expected output.txt to contain '30', but found '{content}'"


def test_fix_patch_exists_and_valid():
    assert os.path.isfile(PATCH), f"{PATCH} is missing. Did you generate the diff?"

    with open(PATCH, "r") as f:
        content = f.read()

    assert "---" in content and "+++" in content, f"{PATCH} does not appear to be a valid unified diff patch file."
    assert "processor.go" in content, f"{PATCH} does not appear to contain diffs for processor.go."

    assert os.path.isfile(ORIGINAL), f"Original processor source is missing: {ORIGINAL}"
    assert shutil.which("patch"), "The patch utility is unavailable"

    with tempfile.TemporaryDirectory() as td:
        candidate = os.path.join(td, "processor.go")
        shutil.copyfile(PROCESSOR, candidate)
        result = subprocess.run(
            ["patch", "--batch", "--reverse", "processor.go"],
            cwd=td,
            input=content,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert result.returncode == 0, f"fix.patch is not a valid patch for the submitted processor.go:\n{result.stdout}"
        with open(candidate, "rb") as f:
            reversed_source = f.read()
        with open(ORIGINAL, "rb") as f:
            original_source = f.read()
        assert reversed_source == original_source, "Reversing fix.patch does not reproduce the original processor.go"


def encode_artifact(expression):
    encoded = base64.b64encode(expression.encode("ascii")).decode("ascii")
    return "".join(chr(ord(ch) + 1) for ch in encoded)


def evaluate_rpn(expression):
    stack = []
    for token in expression.split():
        if token not in {"ADD", "SUB", "MUL", "DIV"}:
            stack.append(int(token))
            continue
        right = stack.pop()
        left = stack.pop()
        if token == "ADD":
            stack.append(left + right)
        elif token == "SUB":
            stack.append(left - right)
        elif token == "MUL":
            stack.append(left * right)
        else:
            stack.append(int(left / right))
    assert len(stack) == 1
    return stack[0]


def test_processor_compiles_and_evaluates_artifacts():
    build = subprocess.run(
        ["go", "build", "-o", BINARY, PROCESSOR],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert build.returncode == 0, f"processor.go does not compile:\n{build.stdout}"

    expressions = [
        "7 5 ADD",
        "20 3 SUB",
        "6 7 MUL",
        "20 4 DIV",
        "8 3 SUB 4 MUL 5 ADD",
        "3 10 SUB 2 MUL",
    ]

    original_artifact = open(ARTIFACT, "rb").read()
    output_existed = os.path.exists(OUTPUT)
    original_output = open(OUTPUT, "rb").read() if output_existed else None

    try:
        for expression in expressions:
            expected = str(evaluate_rpn(expression))
            with open(ARTIFACT, "w", encoding="ascii") as f:
                f.write(encode_artifact(expression))
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)

            run = subprocess.run(
                [BINARY],
                cwd=WORKSPACE,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert run.returncode == 0, f"processor failed for {expression!r}:\n{run.stderr}"

            stdout_result = run.stdout.strip()
            file_result = None
            if os.path.isfile(OUTPUT):
                with open(OUTPUT, "r") as f:
                    file_result = f.read().strip()

            assert stdout_result == expected or file_result == expected, (
                f"processor returned the wrong result for {expression!r}: "
                f"expected {expected!r}, stdout was {stdout_result!r}, output.txt was {file_result!r}"
            )
    finally:
        with open(ARTIFACT, "wb") as f:
            f.write(original_artifact)
        if output_existed:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(BINARY):
            os.remove(BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
