#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import stat
import subprocess

PROJECT = "/home/user/project"
PIPELINE = os.path.join(PROJECT, "ci/run_pipeline.sh")
STATUS = "/home/user/pipeline_status.txt"
LIB = os.path.join(PROJECT, "libexpr.so")
CLI = os.path.join(PROJECT, "expr_cli")


def remove_outputs():
    for path in (STATUS, LIB, CLI):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_pipeline():
    return subprocess.run(
        ["/bin/bash", PIPELINE],
        cwd=PROJECT,
        env=os.environ.copy(),
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_00_pipeline_rejects_bad_library_and_then_succeeds():
    assert os.path.isfile(PIPELINE), f"Missing {PIPELINE}"
    expr_c = os.path.join(PROJECT, "src/expr.c")
    with open(expr_c, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(expr_c).st_mode)

    # A real pipeline must run its expression tests, not merely build files and
    # self-report success. Temporarily provide a valid but deliberately wrong
    # library implementation and require the pipeline to catch it.
    bad_source = b'''int evaluate_math(const char *expr) {\n    (void)expr;\n    return 424242;\n}\n'''
    try:
        with open(expr_c, "wb") as f:
            f.write(bad_source)
        remove_outputs()
        bad = run_pipeline()
        assert bad.returncode != 0, (
            "The pipeline reported success with a deliberately incorrect "
            f"evaluate_math implementation. stdout={bad.stdout!r} stderr={bad.stderr!r}"
        )
        if os.path.exists(STATUS):
            with open(STATUS, "r") as f:
                assert f.read().strip() != "PIPELINE_SUCCESS", (
                    "The pipeline wrote PIPELINE_SUCCESS despite failing its dynamic tests"
                )
    finally:
        with open(expr_c, "wb") as f:
            f.write(original)
        os.chmod(expr_c, original_mode)

    remove_outputs()
    good = run_pipeline()
    assert good.returncode == 0, (
        f"Pipeline failed with return code {good.returncode}. "
        f"stdout={good.stdout!r} stderr={good.stderr!r}"
    )


def test_pipeline_status():
    status_file = "/home/user/pipeline_status.txt"
    assert os.path.isfile(status_file), f"Missing {status_file}. Did the pipeline run successfully?"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "PIPELINE_SUCCESS", f"Expected PIPELINE_SUCCESS in {status_file}, got '{content}'"


def test_expr_c_visibility_fixed():
    expr_c = "/home/user/project/src/expr.c"
    assert os.path.isfile(expr_c), f"Missing {expr_c}"
    with open(expr_c, "r") as f:
        content = f.read()
    assert 'visibility("hidden")' not in content, "The evaluate_math function still has hidden visibility in src/expr.c"


def test_run_pipeline_fixed():
    pipeline = "/home/user/project/ci/run_pipeline.sh"
    assert os.path.isfile(pipeline), f"Missing {pipeline}"
    with open(pipeline, "r") as f:
        content = f.read()
    assert 'EXPECTED=$(echo "0")' not in content, "The expected calculation in run_pipeline.sh is still broken (hardcoded to 0)"
    assert '-shared' in content, "The gcc command for libexpr.so must use -shared"
    assert '-fPIC' in content, "The gcc command for libexpr.so must use -fPIC"


def command_output(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, (
        f"Command {args!r} failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    return result.stdout


def test_artifacts_are_real_dynamic_binaries():
    assert os.path.isfile(LIB), f"Missing compiled library {LIB}"
    assert os.path.isfile(CLI), f"Missing compiled CLI {CLI}"
    assert os.access(CLI, os.X_OK), f"CLI is not executable: {CLI}"

    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libexpr.so is not an ELF shared library"
    with open(CLI, "rb") as f:
        assert f.read(4) == b"\x7fELF", "expr_cli is not an ELF executable"

    lib_header = command_output(["readelf", "-h", LIB])
    assert "DYN (Shared object file)" in lib_header, "libexpr.so is not an ELF shared object"

    lib_symbols = command_output(["nm", "-D", LIB])
    exported = [line.split() for line in lib_symbols.splitlines() if line.split()]
    assert any(parts[-1] == "evaluate_math" and len(parts) >= 3 and parts[-2].upper() in {"T", "W"}
               for parts in exported), "libexpr.so does not export evaluate_math"

    cli_dynamic = command_output(["readelf", "-d", CLI])
    assert "Shared library: [libexpr.so]" in cli_dynamic, "expr_cli is not dynamically linked to libexpr.so"
    cli_symbols = command_output(["nm", "-D", CLI])
    assert any(" U evaluate_math" in line for line in cli_symbols.splitlines()), (
        "expr_cli does not import evaluate_math from the shared library"
    )


def generated_cases():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(4):
        a, b, c = (rng.randrange(2, 40) for _ in range(3))
        cases.extend([
            (f"{a} + {b} * {c}", a + b * c),
            (f"{a} * {b} - {c}", a * b - c),
            (f"({a} + {b}) * {c}", (a + b) * c),
            (f"{a * b} / {b} + {c}", a + c),
        ])
    return cases


def test_artifacts_exist_and_work():
    lib_path = "/home/user/project/libexpr.so"
    cli_path = "/home/user/project/expr_cli"
    assert os.path.isfile(lib_path), f"Missing compiled library {lib_path}"
    assert os.path.isfile(cli_path), f"Missing compiled CLI {cli_path}"

    # Preserve the original fixed behavior assertion.
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/project"
    try:
        result = subprocess.run([cli_path, "5 + 7"], env=env, capture_output=True, text=True, timeout=2)
        assert result.returncode == 0, f"CLI execution failed with return code {result.returncode}. Stderr: {result.stderr}"
        assert result.stdout.strip() == "12", f"CLI output incorrect. Expected '12', got '{result.stdout.strip()}'"
    except Exception as e:
        assert False, f"Failed to execute {cli_path}: {e}"

    # Exercise unpredictable expressions whose answers are independently derived.
    cases = generated_cases()
    for expression, expected in cases:
        result = subprocess.run(
            [cli_path, expression], env=env, capture_output=True, text=True, timeout=3
        )
        assert result.returncode == 0, (
            f"CLI failed for {expression!r}: return code {result.returncode}, stderr={result.stderr!r}"
        )
        assert result.stdout.strip() == str(expected), (
            f"CLI output incorrect for {expression!r}: expected {expected}, got {result.stdout.strip()!r}"
        )

    # Call the shared-library ABI directly so a standalone fake CLI cannot pass.
    helper = r'''
import ctypes, json, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.evaluate_math
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_int
cases = json.loads(sys.argv[2])
for expression, expected in cases:
    actual = fn(expression.encode())
    if actual != expected:
        raise SystemExit(f"{expression!r}: expected {expected}, got {actual}")
'''
    direct = subprocess.run(
        ["python3", "-c", helper, LIB, json.dumps(cases)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert direct.returncode == 0, (
        f"Direct evaluate_math ABI tests failed: stdout={direct.stdout!r}, stderr={direct.stderr!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
