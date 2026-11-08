#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import textwrap
import pytest

WORKSPACE_DIR = "/home/user/math-addon"
SRC_DIR = os.path.join(WORKSPACE_DIR, "src")
PACKAGE_JSON = os.path.join(WORKSPACE_DIR, "package.json")
MATH_CPP = os.path.join(SRC_DIR, "math.cpp")
LIBMATH_SO = os.path.join(SRC_DIR, "libmath.so")
SUCCESS_TXT = "/home/user/success.txt"


def test_success_file():
    assert os.path.isfile(SUCCESS_TXT), f"File {SUCCESS_TXT} does not exist. Did you run the test command and redirect the output?"
    with open(SUCCESS_TXT, "r") as f:
        content = f.read()
    assert "All property tests passed!" in content, f"{SUCCESS_TXT} does not contain the expected success message. Tests might have failed."


def test_shared_library():
    assert os.path.isfile(LIBMATH_SO), f"Shared library {LIBMATH_SO} does not exist. Did you compile it?"

    result = subprocess.run(["file", LIBMATH_SO], capture_output=True, text=True)
    assert "shared object" in result.stdout or "dynamically linked" in result.stdout, f"{LIBMATH_SO} does not appear to be a valid shared object."


def test_package_json_fixed():
    assert os.path.isfile(PACKAGE_JSON), f"File {PACKAGE_JSON} does not exist."
    with open(PACKAGE_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{PACKAGE_JSON} is not valid JSON.")

    deps = data.get("devDependencies", {})
    fast_check = deps.get("fast-check", "")
    assert "github:not-a-real-repo/fast-check-broken" not in fast_check, "package.json still contains the broken fast-check dependency."

    all_deps = {}
    all_deps.update(data.get("dependencies", {}))
    all_deps.update(data.get("devDependencies", {}))
    assert all_deps.get("ffi-napi"), "package.json must retain ffi-napi."
    assert all_deps.get("fast-check"), "package.json must retain fast-check."

    node_modules = os.path.join(WORKSPACE_DIR, "node_modules")
    assert os.path.isdir(node_modules), f"node_modules directory not found in {WORKSPACE_DIR}. Did you run npm install?"


def test_math_cpp_fixed():
    assert os.path.isfile(MATH_CPP), f"File {MATH_CPP} does not exist."
    with open(MATH_CPP, "r") as f:
        content = f.read()

    # Preserve the original source assertion; correctness is checked behaviorally below.
    assert "b = b % a;" not in content.replace(" ", ""), "The logical flaw 'b = b % a;' is still present in math.cpp."


def test_makefile_builds_shared_library():
    result = subprocess.run(
        ["make", "clean", "all"],
        cwd=SRC_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Makefile failed to build libmath.so:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(LIBMATH_SO), "Makefile did not produce src/libmath.so."
    result = subprocess.run(["file", LIBMATH_SO], capture_output=True, text=True)
    assert "shared object" in result.stdout or "dynamically linked" in result.stdout, "Makefile output is not a shared object."


def test_fast_gcd_full_uint64_behavior():
    probe = textwrap.dedent(f"""
        import ctypes
        import math
        import secrets

        lib = ctypes.CDLL({LIBMATH_SO!r})
        gcd = lib.fast_gcd
        gcd.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
        gcd.restype = ctypes.c_uint64

        limit = (1 << 64) - 1
        cases = [
            (0, 0), (0, 1), (1, 0), (1, 1), (6, 4), (4, 6),
            (48, 18), (18, 48), (limit, 0), (0, limit),
            (limit, limit), (limit, limit - 1), (1 << 63, 1 << 62),
            ((1 << 64) - 2, (1 << 63) - 1),
        ]
        cases.extend((secrets.randbits(64), secrets.randbits(64)) for _ in range(2000))

        for a, b in cases:
            actual = int(gcd(a, b))
            expected = math.gcd(a, b)
            if actual != expected:
                raise AssertionError(f"fast_gcd({{a}}, {{b}}) returned {{actual}}, expected {{expected}}")
    """)
    result = subprocess.run(
        ["python3", "-c", probe], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"fast_gcd behavioral checks failed:\n{result.stdout}\n{result.stderr}"


def test_installed_node_dependencies_and_ffi():
    probe = r'''
const { createRequire } = require('module');
const req = createRequire('/home/user/math-addon/package.json');
const ffi = req('ffi-napi');
const fc = req('fast-check');
const lib = ffi.Library('/home/user/math-addon/src/libmath.so', {
  fast_gcd: ['uint64', ['uint64', 'uint64']]
});
function expectedGcd(a, b) {
  a = BigInt(a); b = BigInt(b);
  while (b !== 0n) { const t = b; b = a % b; a = t; }
  return a;
}
fc.assert(fc.property(fc.maxSafeNat(), fc.maxSafeNat(), (a, b) => {
  return BigInt(lib.fast_gcd(a, b)) === expectedGcd(a, b);
}), { numRuns: 500 });
'''
    result = subprocess.run(
        ["node", "-e", probe],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Installed Node dependencies or FFI behavior failed:\n{result.stdout}\n{result.stderr}"


def test_npm_test_actually_passes():
    result = subprocess.run(
        ["npm", "test"],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"npm test failed:\n{output}"
    assert "All property tests passed!" in output, f"npm test did not run the expected property tests:\n{output}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
