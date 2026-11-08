#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import re
import stat
import subprocess

WORKSPACE = "/home/user/math_migration"
LIB_PATH = os.path.join(WORKSPACE, "libmathops.so")


def run(cmd, *, cwd=WORKSPACE, timeout=120):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def test_libmathops_so_exists():
    path = LIB_PATH
    assert os.path.isfile(path), f"File {path} does not exist. Makefile was not fixed or run properly."

    # Check if it's an ELF file
    with open(path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{path} is not a valid ELF file."


def test_pytest_results_log():
    path = os.path.join(WORKSPACE, "pytest_results.log")
    assert os.path.isfile(path), f"File {path} does not exist. Pytest was not run or output not redirected."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check for "passed" in the output (usually "2 passed" or similar)
    assert re.search(r"\b\d+ passed\b", content), "pytest_results.log does not indicate successful test passes."


def test_version_log():
    path = os.path.join(WORKSPACE, "version.log")
    assert os.path.isfile(path), f"File {path} does not exist. check_version.sh was not run or failed."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content.strip() == "VERSION_OK", f"version.log content is incorrect. Expected 'VERSION_OK', got '{content.strip()}'."


def test_check_version_sh():
    path = os.path.join(WORKSPACE, "check_version.sh")
    assert os.path.isfile(path), f"File {path} does not exist."

    # Check executable permission
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original check.
    assert "sort -V" in content or "sort -t" in content, "check_version.sh does not seem to use 'sort -V' or 'sort -t.' for version comparison."
    assert "sort -V" in content, "check_version.sh must use coreutils sort -V."
    assert "ctypes" in content and "get_version" in content, "check_version.sh must obtain get_version() through inline Python ctypes code."
    assert re.search(r"\bpython3?\b", content), "check_version.sh does not invoke Python."


def test_make_rebuilds_and_library_exports_work():
    makefile = os.path.join(WORKSPACE, "Makefile")
    assert os.path.isfile(makefile), "Makefile is missing."
    with open(makefile, "r", encoding="utf-8") as f:
        make_text = f.read()
    assert "mathops.c" in make_text, "Makefile does not build mathops.c."
    assert "-shared" in make_text, "Makefile is missing the shared-library compiler flag."
    assert re.search(r"-fpic\b", make_text, re.IGNORECASE), "Makefile is missing the position-independent-code compiler flag."

    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)
    result = run(["make", "-B"])
    assert result.returncode == 0, f"make failed:\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), "make did not create libmathops.so."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not create an ELF shared library."

    try:
        lib = ctypes.CDLL(LIB_PATH)
        add = lib.add_safe
        multiply = lib.multiply_safe
        get_version = lib.get_version
    except (OSError, AttributeError) as exc:
        raise AssertionError(f"The shared library cannot be loaded with the required exports: {exc}")

    add.argtypes = [ctypes.c_int, ctypes.c_int]
    add.restype = ctypes.c_int
    multiply.argtypes = [ctypes.c_int, ctypes.c_int]
    multiply.restype = ctypes.c_int
    get_version.argtypes = []
    get_version.restype = ctypes.c_char_p

    pairs = [(-1000, -1000), (-1000, 1000), (0, 0), (1, -1), (1000, 1000)]
    rng = random.Random(87321)
    pairs.extend((rng.randint(-1000, 1000), rng.randint(-1000, 1000)) for _ in range(250))
    for a, b in pairs:
        assert add(a, b) == a + b, f"add_safe({a}, {b}) returned the wrong result."
        assert multiply(a, b) == a * b, f"multiply_safe({a}, {b}) returned the wrong result."

    assert get_version() == b"2.1.4", "get_version() did not return the supplied library version."


def test_submitted_hypothesis_tests_are_real_and_pass():
    path = os.path.join(WORKSPACE, "test_mathops.py")
    assert os.path.isfile(path), "test_mathops.py is missing."
    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=path)

    assert "ctypes" in source and "libmathops.so" in source, "test_mathops.py must load libmathops.so using ctypes."
    assert "hypothesis" in source, "test_mathops.py must use Hypothesis."
    assert "add_safe" in source and "multiply_safe" in source, "Both required C functions must be exposed and tested."

    bounded_strategy = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else (node.func.id if isinstance(node.func, ast.Name) else "")
        if name != "integers":
            continue
        values = {}
        for kw in node.keywords:
            if kw.arg in ("min_value", "max_value"):
                try:
                    values[kw.arg] = ast.literal_eval(kw.value)
                except Exception:
                    pass
        if values.get("min_value") == -1000 and values.get("max_value") == 1000:
            bounded_strategy = True
    assert bounded_strategy, "Hypothesis integer strategies must cover exactly -1000 through 1000."

    property_tests = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            decorators = []
            for dec in node.decorator_list:
                try:
                    decorators.append(ast.unparse(dec))
                except Exception:
                    decorators.append("")
            if any(re.search(r"\bgiven\b", dec) for dec in decorators):
                property_tests.append(node)
    assert len(property_tests) >= 2, "At least two Hypothesis @given property tests are required."

    has_native_add = any(isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add) for fn in property_tests for n in ast.walk(fn))
    has_native_multiply = any(isinstance(n, ast.BinOp) and isinstance(n.op, ast.Mult) for fn in property_tests for n in ast.walk(fn))
    assert has_native_add, "A property test must compare addition with native Python +."
    assert has_native_multiply, "A property test must compare multiplication with native Python *."

    result = run(["python3", "-m", "pytest", path, "-x", "--tb=short"], timeout=180)
    with open(os.path.join(WORKSPACE, "pytest_results.log"), "w", encoding="utf-8") as f:
        f.write(result.stdout)
    assert result.returncode == 0, f"Submitted property tests failed:\n{result.stdout}"
    match = re.search(r"\b(\d+) passed\b", result.stdout)
    assert match and int(match.group(1)) >= 2, f"Submitted pytest run did not execute two passing tests:\n{result.stdout}"


def test_version_script_uses_library_value_semantically():
    script = os.path.join(WORKSPACE, "check_version.sh")
    with open(LIB_PATH, "rb") as f:
        original_library = f.read()
    original_mode = stat.S_IMODE(os.stat(LIB_PATH).st_mode)
    variant_source = "/tmp/mathops_version_variant.c"

    try:
        for version, expected in (("1.99.99", "VERSION_TOO_OLD"), ("2.0.0", "VERSION_OK"), ("10.0.0", "VERSION_OK")):
            with open(variant_source, "w", encoding="utf-8") as f:
                f.write(
                    '#include <stdio.h>\n'
                    'int add_safe(int a, int b) { return a + b; }\n'
                    'int multiply_safe(int a, int b) { return a * b; }\n'
                    f'const char* get_version(void) {{ return "{version}"; }}\n'
                )
            compiled = run(["gcc", "-shared", "-fPIC", "-o", LIB_PATH, variant_source])
            assert compiled.returncode == 0, f"Could not build verifier version fixture:\n{compiled.stdout}"
            log_path = os.path.join(WORKSPACE, "version.log")
            if os.path.exists(log_path):
                os.remove(log_path)
            result = run([script])
            assert result.returncode == 0, f"check_version.sh failed for version {version}:\n{result.stdout}"
            assert os.path.isfile(log_path), "check_version.sh did not create version.log."
            with open(log_path, "r", encoding="utf-8") as f:
                actual = f.read().strip()
            assert actual == expected, f"For version {version}, expected {expected}, got {actual}."
    finally:
        with open(LIB_PATH, "wb") as f:
            f.write(original_library)
        os.chmod(LIB_PATH, original_mode)
        if os.path.exists(variant_source):
            os.remove(variant_source)

    final = run([script])
    assert final.returncode == 0, f"check_version.sh failed with the submitted library:\n{final.stdout}"
    with open(os.path.join(WORKSPACE, "version.log"), "r", encoding="utf-8") as f:
        assert f.read().strip() == "VERSION_OK"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
