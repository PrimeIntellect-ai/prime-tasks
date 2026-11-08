#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile

WORKDIR = "/home/user/polymath"
CPP_PATH = os.path.join(WORKDIR, "src", "integrate.cpp")
BINARY_PATH = os.path.join(WORKDIR, "bin", "integrate")


def run_and_check(binary, cases):
    for a, b, n in cases:
        result = subprocess.run(
            [binary, str(a), str(b), str(n)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Binary failed for {(a, b, n)}: {result.stderr}"
        )
        output = result.stdout.strip()
        assert len(output.splitlines()) == 1, f"Unexpected output: {output!r}"
        try:
            value = float(output)
        except ValueError:
            raise AssertionError(f"Output is not numeric for {(a, b, n)}: {output!r}")
        expected = (float(b) ** 4 - float(a) ** 4) / 4.0
        assert math.isclose(value, expected, rel_tol=1e-7, abs_tol=6e-5), (
            f"For {(a, b, n)}, expected {expected:.5f}, got {output}"
        )


def generated_cases():
    rng = secrets.SystemRandom()
    cases = [
        (0, 2, 100),
        (0, 1, 2),
        (1, 3, 4),
        (-2, 1, 6),
        (3, -1, 8),
        (-1.5, 2.25, 3),
    ]
    for _ in range(8):
        a = rng.uniform(-3.0, 2.0)
        b = rng.uniform(a + 0.2, 4.0)
        n = rng.choice([2, 3, 4, 5, 6, 8, 10, 12])
        cases.append((a, b, n))
    return cases


def test_cpp_fixed():
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} does not exist"
    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "4.0 : 2.0" not in content or "i % 2 != 0" in content or "i % 2 == 1" in content, \
        "The bug in integrate.cpp does not appear to be fixed correctly."

    # Compile the submitted source independently and exercise cases whose answers
    # are derived by the verifier.
    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "integrate")
        result = subprocess.run(
            ["g++", "-std=c++17", "-Wall", "-Wextra", CPP_PATH, "-o", compiled],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Submitted C++ source does not compile: {result.stderr}"
        run_and_check(compiled, generated_cases())


def test_patch_exists():
    patch_path = os.path.join(WORKDIR, "simpson.patch")
    assert os.path.isfile(patch_path), f"{patch_path} was not created"
    with open(patch_path, "r") as f:
        content = f.read()

    # Preserve the original patch assertions.
    assert "integrate.cpp" in content, "Patch file does not seem to modify integrate.cpp"
    assert "+" in content and "-" in content, "Patch file does not look like a valid diff"

    assert re.search(r"^---\s+.*integrate\.cpp", content, re.MULTILINE), \
        "Patch is missing the original-file header"
    assert re.search(r"^\+\+\+\s+.*integrate\.cpp", content, re.MULTILINE), \
        "Patch is missing the modified-file header"
    assert re.search(r"^@@", content, re.MULTILINE), "Patch has no unified-diff hunk"
    assert re.search(
        r"^-\s*double\s+multiplier\s*=\s*\(i\s*%\s*2\s*==\s*0\)\s*\?\s*4(?:\.0+)?\s*:\s*2(?:\.0+)?\s*;",
        content,
        re.MULTILINE,
    ), "Patch does not remove the buggy coefficient assignment"
    fixed_added = (
        re.search(
            r"^\+\s*double\s+multiplier\s*=\s*\(i\s*%\s*2\s*==\s*0\)\s*\?\s*2(?:\.0+)?\s*:\s*4(?:\.0+)?\s*;",
            content,
            re.MULTILINE,
        )
        or re.search(
            r"^\+\s*double\s+multiplier\s*=\s*\(i\s*%\s*2\s*(?:!=\s*0|==\s*1)\)\s*\?\s*4(?:\.0+)?\s*:\s*2(?:\.0+)?\s*;",
            content,
            re.MULTILINE,
        )
    )
    assert fixed_added, "Patch does not add the corrected Simpson coefficients"


def test_makefile_exists_and_targets():
    makefile_path = os.path.join(WORKDIR, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} was not created"
    with open(makefile_path, "r") as f:
        content = f.read()

    assert re.search(r'^build:', content, re.MULTILINE), "Makefile is missing 'build' target"
    assert re.search(r'^test:', content, re.MULTILINE), "Makefile is missing 'test' target"
    assert re.search(r'^clean:', content, re.MULTILINE), "Makefile is missing 'clean' target"


def test_build_really_compiles_source():
    with open(CPP_PATH, "r") as f:
        original = f.read()
    try:
        with open(CPP_PATH, "a") as f:
            f.write("\n#error verifier_compile_probe\n")
        subprocess.run(["make", "clean"], cwd=WORKDIR, capture_output=True, timeout=20)
        result = subprocess.run(
            ["make", "build"], cwd=WORKDIR, capture_output=True, text=True, timeout=30
        )
        assert result.returncode != 0, \
            "'make build' succeeded with invalid integrate.cpp; it does not compile the required source"
    finally:
        with open(CPP_PATH, "w") as f:
            f.write(original)
        shutil.rmtree(os.path.join(WORKDIR, "bin"), ignore_errors=True)


def test_make_workflow():
    # Preserve and strengthen the original clean/build workflow checks.
    subprocess.run(["make", "clean"], cwd=WORKDIR, capture_output=True, timeout=20)
    assert not os.path.exists(BINARY_PATH), "'make clean' did not remove the binary"

    res_build = subprocess.run(
        ["make", "build"], cwd=WORKDIR, capture_output=True, timeout=30
    )
    assert res_build.returncode == 0, f"'make build' failed: {res_build.stderr.decode()}"
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} was not created by 'make build'"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/integrate is not a compiled native executable"

    res_bin = subprocess.run(
        [BINARY_PATH, "0", "2", "100"], capture_output=True, text=True, timeout=10
    )
    assert res_bin.returncode == 0, "Binary execution failed"
    output = res_bin.stdout.strip()
    assert output == "4.00000", f"Expected binary output '4.00000', got '{output}'"

    run_and_check(BINARY_PATH, generated_cases())


def test_make_test():
    test_path = os.path.join(WORKDIR, "tests", "test_integration.py")
    res_test = subprocess.run(
        ["make", "test"], cwd=WORKDIR, capture_output=True, text=True, timeout=60
    )
    assert res_test.returncode == 0, \
        f"'make test' failed. Output:\n{res_test.stdout}\n{res_test.stderr}"
    assert "pytest" in res_test.stdout or "pytest" in res_test.stderr, \
        "'make test' doesn't seem to invoke pytest"

    # Prove that the target actually collects and runs the required Python suite,
    # rather than merely printing a successful-looking pytest message.
    with open(test_path, "r") as f:
        original = f.read()
    marker = os.path.join(tempfile.gettempdir(), "polymath_pytest_" + secrets.token_hex(12))
    probe = (
        "import os\n"
        "def test_verifier_probe():\n"
        "    with open(os.environ['POLYMATH_PYTEST_MARKER'], 'w') as f:\n"
        "        f.write('executed')\n"
    )
    try:
        with open(test_path, "w") as f:
            f.write(probe)
        env = os.environ.copy()
        env["POLYMATH_PYTEST_MARKER"] = marker
        result = subprocess.run(
            ["make", "test"], cwd=WORKDIR, env=env,
            capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, \
            f"'make test' failed while running the pytest probe: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(marker), \
            "'make test' did not execute tests/test_integration.py through pytest"
        with open(marker, "r") as f:
            assert f.read() == "executed"
    finally:
        with open(test_path, "w") as f:
            f.write(original)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
