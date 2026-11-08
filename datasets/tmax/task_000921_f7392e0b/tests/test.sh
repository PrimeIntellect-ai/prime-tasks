#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import subprocess
import tempfile
import textwrap
import pytest

WORKSPACE = "/home/user/math-ci"
LIBRARY = os.path.join(WORKSPACE, "libmathvm.so")


def run_command(command, *, cwd=WORKSPACE, env=None, timeout=30):
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        pytest.fail(f"Required command was not found: {command[0]}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {' '.join(command)}")


def load_vm(path):
    try:
        library = ctypes.CDLL(path)
    except OSError as exc:
        pytest.fail(f"Could not load shared library {path}: {exc}")
    try:
        evaluate = library.evaluate
    except AttributeError:
        pytest.fail(f"Shared library {path} does not export evaluate")
    evaluate.argtypes = [
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    evaluate.restype = ctypes.c_double
    return library, evaluate


def evaluate_vm(evaluate, opcodes, values):
    opcode_array = (ctypes.c_int * len(opcodes))(*opcodes)
    value_array = (ctypes.c_double * max(1, len(values)))(*(values or [0.0]))
    return evaluate(opcode_array, value_array, len(opcodes))


def assert_vm_behavior(library_path):
    library, evaluate = load_vm(library_path)
    del library  # The function object retains the loaded library.

    rng = random.SystemRandom()
    for _ in range(200):
        a = float(rng.randint(-1000000, 1000000))
        b = float(rng.randint(-1000000, 1000000))
        assert evaluate_vm(evaluate, [1, 1, 3], [a, b]) == a - b
        assert evaluate_vm(evaluate, [1, 1, 2], [a, b]) == a + b

    for _ in range(100):
        a = float(rng.randint(-10000, 10000))
        b = float(rng.randint(-10000, 10000))
        c = float(rng.randint(-10000, 10000))
        opcodes = [1, 1, 3, 1, 2]
        assert evaluate_vm(evaluate, opcodes, [a, b, c]) == (a - b) + c


def test_success_log_exists_and_correct():
    success_log_path = os.path.join(WORKSPACE, "success.log")
    assert os.path.isfile(success_log_path), f"Expected file {success_log_path} does not exist."
    with open(success_log_path, "r") as f:
        content = f.read().strip()
    assert content == "CI_PIPELINE_FIXED", f"Expected success.log to contain exactly 'CI_PIPELINE_FIXED', but got '{content}'."
    with open(success_log_path, "rb") as f:
        assert f.read() == b"CI_PIPELINE_FIXED", "success.log must contain exactly CI_PIPELINE_FIXED with no extra data."


def test_make_builds_working_shared_library():
    for filename in ("libmathvm.so", "vm.o"):
        path = os.path.join(WORKSPACE, filename)
        if os.path.lexists(path):
            os.remove(path)

    result = run_command(["make"])
    assert result.returncode == 0, f"'make' failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} was not built."
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIBRARY} is not an ELF library."
    assert_vm_behavior(LIBRARY)


def test_vm_c_bug_fixed():
    vm_c_path = os.path.join(WORKSPACE, "vm.c")
    assert os.path.isfile(vm_c_path), f"File {vm_c_path} is missing."
    with open(vm_c_path, "r") as f:
        content = f.read()
    assert "a - b" not in content.replace(" ", ""), "The logic bug in vm.c (subtracting in the wrong order) does not appear to be fixed."
    assert "b-a" in content.replace(" ", "") or "-a" in content.replace(" ", ""), "The subtraction logic in vm.c does not appear to reflect the correct order (b - a)."

    with tempfile.TemporaryDirectory() as tempdir:
        direct_library = os.path.join(tempdir, "libvm_from_source.so")
        result = run_command([
            "gcc", "-shared", "-fPIC", "-I", WORKSPACE,
            os.path.join(WORKSPACE, "vm.c"), "-o", direct_library,
        ])
        assert result.returncode == 0, f"vm.c could not be compiled.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        assert_vm_behavior(direct_library)


def test_go_test_passes_with_independent_tests():
    verifier_test = os.path.join(WORKSPACE, "zz_verifier_mathvm_test.go")
    source = textwrap.dedent(r'''
        package mathvm

        import (
            "math/rand"
            "testing"
            "time"
        )

        func TestVerifierMathVMBehavior(t *testing.T) {
            rng := rand.New(rand.NewSource(time.Now().UnixNano()))
            for i := 0; i < 1000; i++ {
                a := float64(rng.Int63n(2000001) - 1000000)
                b := float64(rng.Int63n(2000001) - 1000000)
                c := float64(rng.Int63n(2000001) - 1000000)

                if got, want := Evaluate([]int{OpPush, OpPush, OpSub}, []float64{a, b}), a-b; got != want {
                    t.Fatalf("subtraction: got %v, want %v for %v and %v", got, want, a, b)
                }
                if got, want := Evaluate([]int{OpPush, OpPush, OpAdd}, []float64{a, b}), a+b; got != want {
                    t.Fatalf("addition: got %v, want %v for %v and %v", got, want, a, b)
                }
                if got, want := Evaluate(
                    []int{OpPush, OpPush, OpSub, OpPush, OpAdd},
                    []float64{a, b, c},
                ), (a-b)+c; got != want {
                    t.Fatalf("combined expression: got %v, want %v", got, want)
                }
            }
        }
    ''')
    with open(verifier_test, "w") as f:
        f.write(source)

    env = os.environ.copy()
    current_ld = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = f"{WORKSPACE}:{current_ld}" if current_ld else WORKSPACE

    try:
        result = run_command(["go", "test", "-v"], env=env, timeout=30)
    finally:
        try:
            os.remove(verifier_test)
        except FileNotFoundError:
            pass

    assert result.returncode == 0, f"'go test' failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
