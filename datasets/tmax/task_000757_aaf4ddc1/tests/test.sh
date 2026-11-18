#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/data_processor")
DATA = PROJECT / "data.csv"
SOURCE = PROJECT / "main.cpp"
MAKEFILE = PROJECT / "Makefile"
BINARY = PROJECT / "process_data"
RESULT = Path("/home/user/result.txt")

EXPECTED_DATA = "id,name,score\n1,Alice,45\n2,Bob,85\n3,Charlie,90\n4,Dave,60"


def normalized(text):
    return "\n".join(line.strip() for line in text.splitlines() if line.strip())


def assert_result(expected):
    assert RESULT.is_file(), f"File {RESULT} does not exist. The program may not have run successfully."
    content = RESULT.read_text().strip()
    assert content == f"Average: {expected}", f"Expected content 'Average: {expected}', but got '{content}'"


def assert_elf_executable(path):
    assert path.is_file(), f"Expected executable {path} was not created."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    assert path.read_bytes()[:4] == b"\x7fELF", f"{path} is not a compiled ELF executable."


def run_and_check(binary, expected):
    if RESULT.exists():
        RESULT.unlink()
    completed = subprocess.run(
        [str(binary)], cwd=PROJECT, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{binary} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert_result(expected)


def test_result_txt_exists_and_correct():
    assert_result(78)


def test_data_csv_unmodified():
    assert DATA.is_file(), f"File {DATA} is missing."
    assert normalized(DATA.read_text()) == normalized(EXPECTED_DATA), (
        "The data.csv file was modified, which violates the requirements."
    )


def test_project_builds_and_program_computes_results():
    assert MAKEFILE.is_file(), "The required Makefile is missing."
    assert SOURCE.is_file(), "The required C++ source file main.cpp is missing."

    original_data = DATA.read_bytes()
    source_binary = Path("/tmp/source_process_data")

    try:
        if BINARY.exists() or BINARY.is_symlink():
            if BINARY.is_dir() and not BINARY.is_symlink():
                shutil.rmtree(BINARY)
            else:
                BINARY.unlink()

        built = subprocess.run(
            ["make", "-B"], cwd=PROJECT, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert built.returncode == 0, (
            f"Makefile build failed with status {built.returncode}.\n"
            f"stdout:\n{built.stdout}\nstderr:\n{built.stderr}"
        )
        assert DATA.read_bytes() == original_data, "The build modified data.csv."
        assert_elf_executable(BINARY)

        if source_binary.exists():
            source_binary.unlink()
        compiled = subprocess.run(
            ["g++", "-g", str(SOURCE), "-o", str(source_binary)],
            cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert compiled.returncode == 0, (
            f"main.cpp does not compile successfully.\n"
            f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
        )
        assert_elf_executable(source_binary)

        # Both the Makefile-produced artifact and a direct build of main.cpp
        # must process the original data correctly.
        DATA.write_bytes(original_data)
        run_and_check(BINARY, 78)
        DATA.write_bytes(original_data)
        run_and_check(source_binary, 78)

        # Exercise fresh data whose expected answer is derived by the verifier.
        while True:
            high_scores = [51 + secrets.randbelow(49) for _ in range(3)]
            expected = sum(high_scores) // len(high_scores)
            if expected != 78:
                break
        low_score = secrets.randbelow(51)
        generated = (
            "id,name,score\n"
            f"11,North,{low_score}\n"
            f"12,East,{high_scores[0]}\n"
            f"13,South,{high_scores[1]}\n"
            f"14,West,{high_scores[2]}\n"
        )

        for executable in (BINARY, source_binary):
            DATA.write_text(generated)
            run_and_check(executable, expected)

        # Leave the required data and final result in their requested state.
        DATA.write_bytes(original_data)
        run_and_check(BINARY, 78)
        assert DATA.read_bytes() == original_data, "The executable modified data.csv."
    finally:
        DATA.write_bytes(original_data)
        if source_binary.exists():
            source_binary.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
