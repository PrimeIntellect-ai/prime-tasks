#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import secrets
import shutil
import subprocess

import pytest

HOME = "/home/user"


@pytest.fixture(scope="session", autouse=True)
def rebuild_with_orchestration_script():
    """Require the submitted script to recreate the requested build artifacts."""
    script_path = os.path.join(HOME, "run_e2e.sh")
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} must be executable"

    for path in (
        os.path.join(HOME, "librpn_calc.so"),
        os.path.join(HOME, "frontend"),
        os.path.join(HOME, "e2e_output.txt"),
    ):
        if os.path.lexists(path):
            os.remove(path)

    shutil.rmtree(os.path.join(HOME, "rpn_calc", "target"), ignore_errors=True)

    result = subprocess.run(
        [script_path],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"run_e2e.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_rust_project_configuration():
    """Verify the Rust project is configured as a cdylib."""
    cargo_toml_path = "/home/user/rpn_calc/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"{cargo_toml_path} does not exist"

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    assert re.search(r'crate-type\s*=\s*\[.*"cdylib".*\]', content), "Cargo.toml must configure crate-type as 'cdylib'"


def test_rust_lib_source():
    """Verify the Rust source code exposes the correct C ABI function."""
    lib_rs_path = "/home/user/rpn_calc/src/lib.rs"
    assert os.path.isfile(lib_rs_path), f"{lib_rs_path} does not exist"

    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "eval_rpn" in content, "lib.rs must contain the eval_rpn function"
    assert "#[no_mangle]" in content, "eval_rpn function must have #[no_mangle]"
    assert "extern \"C\"" in content, "eval_rpn function must use extern \"C\""


def test_c_frontend_source():
    """Verify the C frontend uses dlopen and dlsym."""
    frontend_c_path = "/home/user/frontend.c"
    assert os.path.isfile(frontend_c_path), f"{frontend_c_path} does not exist"

    with open(frontend_c_path, "r") as f:
        content = f.read()

    assert "dlopen" in content, "frontend.c must use dlopen"
    assert "dlsym" in content, "frontend.c must use dlsym"


def test_orchestration_script():
    """Verify the orchestration script exists and is executable."""
    script_path = "/home/user/run_e2e.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} must be executable"


def test_e2e_output():
    """Verify the output recreated by the end-to-end script is exactly correct."""
    output_path = "/home/user/e2e_output.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist. Did the script run successfully?"

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == "5.00", f"Expected output '5.00', but got '{content}'"
    with open(output_path, "rb") as f:
        assert f.read() == b"5.00\n", "e2e_output.txt must contain only the frontend's formatted output"


def test_compiled_artifacts():
    """Verify the compiled artifacts are present in the user directory."""
    so_path = "/home/user/librpn_calc.so"
    assert os.path.isfile(so_path), f"Shared library {so_path} was not copied to the user directory"

    bin_path = "/home/user/frontend"
    assert os.path.isfile(bin_path), f"Frontend binary {bin_path} was not compiled into the user directory"
    assert os.access(bin_path, os.X_OK), f"Frontend binary {bin_path} must be executable"


def generated_cases():
    cases = [
        ("8 2 /", 8.0 / 2.0),
        ("3 4 + 5 * 6 - 2 /", ((3.0 + 4.0) * 5.0 - 6.0) / 2.0),
        ("-7 2 * 9 +", -7.0 * 2.0 + 9.0),
    ]
    for _ in range(9):
        a = secrets.randbelow(181) - 90
        b = secrets.randbelow(181) - 90
        c = secrets.randbelow(17) + 1
        d = secrets.randbelow(181) - 90
        e = secrets.randbelow(19) + 1
        expr = f"{a} {b} + {c} * {d} - {e} /"
        expected = (((float(a) + float(b)) * float(c)) - float(d)) / float(e)
        cases.append((expr, expected))
    return cases


CASES = generated_cases()


def test_rust_library_executes_rpn_expressions():
    """Load the produced shared object and call its exported C ABI directly."""
    so_path = os.path.join(HOME, "librpn_calc.so")
    lib = ctypes.CDLL(so_path)
    assert hasattr(lib, "eval_rpn"), "librpn_calc.so does not export eval_rpn"
    evaluator = lib.eval_rpn
    evaluator.argtypes = [ctypes.c_char_p]
    evaluator.restype = ctypes.c_double

    for expr, expected in CASES:
        actual = evaluator(expr.encode("utf-8"))
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"eval_rpn({expr!r}) returned {actual}, expected {expected}"
        )


def test_frontend_executes_generated_expressions():
    """Exercise the compiled frontend on unpredictable expressions."""
    frontend = os.path.join(HOME, "frontend")
    for expr, expected in CASES:
        result = subprocess.run(
            [frontend, expr],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"frontend failed for {expr!r}: {result.stderr}"
        assert re.fullmatch(r"-?(?:\d+)\.\d{2}\n", result.stdout), (
            f"frontend output is not in %.2f format for {expr!r}: {result.stdout!r}"
        )
        actual = float(result.stdout.strip())
        assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=0.005000001), (
            f"frontend returned {actual} for {expr!r}, expected {expected:.2f}"
        )


def test_frontend_really_loads_and_calls_eval_rpn(tmp_path):
    """Replace the library temporarily to prove the frontend uses dlopen/dlsym and the function result."""
    sentinel_c = tmp_path / "sentinel.c"
    sentinel_so = tmp_path / "sentinel.so"
    sentinel_c.write_text("double eval_rpn(const char *expr) { (void)expr; return 1234.5; }\n")
    subprocess.run(
        ["gcc", "-shared", "-fPIC", str(sentinel_c), "-o", str(sentinel_so)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    real_so = os.path.join(HOME, "librpn_calc.so")
    saved_so = os.path.join(HOME, ".librpn_calc.so.verifier-save")
    os.replace(real_so, saved_so)
    try:
        shutil.copy2(sentinel_so, real_so)
        result = subprocess.run(
            [os.path.join(HOME, "frontend"), "2 3 +"],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"frontend failed with a valid replacement library: {result.stderr}"
        assert result.stdout == "1234.50\n", (
            "frontend did not print the value returned by dynamically loaded eval_rpn"
        )
    finally:
        if os.path.exists(real_so):
            os.remove(real_so)
        os.replace(saved_so, real_so)


def test_frontend_fails_when_library_is_missing():
    """The frontend must report a loading failure and return nonzero."""
    real_so = os.path.join(HOME, "librpn_calc.so")
    saved_so = os.path.join(HOME, ".librpn_calc.so.verifier-missing")
    os.replace(real_so, saved_so)
    try:
        result = subprocess.run(
            [os.path.join(HOME, "frontend"), "2 3 +"],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode != 0, "frontend must fail when ./librpn_calc.so cannot be loaded"
        assert result.stdout or result.stderr, "frontend must print an error when dlopen fails"
    finally:
        os.replace(saved_so, real_so)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
