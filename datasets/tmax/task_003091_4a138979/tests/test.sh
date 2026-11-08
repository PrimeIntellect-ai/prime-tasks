#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

import pytest


def test_evaluator_c_exists():
    path = "/home/user/evaluator.c"
    assert os.path.isfile(path), f"File {path} is missing."


def test_build_and_test_sh_exists_and_executable():
    path = "/home/user/build_and_test.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_build_and_test_script_runs_from_clean_outputs():
    for path in ("/home/user/evaluator", "/home/user/test_result.json"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    proc = subprocess.run(
        ["/home/user/build_and_test.sh"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        "build_and_test.sh failed:\n"
        + proc.stdout.decode(errors="replace")
        + proc.stderr.decode(errors="replace")
    )


def test_evaluator_executable_exists():
    path = "/home/user/evaluator"
    assert os.path.isfile(path), f"Compiled executable {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_test_result_json_exists_and_correct():
    path = "/home/user/test_result.json"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    try:
        data = json.loads(content.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Content of {path} is not valid JSON: {content}")

    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("result") == 500, f"Expected result 500, got {data.get('result')}"
    assert content == '{"status": "success", "result": 500}\n', "Output JSON format is not exact."


def test_source_compiles_and_evaluators_decode_and_evaluate():
    source_binary = "/tmp/evaluator_from_submitted_source"
    compile_proc = subprocess.run(
        ["gcc", "/home/user/evaluator.c", "-o", source_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        "evaluator.c does not compile with gcc:\n"
        + compile_proc.stdout.decode(errors="replace")
        + compile_proc.stderr.decode(errors="replace")
    )

    cases = [
        (1, "+", 2),
        (100, "-", 42),
        (3, "-", 99),
        (12, "*", 5),
        (12345, "+", 6789),
        (317, "*", 29),
    ]
    for _ in range(18):
        cases.append((
            secrets.randbelow(20000) + 1,
            secrets.choice(("+", "-", "*")),
            secrets.randbelow(20000) + 1,
        ))

    for binary in ("/home/user/evaluator", source_binary):
        for index, (left, operator, right) in enumerate(cases):
            expression = f"{left}{operator}{right}"
            payload = expression.encode("ascii").hex()
            if index % 2:
                payload = payload.upper()

            proc = subprocess.run(
                [binary],
                input=(payload + "\n").encode("ascii"),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (
                f"{binary} failed for encoded expression {payload}: "
                + proc.stderr.decode(errors="replace")
            )

            if operator == "+":
                result = left + right
            elif operator == "-":
                result = left - right
            else:
                result = left * right

            expected = f'{{"status": "success", "result": {result}}}\n'.encode("ascii")
            assert proc.stdout == expected, (
                f"{binary} produced incorrect output for hex payload {payload}. "
                f"Expected {expected!r}, got {proc.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
