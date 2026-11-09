#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import subprocess

PROJECT = "/home/user/math_project"
LIB_PATH = os.path.join(PROJECT, "lib/libfib.so")
RESULT_FILE = "/home/user/result.txt"

def fib_mod(n, mod=1000000007):
    if n == 0:
        return 0
    a, b = 0, 1
    for _ in range(2, n + 1):
        a, b = b, (a + b) % mod
    return b

def test_result_file():
    assert os.path.exists(RESULT_FILE), f"{RESULT_FILE} does not exist. The Go program may not have run successfully."

    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()

    expected_sum = (fib_mod(100000) + fib_mod(200000) + fib_mod(300000)) % 1000000007
    assert content == str(expected_sum), f"Expected result {expected_sum}, but got {content} in {RESULT_FILE}"

def test_shared_library_exists():
    assert os.path.exists(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Makefile might not be fixed correctly."

    result = subprocess.run(["file", LIB_PATH], capture_output=True, text=True)
    assert "shared object" in result.stdout, f"{LIB_PATH} is not a valid shared object. Output of file command: {result.stdout}"

def test_shared_library_implements_fib_mod():
    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, "fib_mod"), "libfib.so does not export fib_mod"
    lib.fib_mod.argtypes = [ctypes.c_int]
    lib.fib_mod.restype = ctypes.c_ulonglong

    rng = random.Random(847231)
    inputs = [0, 1, 2, 3, 10, 100, 1000, 9999]
    inputs.extend(rng.randrange(4, 50000) for _ in range(12))
    for n in inputs:
        actual = lib.fib_mod(n)
        expected = fib_mod(n)
        assert actual == expected, f"fib_mod({n}) returned {actual}, expected {expected}"

def test_main_go_fixed():
    main_go = os.path.join(PROJECT, "main.go")
    assert os.path.exists(main_go), f"{main_go} is missing."
    with open(main_go, "r") as f:
        content = f.read()

    assert "wrong_include" not in content, "main.go still contains 'wrong_include'."
    assert "wrong_lib" not in content, "main.go still contains 'wrong_lib'."

    assert "-I${SRCDIR}/include" in content or "-Iinclude" in content or "-I/home/user/math_project/include" in content, "main.go does not correctly reference the include directory."
    assert "-L${SRCDIR}/lib" in content or "-Llib" in content or "-L/home/user/math_project/lib" in content, "main.go does not correctly reference the lib directory."
TEST_EOF

if (
    set -e
    cd /home/user/math_project
    rm -f lib/libfib.so src/fib.o
    timeout 60 make
    test -f lib/libfib.so
    rm -f /tmp/math_project_app
    CGO_ENABLED=1 timeout 120 go build -o /tmp/math_project_app main.go
    test -x /tmp/math_project_app
    rm -f /home/user/result.txt
    LD_LIBRARY_PATH=/home/user/math_project/lib timeout 60 /tmp/math_project_app
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
