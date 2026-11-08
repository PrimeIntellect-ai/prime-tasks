#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import pytest

WORKSPACE = "/home/user/artifact_pipeline"
BINARY = os.path.join(WORKSPACE, "fletcher_calc")
PY_TEST = os.path.join(WORKSPACE, "test_fletcher.py")


def run_command(args, **kwargs):
    try:
        return subprocess.run(args, timeout=120, **kwargs)
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Command timed out: {args!r}: {exc}")


def expected_fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return f"{((sum2 << 8) | sum1):04X}\n"


def test_makefile_fixed_and_binary_compiled():
    makefile_path = os.path.join(WORKSPACE, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}."

    if os.path.lexists(BINARY):
        os.unlink(BINARY)

    dry_run = run_command(
        ["make", "-B", "-n", "-C", WORKSPACE],
        capture_output=True,
        text=True,
    )
    assert dry_run.returncode == 0, (
        f"make dry-run failed:\n{dry_run.stdout}\n{dry_run.stderr}"
    )
    assert re.search(r"(^|[\s/])gcc(?:\s|$)", dry_run.stdout), (
        f"Makefile build command does not use gcc:\n{dry_run.stdout}"
    )

    # Run make to ensure it succeeds and builds the binary
    result = run_command(
        ["make", "-C", WORKSPACE], capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"make failed with output:\n{result.stdout}\n{result.stderr}"
    )

    binary_path = os.path.join(WORKSPACE, "fletcher_calc")
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fletcher_calc is not a compiled ELF executable."

    vectors = [
        b"",
        b"a",
        b"123456789",
        bytes(range(256)),
        b"\x00" * 1024,
        b"\xff" * 1024,
    ]
    vectors.extend(secrets.token_bytes(n) for n in [2, 7, 31, 255, 513, 1024])
    vectors.extend(secrets.token_bytes(secrets.randbelow(1025)) for _ in range(12))

    for data in vectors:
        proc = run_command([binary_path], input=data, capture_output=True)
        assert proc.returncode == 0, (
            f"fletcher_calc exited {proc.returncode} for {len(data)} bytes; "
            f"stderr={proc.stderr!r}"
        )
        assert proc.stderr == b"", f"Unexpected stderr from fletcher_calc: {proc.stderr!r}"
        expected = expected_fletcher16(data).encode("ascii")
        assert proc.stdout == expected, (
            f"Wrong checksum for {len(data)} bytes: got {proc.stdout!r}, expected {expected!r}"
        )


def test_python_test_implementation():
    py_file = os.path.join(WORKSPACE, "test_fletcher.py")
    assert os.path.isfile(py_file), f"Python test file {py_file} does not exist."

    with open(py_file, "r") as f:
        content = f.read()

    assert "test_c_binary_matches_python" in content, "Test function `test_c_binary_matches_python` not found."
    assert "st.binary" in content, "Hypothesis strategy `st.binary` not used."
    assert "subprocess" in content, "subprocess module not used."

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {py_file}: {e}")

    test_func_found = False
    strategy_ok = False
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "test_c_binary_matches_python":
            test_func_found = True
            has_given = any(
                isinstance(d, ast.Call) and getattr(d.func, "id", "") == "given"
                for d in node.decorator_list
            )
            assert has_given, "`test_c_binary_matches_python` is missing the @given decorator."
            assert any(isinstance(n, ast.Assert) for n in ast.walk(node)), (
                "`test_c_binary_matches_python` must assert the binary result."
            )
            for n in ast.walk(node):
                if (
                    isinstance(n, ast.Call)
                    and isinstance(n.func, ast.Attribute)
                    and isinstance(n.func.value, ast.Name)
                    and n.func.value.id == "st"
                    and n.func.attr == "binary"
                ):
                    kwargs = {
                        kw.arg: kw.value.value
                        for kw in n.keywords
                        if kw.arg and isinstance(kw.value, ast.Constant)
                    }
                    if kwargs.get("min_size") == 0 and kwargs.get("max_size") == 1024:
                        strategy_ok = True

    assert test_func_found, "Function `test_c_binary_matches_python` not found in AST."
    assert strategy_ok, "The test must use st.binary(min_size=0, max_size=1024)."

    # Execute the submitted property test against the genuine binary.
    genuine = run_command(
        ["python3", "-m", "pytest", "-q", "test_fletcher.py::test_c_binary_matches_python"],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
    )
    assert genuine.returncode == 0, (
        f"Submitted property test failed:\n{genuine.stdout}\n{genuine.stderr}"
    )
    assert "passed" in genuine.stdout.lower(), "Pytest did not report the property test as passed."

    # Mutation check: a real comparison test must reject a deliberately wrong binary.
    fd, backup = tempfile.mkstemp(prefix="fletcher_calc_backup_", dir="/tmp")
    os.close(fd)
    try:
        shutil.copy2(BINARY, backup)
        with open(BINARY, "w") as f:
            f.write("#!/bin/sh\nprintf 'ZZZZ\\n'\n")
        os.chmod(BINARY, 0o755)
        mutated = run_command(
            ["python3", "-m", "pytest", "-q", "test_fletcher.py::test_c_binary_matches_python"],
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
        )
        assert mutated.returncode != 0, (
            "The property test passed against a deliberately incorrect checksum binary; "
            "it is not validating the binary output against the Python implementation."
        )
    finally:
        os.replace(backup, BINARY)


def test_pytest_output_log():
    log_file = "/home/user/pytest_output.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read()

    assert "passed" in content.lower(), f"Log file {log_file} does not indicate successful test execution."
    assert "test_fletcher" in content, "Log file does not show execution of test_fletcher.py."
    assert "failed" not in content.lower(), "Log file indicates a failed pytest run."


def test_pipeline_status():
    status_file = "/home/user/pipeline_status.txt"
    assert os.path.isfile(status_file), f"Status file {status_file} does not exist."

    with open(status_file, "r") as f:
        content = f.read().strip()

    assert content == "PIPELINE_OK", f"Status file content is '{content}', expected 'PIPELINE_OK'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
