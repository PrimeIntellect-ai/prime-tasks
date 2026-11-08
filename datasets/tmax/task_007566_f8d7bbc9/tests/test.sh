#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

PROJECT = "/home/user/project"
EXE_PATH = os.path.join(PROJECT, "parser")
SOURCE_PATH = os.path.join(PROJECT, "parser.c")
DEPS_PATH = os.path.join(PROJECT, "tests/pr_test.deps")


def run_parser(executable, input_path):
    result = subprocess.run(
        [executable, input_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Parser exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout


def make_random_case():
    suffix = secrets.token_hex(6)
    records = [
        (f"frontend_{suffix}", 10 + secrets.randbelow(500),
         [f"db_{suffix}", f"auth_{suffix}"]),
        (f"db_{suffix}", None, [f"network_{suffix}"]),
        (f"auth_{suffix}", 1 + secrets.randbelow(99),
         [f"crypto_{suffix}", f"audit_{suffix}", f"cache_{suffix}"]),
        (f"worker_{suffix}", None,
         [f"queue_{suffix}", f"storage_{suffix}"]),
    ]

    input_lines = []
    output_lines = []
    for target, limit, deps in records:
        if limit is None:
            input_lines.append(f"{target}: {' '.join(deps)};")
            output_limit = 0
        else:
            input_lines.append(f"{target}({limit}): {' '.join(deps)};")
            output_limit = limit
        output_lines.append(
            f"Target: {target}, Limit: {output_limit}, Deps: {' '.join(deps)}"
        )

    return "\n".join(input_lines) + "\n", "\n".join(output_lines) + "\n"


def exercise_parser(executable):
    input_text, expected_output = make_random_case()
    fd, path = tempfile.mkstemp(prefix="dep_parser_", suffix=".deps")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(input_text)
        actual_output = run_parser(executable, path)
        assert actual_output == expected_output, (
            "Parser output for generated rate-limit cases was incorrect.\n"
            f"Input:\n{input_text}\n"
            f"Expected:\n{expected_output}\n"
            f"Actual:\n{actual_output}"
        )
    finally:
        os.unlink(path)


def test_deps_file_content():
    deps_path = "/home/user/project/tests/pr_test.deps"
    assert os.path.isfile(deps_path), f"{deps_path} is missing."

    with open(deps_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "web_server(10): db_client auth_module;\n"
        "db_client(5): network_lib;\n"
        "auth_module: crypto_lib;"
    )
    assert content == expected_content, f"Content of {deps_path} does not match the expected configuration."


def test_executable_exists():
    exe_path = "/home/user/project/parser"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} is missing. Did you run 'make'?"
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."


def test_built_parser_on_required_input():
    expected = (
        "Target: web_server, Limit: 10, Deps: db_client auth_module\n"
        "Target: db_client, Limit: 5, Deps: network_lib\n"
        "Target: auth_module, Limit: 0, Deps: crypto_lib\n"
    )
    assert run_parser(EXE_PATH, DEPS_PATH) == expected


def test_built_parser_on_generated_inputs():
    exercise_parser(EXE_PATH)


def test_source_build_and_behavior():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    with tempfile.TemporaryDirectory(prefix="parser_build_") as build_dir:
        rebuilt = os.path.join(build_dir, "parser")
        result = subprocess.run(
            ["gcc", "-Wall", "-Wextra", "-o", rebuilt, SOURCE_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            "parser.c did not compile successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        exercise_parser(rebuilt)


def test_verification_log_content():
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Verification log {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Target: web_server, Limit: 10, Deps: db_client auth_module",
        "Target: db_client, Limit: 5, Deps: network_lib",
        "Target: auth_module, Limit: 0, Deps: crypto_lib"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in log, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in log mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_c_code_fix():
    c_file_path = "/home/user/project/parser.c"
    assert os.path.isfile(c_file_path), f"Source file {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    # The fix requires null-terminating the target string when '(' is encountered.
    # We check if target is null-terminated or state machine handles it.
    # A common fix is `target[t_idx] = '\0';`
    assert "target[t_idx] = '\\0';" in content or "target[t_idx]='\\0';" in content.replace(" ", ""), \
        "The bug in parser.c does not appear to be fixed. Missing null termination for 'target' when '(' is encountered."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
