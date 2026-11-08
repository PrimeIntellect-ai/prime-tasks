#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/math_project")


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def assert_elf_executable(path):
    assert path.exists(), "The 'calculate' executable was not built."
    assert path.is_file(), "The 'calculate' executable is not a regular file."
    assert os.access(path, os.X_OK), "The 'calculate' file is not executable."
    assert path.read_bytes()[:4] == b"\x7fELF", "The build did not produce a compiled executable."


def check_calculation(executable, values, input_path):
    input_path.write_text("".join(f"{value:.6f}\n" for value in values))
    completed = subprocess.run(
        [str(executable), str(input_path)],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, f"calculate failed: {completed.stderr}"
    expected = f"Sum: {sum(math.sqrt(value) for value in values):.2f}"
    assert completed.stdout.strip() == expected, (
        f"calculate produced {completed.stdout.strip()!r}; expected {expected!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_run_project():
    build_script = PROJECT_DIR / "build.sh"
    run_script = PROJECT_DIR / "run_math.sh"
    executable = PROJECT_DIR / "calculate"
    result_file = PROJECT_DIR / "result.txt"

    assert build_script.is_file(), "build.sh is missing."
    assert os.access(build_script, os.X_OK), "build.sh is not executable."
    assert run_script.is_file(), "run_math.sh is missing."
    assert os.access(run_script, os.X_OK), "run_math.sh is not executable."

    remove_path(executable)
    remove_path(result_file)

    built = subprocess.run(
        ["./build.sh"], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert built.returncode == 0, f"build.sh failed: {built.stderr}"
    assert_elf_executable(executable)

    # Force run_math.sh to perform a fresh build and create a fresh result.
    remove_path(executable)
    run = subprocess.run(
        ["./run_math.sh"], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert run.returncode == 0, f"run_math.sh failed: {run.stderr}"
    assert_elf_executable(executable)

    # Compile calculate.c independently so behavior cannot be supplied only by
    # a replacement build artifact or by run_math.sh.
    temp_dir = tempfile.TemporaryDirectory()
    source_executable = Path(temp_dir.name) / "calculate_from_source"
    compiled = subprocess.run(
        ["gcc", "-g", str(PROJECT_DIR / "calculate.c"), "-o", str(source_executable), "-lm"],
        cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert compiled.returncode == 0, f"calculate.c does not compile: {compiled.stderr}"
    assert_elf_executable(source_executable)

    yield executable, source_executable, Path(temp_dir.name)
    temp_dir.cleanup()


def test_data_txt_recovered():
    data_file = PROJECT_DIR / "data.txt"
    assert data_file.exists(), "data.txt was not recovered."
    assert data_file.is_file(), "data.txt is not a file."

    content = data_file.read_text().strip().split()
    expected = ["4", "9", "16", "25", "36", "49", "64", "81", "100", "144"]
    assert content == expected, "data.txt does not contain the expected original data."


def test_result_txt_correct():
    result_file = PROJECT_DIR / "result.txt"
    assert result_file.exists(), "result.txt was not created. Did you run ./run_math.sh?"
    assert result_file.is_file(), "result.txt is not a file."

    content = result_file.read_text().strip()
    assert content == "Sum: 66.00", f"result.txt contains incorrect output: expected 'Sum: 66.00', got '{content}'"


def test_executable_exists():
    executable = PROJECT_DIR / "calculate"
    assert executable.exists(), "The 'calculate' executable was not built."
    assert os.access(executable, os.X_OK), "The 'calculate' file is not executable."


def test_built_and_source_programs_on_derived_input(build_and_run_project):
    executable, source_executable, temp_dir = build_and_run_project
    rng = secrets.SystemRandom()
    values = [rng.randint(1, 100000000) / 10000.0 for _ in range(19)]
    check_calculation(executable, values, temp_dir / "dynamic-built.txt")
    check_calculation(source_executable, values, temp_dir / "dynamic-source.txt")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
