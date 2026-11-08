#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

REPO = "/home/user/math_server"
TEST_SOURCE = os.path.join(REPO, "test.c")
RUN_TEST = os.path.join(REPO, "run_test")


def test_resolution_txt():
    path = "/home/user/resolution.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    expected = "SECRET: PROD_MATH_88492_XYZ\nCRASH_INPUTS: -2147483648, -1"
    assert content == expected, f"Content of {path} does not match expected output. Got:\n{content}"


def test_run_test_executable():
    path = RUN_TEST
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."

    result = subprocess.run([path], capture_output=True, timeout=5)
    assert result.returncode == 0, f"Executing {path} returned non-zero exit code: {result.returncode}"


def test_regression_test_source():
    assert os.path.isfile(TEST_SOURCE), f"File {TEST_SOURCE} does not exist."
    with open(TEST_SOURCE, "r") as f:
        source = f.read()

    include_pattern = re.compile(
        r'^\s*#\s*include\s*[<"][^">]*math_ops\.c[>"]\s*$', re.MULTILINE
    )
    assert include_pattern.search(source), "test.c must include math_ops.c."

    # Compile the submitted source itself against the repaired implementation.
    rebuilt = "/tmp/rebuilt_run_test"
    compile_res = subprocess.run(
        ["gcc", TEST_SOURCE, "-o", rebuilt],
        cwd=REPO,
        capture_output=True,
        timeout=10,
    )
    assert compile_res.returncode == 0, (
        "Failed to compile test.c:\n" + compile_res.stderr.decode(errors="replace")
    )
    run_res = subprocess.run([rebuilt], capture_output=True, timeout=5)
    assert run_res.returncode == 0, "The executable compiled from test.c did not pass."

    # Replace only the included implementation in isolated builds. This verifies
    # that test.c calls gcd with the captured inputs and returns exactly 0 for -1
    # and exactly 1 for a different result.
    shadow_source = include_pattern.sub('#include "math_ops.c"', source, count=1)

    def compile_and_run(stub):
        with tempfile.TemporaryDirectory(prefix="verify_regression_") as tempdir:
            shadow_test = os.path.join(tempdir, "test.c")
            shadow_math = os.path.join(tempdir, "math_ops.c")
            shadow_binary = os.path.join(tempdir, "run_test")
            with open(shadow_test, "w") as f:
                f.write(shadow_source)
            with open(shadow_math, "w") as f:
                f.write(stub)
            result = subprocess.run(
                ["gcc", shadow_test, "-I", tempdir, "-o", shadow_binary],
                cwd=tempdir,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                "Failed to compile isolated test.c:\n"
                + result.stderr.decode(errors="replace")
            )
            return subprocess.run([shadow_binary], capture_output=True, timeout=5).returncode

    correct_call_stub = """
int gcd(int a, int b) {
    if (a == (-2147483647 - 1) && b == -1) return -1;
    return 123;
}
"""
    assert compile_and_run(correct_call_stub) == 0, (
        "test.c must call gcd(-2147483648, -1) and return 0 when it returns -1."
    )

    failure_stub = """
int gcd(int a, int b) {
    (void)a;
    (void)b;
    return 123;
}
"""
    assert compile_and_run(failure_stub) == 1, (
        "test.c must return 1 when gcd does not return -1."
    )


def test_math_ops_logic():
    # Compile our own test against math_ops.c to verify the logic directly
    c_code = """
    #include <stdio.h>
    #include "math_ops.c"
    int main() {
        int res = gcd(-2147483648, -1);
        if (res == -1) return 0;
        return 1;
    }
    """
    test_file = "/tmp/verify_math_ops.c"
    out_binary = "/tmp/verify_math_ops"
    with open(test_file, "w") as f:
        f.write(c_code)

    compile_res = subprocess.run(
        ["gcc", test_file, "-o", out_binary, "-I/home/user/math_server"],
        cwd="/home/user/math_server",
        capture_output=True,
    )
    assert compile_res.returncode == 0, f"Failed to compile math_ops.c with test harness:\n{compile_res.stderr.decode()}"

    run_res = subprocess.run([out_binary], capture_output=True)
    assert run_res.returncode == 0, "gcd(-2147483648, -1) did not return -1 as required."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
