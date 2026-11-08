#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import shutil
import stat
import subprocess
import sysconfig

WORKSPACE_DIR = "/home/user/workspace"


def clean_extension_artifacts():
    for path in glob.glob(os.path.join(WORKSPACE_DIR, "mathops*.so")):
        os.remove(path)
    shutil.rmtree(os.path.join(WORKSPACE_DIR, "build"), ignore_errors=True)


def run_checked(command, timeout=180):
    result = subprocess.run(
        command,
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    return result


def verify_compiled_module():
    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    candidates = glob.glob(os.path.join(WORKSPACE_DIR, "mathops*.so"))
    assert candidates, "No compiled mathops extension was produced"
    if suffix:
        assert any(path.endswith(suffix) for path in candidates), (
            f"No mathops extension with the expected suffix {suffix!r} was produced"
        )

    cases = [
        [0, 0], [1, 2], [-1, 1], [-1000, -2345], [999999, -123456],
        [271828, 314159],
    ]
    code = r'''
import importlib.machinery
import importlib.util
import json
import mathops
import sys
cases = json.loads(sys.argv[1])
spec = importlib.util.find_spec("mathops")
assert spec is not None and spec.origin
assert isinstance(spec.loader, importlib.machinery.ExtensionFileLoader), spec.loader
for a, b in cases:
    actual = mathops.add(a, b)
    assert actual == a + b, (a, b, actual, a + b)
'''
    run_checked(["python3", "-c", code, json.dumps(cases)])


def test_mathops_c_patched():
    mathops_path = os.path.join(WORKSPACE_DIR, "mathops.c")
    assert os.path.isfile(mathops_path), f"mathops.c missing at {mathops_path}"
    with open(mathops_path, "r") as f:
        content = f.read()
    assert "return a + b;" in content, "mathops.c was not patched correctly (missing 'return a + b;')"
    assert "return a - b; // BUG!" not in content, "mathops.c still contains the bug"


def test_setup_py_fixed():
    setup_path = os.path.join(WORKSPACE_DIR, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py missing at {setup_path}"
    with open(setup_path, "r") as f:
        content = f.read()
    assert "mathops.c" in content, "setup.py was not fixed to use 'mathops.c'"
    assert "wrong_name.c" not in content, "setup.py still contains 'wrong_name.c'"

    clean_extension_artifacts()
    run_checked(["python3", "setup.py", "build_ext", "--inplace"])
    verify_compiled_module()


def test_test_mathops_py_contents_and_behavior():
    test_path = os.path.join(WORKSPACE_DIR, "test_mathops.py")
    assert os.path.isfile(test_path), f"test_mathops.py missing at {test_path}"
    with open(test_path, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "test_mathops.py does not import hypothesis"
    assert "st.integers()" in content, "test_mathops.py does not use st.integers()"
    assert "mathops" in content, "test_mathops.py does not import mathops"
    assert "test_add" in content, "test_mathops.py does not contain test_add function"

    run_checked(["python3", "-m", "pytest", "test_mathops.py"])

    mathops_path = os.path.join(WORKSPACE_DIR, "mathops.c")
    with open(mathops_path, "r") as f:
        original_source = f.read()
    broken_source = original_source.replace("return a + b;", "return a - b;", 1)
    assert broken_source != original_source, "Could not create the verifier's faulty test build"

    try:
        with open(mathops_path, "w") as f:
            f.write(broken_source)
        clean_extension_artifacts()
        run_checked(["python3", "setup.py", "build_ext", "--inplace", "--force"])

        bad_test = subprocess.run(
            ["python3", "-m", "pytest", "test_mathops.py"],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert bad_test.returncode != 0, (
            "test_mathops.py passed against a deliberately broken subtraction implementation; "
            "the property test does not validate addition"
        )
    finally:
        with open(mathops_path, "w") as f:
            f.write(original_source)
        clean_extension_artifacts()
        run_checked(["python3", "setup.py", "build_ext", "--inplace", "--force"])


def test_ci_run_sh_executable_and_successful():
    ci_script_path = os.path.join(WORKSPACE_DIR, "ci_run.sh")
    assert os.path.isfile(ci_script_path), f"ci_run.sh missing at {ci_script_path}"

    st = os.stat(ci_script_path)
    assert bool(st.st_mode & stat.S_IXUSR), "ci_run.sh is not executable"

    with open(ci_script_path, "r") as f:
        ci_content = f.read()
    assert "python3 setup.py build_ext --inplace" in ci_content, (
        "ci_run.sh does not compile the extension in-place with setup.py"
    )
    assert "python3 -m pytest test_mathops.py" in ci_content, (
        "ci_run.sh does not run test_mathops.py with pytest"
    )

    clean_extension_artifacts()
    result = subprocess.run(
        ["./ci_run.sh"],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )

    assert result.returncode == 0, f"ci_run.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    verify_compiled_module()

    test_path = os.path.join(WORKSPACE_DIR, "test_mathops.py")
    with open(test_path, "r") as f:
        original_test = f.read()
    sentinel = "VERIFIER_SENTINEL_CI_MUST_RUN_PYTEST"
    try:
        with open(test_path, "a") as f:
            f.write(
                "\n\ndef test_verifier_ci_sentinel():\n"
                f"    assert False, '{sentinel}'\n"
            )
        failing_result = subprocess.run(
            ["./ci_run.sh"],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=180,
        )
        combined = failing_result.stdout + failing_result.stderr
        assert failing_result.returncode != 0, (
            "ci_run.sh returned success even when test_mathops.py contained a failing test"
        )
        assert sentinel in combined, (
            "ci_run.sh failed without evidence that it actually ran test_mathops.py with pytest"
        )
    finally:
        with open(test_path, "w") as f:
            f.write(original_test)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
