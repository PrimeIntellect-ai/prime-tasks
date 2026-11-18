#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import random
import shutil
import subprocess

import pytest

CALC = pathlib.Path("/home/user/calculator")
PROJECT = CALC / "safe_eval"
SO_PATH = PROJECT / "target/release/libsafe_eval.so"
PY_PATH = CALC / "secure.py"
INPUT_PATH = CALC / "input.txt"
OUTPUT_PATH = CALC / "secure_output.txt"


def read_results(path):
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def expected_value(expression):
    tokens = expression.split()
    result = int(tokens[0])
    for index in range(1, len(tokens), 2):
        operand = int(tokens[index + 1])
        if tokens[index] == "+":
            result += operand
        else:
            result -= operand
    return result


def random_expressions(count):
    rng = random.SystemRandom()
    expressions = []
    for _ in range(count):
        terms = [rng.randint(1, 50000) for _ in range(rng.randint(2, 9))]
        operators = [rng.choice(["+", "-"]) for _ in range(len(terms) - 1)]
        expression = str(terms[0])
        for operator, term in zip(operators, terms[1:]):
            expression += f" {operator} {term}"
        expressions.append(expression)
    return expressions


def test_secure_output_exists_and_correct():
    """Check that secure_output.txt exists and contains the expected results."""
    file_path = "/home/user/calculator/secure_output.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_lines = ["12", "76", "50", "-1"]

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Content of {file_path} does not match expected values. Got {lines}, expected {expected_lines}."


def test_rust_shared_object_exists():
    """Check that the compiled Rust shared object exists."""
    so_path = "/home/user/calculator/safe_eval/target/release/libsafe_eval.so"
    assert os.path.exists(so_path), f"Shared object {so_path} does not exist. Did you build the Rust library in release mode?"
    assert os.path.isfile(so_path), f"{so_path} is not a file."


def test_secure_py_exists_and_uses_ctypes():
    """Check that secure.py exists, imports ctypes, and loads the shared object."""
    py_path = "/home/user/calculator/secure.py"
    assert os.path.exists(py_path), f"Python script {py_path} does not exist."
    assert os.path.isfile(py_path), f"{py_path} is not a file."

    with open(py_path, "r") as f:
        content = f.read()

    assert "import ctypes" in content or "from ctypes import" in content, f"{py_path} does not seem to import ctypes."
    assert "libsafe_eval.so" in content, f"{py_path} does not seem to load the libsafe_eval.so shared object."


def test_rust_project_builds_and_exported_function_works():
    cargo_toml = PROJECT / "Cargo.toml"
    rust_source = PROJECT / "src/lib.rs"
    assert cargo_toml.is_file(), f"{cargo_toml} does not exist."
    assert rust_source.is_file(), f"{rust_source} does not exist."

    cargo_text = cargo_toml.read_text()
    assert "cdylib" in cargo_text, "Cargo.toml is not configured to build a cdylib."

    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust library did not build in release mode:\n{build.stdout}"
    assert SO_PATH.is_file(), f"Build did not create {SO_PATH}."
    assert SO_PATH.read_bytes()[:4] == b"\x7fELF", f"{SO_PATH} is not an ELF shared object."

    try:
        library = ctypes.CDLL(str(SO_PATH))
        evaluate = library.evaluate_expr
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load evaluate_expr from {SO_PATH}: {exc}")

    evaluate.argtypes = [ctypes.c_char_p]
    evaluate.restype = ctypes.c_int32

    expressions = random_expressions(20)
    for expression in expressions:
        actual = evaluate(expression.encode("utf-8"))
        assert actual == expected_value(expression), (
            f"evaluate_expr({expression!r}) returned {actual}, "
            f"expected {expected_value(expression)}"
        )


def test_secure_script_executes_library_on_dynamic_input():
    original_input = INPUT_PATH.read_bytes() if INPUT_PATH.exists() else None
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    original_so = SO_PATH.read_bytes()
    original_mode = SO_PATH.stat().st_mode

    def run_script(expressions):
        INPUT_PATH.write_text("\n".join(expressions) + "\n")
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        result = subprocess.run(
            ["python3", str(PY_PATH)],
            cwd=CALC,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"secure.py failed:\n{result.stdout}"
        assert OUTPUT_PATH.is_file(), "secure.py did not generate secure_output.txt."
        return read_results(OUTPUT_PATH)

    try:
        expressions = random_expressions(12)
        expected = [str(expected_value(expression)) for expression in expressions]
        assert run_script(expressions) == expected, "secure.py produced incorrect dynamic results."

        # Temporarily substitute an instrumented shared library. A genuine ctypes
        # caller will return these deliberately altered, input-dependent values;
        # a Python-only evaluator or hardcoded output will not.
        shim_source = pathlib.Path("/tmp/verifier_safe_eval_shim.rs")
        shim_so = pathlib.Path("/tmp/verifier_libsafe_eval.so")
        shim_source.write_text(r'''
use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub unsafe extern "C" fn evaluate_expr(expr: *const c_char) -> i32 {
    if expr.is_null() {
        return -2147483000;
    }
    let mut result: i32 = 100000;
    for byte in CStr::from_ptr(expr).to_bytes() {
        if !matches!(*byte, b' ' | b'\n' | b'\r' | b'\t') {
            result = result.wrapping_add(*byte as i32);
        }
    }
    result
}
''')
        compiled = subprocess.run(
            ["rustc", "--crate-type", "cdylib", str(shim_source), "-o", str(shim_so)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
        assert compiled.returncode == 0, f"Verifier could not build FFI shim:\n{compiled.stdout}"
        shutil.copyfile(shim_so, SO_PATH)

        ffi_expressions = random_expressions(7)
        ffi_expected = [
            str(100000 + sum(ch for ch in expression.encode("utf-8") if ch not in b" \n\r\t"))
            for expression in ffi_expressions
        ]
        assert run_script(ffi_expressions) == ffi_expected, (
            "secure.py does not use the return value from evaluate_expr in the shared library."
        )
    finally:
        SO_PATH.write_bytes(original_so)
        os.chmod(SO_PATH, original_mode)
        if original_input is None:
            INPUT_PATH.unlink(missing_ok=True)
        else:
            INPUT_PATH.write_bytes(original_input)
        if original_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
