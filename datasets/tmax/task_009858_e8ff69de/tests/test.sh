#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import secrets
import subprocess
import sys
import urllib.parse
import pytest

PARSER = "/home/user/modern_parser.py"
DATA = "/home/user/data.txt"
OUTPUT = "/home/user/output.txt"

EXPECTED_DATA_OUTPUT = """result {
  context_id: "alpha"
  value: 40
}
result {
  context_id: "beta"
  value: 58
}
result {
  context_id: "gamma"
  value: 7
}"""


def run_parser(stdin_text):
    try:
        completed = subprocess.run(
            [sys.executable, PARSER],
            input=stdin_text,
            text=True,
            capture_output=True,
            timeout=5,
            cwd="/home/user",
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{PARSER} timed out while processing input.")

    assert completed.returncode == 0, (
        f"{PARSER} exited with status {completed.returncode}: {completed.stderr}"
    )
    assert completed.stderr == "", f"{PARSER} produced unexpected stderr: {completed.stderr}"
    return completed.stdout


def format_result(context, value):
    return f'result {{\n  context_id: "{context}"\n  value: {value}\n}}\n'


def test_modern_parser_exists_and_valid():
    assert os.path.isfile(PARSER), f"File {PARSER} is missing."

    try:
        py_compile.compile(PARSER, doraise=True)
    except py_compile.PyCompileError as e:
        pytest.fail(f"{PARSER} is not a valid Python 3 script. Compilation failed: {e}")


def test_output_txt_content_and_data_execution():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing. Did you save the output?"

    with open(OUTPUT, "r") as f:
        content = f.read()

    assert content.strip() == EXPECTED_DATA_OUTPUT.strip(), (
        f"Content of {OUTPUT} does not match the expected protobuf-like text format."
    )

    with open(DATA, "r") as f:
        data = f.read()

    actual = run_parser(data)
    assert actual.strip() == EXPECTED_DATA_OUTPUT.strip(), (
        "modern_parser.py does not produce the required output for data.txt."
    )
    assert content.strip() == actual.strip(), (
        "output.txt is not the output produced by modern_parser.py for data.txt."
    )


def test_parser_preserves_legacy_behavior_on_unseen_input():
    a = secrets.randbelow(200001) - 100000
    b = secrets.randbelow(200001) - 100000
    c = secrets.randbelow(200001) - 100000
    d = secrets.randbelow(200001) - 100000
    token = secrets.token_hex(12)

    ctx_add = f"add {token}"
    ctx_sub = f"sub {token}"
    ctx_unknown = f"unknown {token}"

    def emu_url(expr, context):
        query = urllib.parse.urlencode({"expr": expr, "context": context})
        return f"emu://generated/path?{query}"

    payload = "\n".join([
        "",
        emu_url(f"add({a},{b})", ctx_add),
        f"http://ignored.example/?expr=add(1,2)&context={token}",
        "not_a_url",
        emu_url(f"sub({c},{d})", ctx_sub),
        emu_url("multiply(9,9)", ctx_unknown),
        "",
    ]) + "\n"

    expected = (
        format_result(ctx_add, a + b)
        + format_result(ctx_sub, c - d)
        + format_result(ctx_unknown, 0)
    )

    assert run_parser(payload) == expected, (
        "modern_parser.py does not preserve the legacy parser's routing, query parsing, "
        "evaluation, and output formatting on unseen input."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
