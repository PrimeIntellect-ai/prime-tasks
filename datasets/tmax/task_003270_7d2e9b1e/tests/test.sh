#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_libpoly_so_exists():
    assert os.path.isfile("/home/user/libpoly.so"), "Shared library /home/user/libpoly.so is missing."

def test_poly_diff_py_exists():
    assert os.path.isfile("/home/user/poly_diff.py"), "Python script /home/user/poly_diff.py is missing."

def test_poly_diff_result():
    result_file = "/home/user/poly_diff_result.txt"
    assert os.path.isfile(result_file), f"Result file {result_file} is missing."

    with open(result_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["-6,4", "-1,0"]
    assert lines == expected, f"Expected {expected}, but got {lines} in {result_file}"

def test_poly_diff_py_uses_ctypes():
    script_file = "/home/user/poly_diff.py"
    if os.path.isfile(script_file):
        with open(script_file, "r") as f:
            content = f.read()
        assert "ctypes" in content, "Python script does not seem to import/use ctypes."
        assert "Structure" in content, "Python script does not seem to define a ctypes.Structure."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
