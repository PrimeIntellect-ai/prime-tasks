#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import subprocess
import pytest

QA_ENV_DIR = "/home/user/qa_env"


def get_expected_dot_product():
    vectors_file = os.path.join(QA_ENV_DIR, "vectors.json")
    assert os.path.isfile(vectors_file), f"File {vectors_file} is missing."
    with open(vectors_file, "r") as f:
        data = json.load(f)
    x = data.get("vector_x", [])
    y = data.get("vector_y", [])
    assert len(x) == len(y), "vector_x and vector_y must have the same length."
    return sum(a * b for a, b in zip(x, y))


def expected_output(value):
    return f"Test Output Verification: {value}"


def run_make():
    proc = subprocess.run(
        ["make", "-B"],
        cwd=QA_ENV_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert proc.returncode == 0, f"make failed with output:\n{proc.stdout}"


def run_math_eval():
    math_eval = os.path.join(QA_ENV_DIR, "math_eval")
    proc = subprocess.run(
        [math_eval],
        cwd=QA_ENV_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"math_eval exited with status {proc.returncode}. stderr:\n{proc.stderr}"
    )
    return proc.stdout.strip()


def test_config_h():
    expected_dp = get_expected_dot_product()
    config_h = os.path.join(QA_ENV_DIR, "config.h")
    assert os.path.isfile(config_h), f"File {config_h} is missing."

    with open(config_h, "r") as f:
        content = f.read()

    expected_line = f"#define DOT_PRODUCT {expected_dp}"
    assert expected_line in content, (
        "config.h does not contain the expected macro definition. "
        f"Expected to find: {expected_line}"
    )
    assert content.splitlines() == [expected_line], (
        "config.h must contain exactly one line, equal to: " + expected_line
    )


def test_makefile_patched():
    makefile = os.path.join(QA_ENV_DIR, "Makefile")
    assert os.path.isfile(makefile), f"File {makefile} is missing."

    with open(makefile, "r") as f:
        content = f.read()

    assert "-I/nonexistent/path" not in content, (
        "Makefile still contains the broken include path '-I/nonexistent/path'."
    )
    assert "-I." in content, "Makefile does not contain the fixed include path '-I.'."
    assert "main.o: main.c config.h" in content, (
        "Makefile does not contain the fixed dependencies for main.o."
    )


def test_math_eval_compiled_and_executed():
    expected_dp = get_expected_dot_product()
    math_eval = os.path.join(QA_ENV_DIR, "math_eval")
    main_o = os.path.join(QA_ENV_DIR, "main.o")
    config_h = os.path.join(QA_ENV_DIR, "config.h")
    result_txt = os.path.join(QA_ENV_DIR, "result.txt")

    assert os.path.isfile(result_txt), f"File {result_txt} is missing."
    with open(result_txt, "r") as f:
        recorded_result = f.read().strip()
    assert recorded_result == expected_output(expected_dp), (
        "result.txt content is incorrect.\n"
        f"Expected: '{expected_output(expected_dp)}'\nGot: '{recorded_result}'"
    )

    for artifact in (math_eval, main_o):
        if os.path.lexists(artifact):
            os.remove(artifact)

    run_make()

    assert os.path.isfile(math_eval), f"Compiled binary {math_eval} is missing."
    st = os.stat(math_eval)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"File {math_eval} is not executable."
    with open(math_eval, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {math_eval} is not a compiled ELF binary."

    actual_output = run_math_eval()
    assert actual_output == expected_output(expected_dp), (
        "math_eval output is incorrect.\n"
        f"Expected: '{expected_output(expected_dp)}'\nGot: '{actual_output}'"
    )
    assert recorded_result == actual_output, (
        "result.txt does not match the output produced by the compiled math_eval binary."
    )

    original_config = f"#define DOT_PRODUCT {expected_dp}\n"
    probe_value = expected_dp + 137
    try:
        with open(config_h, "w") as f:
            f.write(f"#define DOT_PRODUCT {probe_value}\n")
        run_make()
        probe_output = run_math_eval()
        assert probe_output == expected_output(probe_value), (
            "The rebuilt math_eval binary does not use DOT_PRODUCT from config.h.\n"
            f"Expected: '{expected_output(probe_value)}'\nGot: '{probe_output}'"
        )
    finally:
        with open(config_h, "w") as f:
            f.write(original_config)
        run_make()

    assert run_math_eval() == expected_output(expected_dp)


def test_result_txt():
    expected_dp = get_expected_dot_product()
    result_txt = os.path.join(QA_ENV_DIR, "result.txt")
    assert os.path.isfile(result_txt), f"File {result_txt} is missing."

    with open(result_txt, "r") as f:
        content = f.read().strip()

    expected_content = expected_output(expected_dp)
    assert content == expected_content, (
        "result.txt content is incorrect.\n"
        f"Expected: '{expected_content}'\nGot: '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
