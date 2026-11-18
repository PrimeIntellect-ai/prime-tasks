#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import shutil
import subprocess

import pytest

WORKSPACE = "/home/user/polymath"


def run(command, **kwargs):
    return subprocess.run(
        command,
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        **kwargs,
    )


def load_evaluate(library_path):
    library = ctypes.CDLL(str(library_path))
    function = library.evaluate
    function.argtypes = [ctypes.c_double, ctypes.c_double]
    function.restype = ctypes.c_double
    return library, function


def test_git_repo_initialized():
    git_dir = os.path.join(WORKSPACE, ".git")
    assert os.path.isdir(git_dir), "Git repository not initialized in /home/user/polymath"


def test_model_msm_content():
    msm_file = os.path.join(WORKSPACE, "model.msm")
    assert os.path.isfile(msm_file), "model.msm does not exist"

    expected_content = """INPUT x y
t1 = ADD x 5.0
t2 = MUL t1 y
t3 = SUB t2 x
OUTPUT t3"""
    with open(msm_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, "model.msm content does not match expected exact content."


def test_parser_exists():
    parser_file = os.path.join(WORKSPACE, "parser.py")
    assert os.path.isfile(parser_file), "parser.py does not exist"


def test_makefile_contents():
    makefile = os.path.join(WORKSPACE, "Makefile")
    assert os.path.isfile(makefile), "Makefile does not exist"

    with open(makefile, "r") as f:
        content = f.read()

    assert "parser.py" in content, "Makefile does not invoke parser.py"
    assert "gcc" in content or "cc " in content, "Makefile does not compile C code using gcc/cc"
    assert "-shared" in content, "Makefile does not use -shared to build a shared library"
    assert "-fPIC" in content, "Makefile does not use -fPIC"


def test_test_model_exists():
    test_file = os.path.join(WORKSPACE, "test_model.py")
    assert os.path.isfile(test_file), "test_model.py does not exist"


def test_generated_files():
    c_file = os.path.join(WORKSPACE, "model.c")
    so_file = os.path.join(WORKSPACE, "libmodel.so")

    assert os.path.isfile(c_file), "model.c was not generated"
    assert os.path.isfile(so_file), "libmodel.so was not generated"


def test_result_txt():
    result_file = os.path.join(WORKSPACE, "result.txt")
    assert os.path.isfile(result_file), "result.txt does not exist"

    with open(result_file, "r") as f:
        res = f.read().strip()

    try:
        val = float(res)
    except ValueError:
        pytest.fail(f"result.txt content '{res}' is not a valid float")

    assert val == 29.0, f"Expected result.txt to contain 29.0, but got {val}"


def test_pre_commit_hook():
    hook_file = os.path.join(WORKSPACE, ".git", "hooks", "pre-commit")
    assert os.path.isfile(hook_file), "pre-commit hook does not exist"
    assert os.access(hook_file, os.X_OK), "pre-commit hook is not executable"

    with open(hook_file, "r") as f:
        content = f.read()

    assert "make" in content, "pre-commit hook does not run 'make'"
    assert "test_model.py" in content, "pre-commit hook does not run test_model.py"


def test_make_rebuilds_and_compiled_library_computes_model():
    for name in ("model.c", "libmodel.so", "result.txt"):
        path = os.path.join(WORKSPACE, name)
        if os.path.lexists(path):
            os.unlink(path)

    completed = run(["make"])
    assert completed.returncode == 0, completed.stdout + completed.stderr

    c_file = os.path.join(WORKSPACE, "model.c")
    so_file = os.path.join(WORKSPACE, "libmodel.so")
    assert os.path.isfile(c_file), "make did not generate model.c"
    assert os.path.isfile(so_file), "make did not generate libmodel.so"

    library, evaluate = load_evaluate(so_file)
    for x, y in [(3.0, 4.0), (1.25, -2.0), (-7.0, 0.5), (9.0, 3.0)]:
        expected = (x + 5.0) * y - x
        actual = evaluate(x, y)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"evaluate({x}, {y}) returned {actual}, expected {expected}"
        )
    assert library is not None


def test_parser_compiles_a_different_valid_program(tmp_path):
    source = tmp_path / "alternate.msm"
    generated = tmp_path / "alternate.c"
    library_path = tmp_path / "alternate.so"
    source.write_text(
        "INPUT x y\n"
        "difference = SUB x y\n"
        "half = DIV difference 2.0\n"
        "offset = ADD half 7.5\n"
        "answer = MUL offset y\n"
        "OUTPUT answer\n"
    )

    parsed = run(["python3", "parser.py", str(source), str(generated)])
    assert parsed.returncode == 0, parsed.stdout + parsed.stderr
    assert generated.is_file(), "parser.py did not generate C for an alternate MSM program"

    compiled = run(["gcc", "-fPIC", "-shared", "-o", str(library_path), str(generated)])
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr

    library, evaluate = load_evaluate(library_path)
    for x, y in [(10.0, 2.0), (-4.0, 3.0), (1.5, -2.5)]:
        expected = (((x - y) / 2.0) + 7.5) * y
        actual = evaluate(x, y)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"alternate program returned {actual}, expected {expected}"
        )
    assert library is not None


def test_test_model_loads_library_calls_evaluate_and_writes_result(tmp_path):
    real_library = os.path.join(WORKSPACE, "libmodel.so")
    saved_library = tmp_path / "saved-libmodel.so"
    probe_source = tmp_path / "probe.c"
    probe_library = tmp_path / "probe.so"
    result_file = os.path.join(WORKSPACE, "result.txt")

    shutil.copy2(real_library, saved_library)
    probe_source.write_text(
        "double evaluate(double x, double y) { return x * 100.0 + y; }\n"
    )
    compiled = run(["gcc", "-fPIC", "-shared", "-o", str(probe_library), str(probe_source)])
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr

    try:
        shutil.copy2(probe_library, real_library)
        if os.path.exists(result_file):
            os.unlink(result_file)
        tested = run(["python3", "test_model.py"])
        assert tested.returncode == 0, tested.stdout + tested.stderr
        assert os.path.isfile(result_file), "test_model.py did not write result.txt"
        with open(result_file) as f:
            probe_result = float(f.read().strip())
        assert probe_result == 304.0, (
            "test_model.py did not load libmodel.so and call evaluate with x=3.0, y=4.0"
        )
    finally:
        shutil.copy2(saved_library, real_library)

    if os.path.exists(result_file):
        os.unlink(result_file)
    tested = run(["python3", "test_model.py"])
    assert tested.returncode == 0, tested.stdout + tested.stderr
    with open(result_file) as f:
        actual = float(f.read().strip())
    assert actual == 29.0, f"Expected rebuilt model result 29.0, got {actual}"


def test_pre_commit_hook_executes_pipeline_and_propagates_failure(tmp_path):
    hook = os.path.join(WORKSPACE, ".git", "hooks", "pre-commit")
    makefile = os.path.join(WORKSPACE, "Makefile")
    saved_makefile = tmp_path / "Makefile.saved"
    shutil.copy2(makefile, saved_makefile)

    try:
        with open(makefile, "w") as f:
            f.write("all:\n\t@false\n")
        failed = run([hook])
    finally:
        shutil.copy2(saved_makefile, makefile)

    assert failed.returncode != 0, "pre-commit hook did not stop when make failed"

    completed = run([hook])
    assert completed.returncode == 0, completed.stdout + completed.stderr
    result_file = os.path.join(WORKSPACE, "result.txt")
    assert os.path.isfile(result_file), "pre-commit hook did not run test_model.py"
    with open(result_file) as f:
        assert float(f.read().strip()) == 29.0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
