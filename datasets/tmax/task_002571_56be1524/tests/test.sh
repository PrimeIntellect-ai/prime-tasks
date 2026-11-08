#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import secrets
import pytest

PIPELINE_DIR = "/home/user/pipeline"
C_FILE = os.path.join(PIPELINE_DIR, "calc_interp.c")
PY_FILE = os.path.join(PIPELINE_DIR, "run_data.py")
CSV_FILE = os.path.join(PIPELINE_DIR, "data.csv")
CI_SCRIPT = os.path.join(PIPELINE_DIR, "ci_build.sh")
CI_LOG = os.path.join(PIPELINE_DIR, "ci_output.log")
EXECUTABLE = os.path.join(PIPELINE_DIR, "calc_interp")


def test_c_file_fixed():
    assert os.path.isfile(C_FILE), f"File {C_FILE} is missing."
    with open(C_FILE, "r") as f:
        content = f.read()

    assert "a + b" in content, f"The C file {C_FILE} does not seem to have 'a + b' to fix the addition bug."


def test_ci_build_script_exists_and_executable():
    assert os.path.isfile(CI_SCRIPT), f"CI script {CI_SCRIPT} is missing."
    st = os.stat(CI_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI script {CI_SCRIPT} is not executable."


def test_ci_output_log_correct():
    assert os.path.isfile(CI_LOG), f"Output log {CI_LOG} is missing. Did you run the CI script?"
    with open(CI_LOG, "r") as f:
        content = f.read().strip()

    expected_output = "Result: 25\nResult: 20\nResult: 58"
    assert content == expected_output, f"The contents of {CI_LOG} do not match the expected output.\nExpected:\n{expected_output}\nGot:\n{content}"


def test_python_script_is_python3():
    assert os.path.isfile(PY_FILE), f"File {PY_FILE} is missing."
    try:
        subprocess.check_call(["python3", "-m", "py_compile", PY_FILE])
    except subprocess.CalledProcessError:
        pytest.fail(f"The script {PY_FILE} is not valid Python 3 code.")


def test_executable_compiled():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. The CI script should compile it."
    st = os.stat(EXECUTABLE)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {EXECUTABLE} is not executable."


def run_ci():
    result = subprocess.run(
        [CI_SCRIPT],
        cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"ci_build.sh failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_lines(cases):
    values = []
    for op, a, b in cases:
        if op == "+":
            value = a + b
        elif op == "-":
            value = a - b
        else:
            value = a * b
        values.append(f"Result: {value}")
    return "\n".join(values)


def test_artifacts_and_ci_behave_on_derived_inputs():
    with open(CSV_FILE, "rb") as f:
        original_csv = f.read()

    original_expected = "Result: 25\nResult: 20\nResult: 58"

    # Force the CI script to create both artifacts rather than accepting stale files.
    for path in (EXECUTABLE, CI_LOG):
        if os.path.lexists(path):
            os.remove(path)
    run_ci()

    assert os.path.isfile(EXECUTABLE), "ci_build.sh did not create calc_interp."
    assert os.access(EXECUTABLE, os.X_OK), "The generated calc_interp is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc_interp is not a compiled ELF executable."
    assert os.path.isfile(CI_LOG), "ci_build.sh did not create ci_output.log."
    with open(CI_LOG, "r") as f:
        assert f.read().strip() == original_expected

    # Exercise the compiled interpreter directly using values unavailable to the agent.
    direct_cases = [
        ("+", secrets.randbelow(2001) - 1000, secrets.randbelow(2001) - 1000),
        ("-", secrets.randbelow(2001) - 1000, secrets.randbelow(2001) - 1000),
        ("*", secrets.randbelow(101) - 50, secrets.randbelow(101) - 50),
    ]
    for op, a, b in direct_cases:
        result = subprocess.run(
            [EXECUTABLE, op, str(a), str(b)],
            cwd=PIPELINE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, f"calc_interp failed for {op},{a},{b}: {result.stderr}"
        assert result.stdout == expected_lines([(op, a, b)]) + "\n"

    # Exercise run_data.py independently with a generated CSV.
    generated_csv = os.path.join(PIPELINE_DIR, ".verifier_data.csv")
    py_cases = [
        ("+", secrets.randbelow(4001) - 2000, secrets.randbelow(4001) - 2000),
        ("*", secrets.randbelow(81) - 40, secrets.randbelow(81) - 40),
        ("-", secrets.randbelow(4001) - 2000, secrets.randbelow(4001) - 2000),
    ]
    try:
        with open(generated_csv, "w") as f:
            for op, a, b in py_cases:
                f.write(f"{op},{a},{b}\n")
        result = subprocess.run(
            ["python3", PY_FILE, generated_csv],
            cwd=PIPELINE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"run_data.py failed: {result.stderr}"
        assert result.stdout.strip() == expected_lines(py_cases)
    finally:
        if os.path.exists(generated_csv):
            os.remove(generated_csv)

    # Replace data.csv temporarily and rerun CI, proving that the script really
    # builds and runs the pipeline rather than writing the known sample output.
    ci_cases = [
        ("+", secrets.randbelow(6001) - 3000, secrets.randbelow(6001) - 3000),
        ("*", secrets.randbelow(61) - 30, secrets.randbelow(61) - 30),
        ("-", secrets.randbelow(6001) - 3000, secrets.randbelow(6001) - 3000),
    ]
    try:
        with open(CSV_FILE, "w") as f:
            for op, a, b in ci_cases:
                f.write(f"{op},{a},{b}\n")
        for path in (EXECUTABLE, CI_LOG):
            if os.path.lexists(path):
                os.remove(path)
        run_ci()
        assert os.path.isfile(EXECUTABLE), "CI did not rebuild calc_interp."
        with open(EXECUTABLE, "rb") as f:
            assert f.read(4) == b"\x7fELF", "CI did not produce a compiled executable."
        with open(CI_LOG, "r") as f:
            assert f.read().strip() == expected_lines(ci_cases)
    finally:
        with open(CSV_FILE, "wb") as f:
            f.write(original_csv)
        run_ci()

    with open(CI_LOG, "r") as f:
        assert f.read().strip() == original_expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
