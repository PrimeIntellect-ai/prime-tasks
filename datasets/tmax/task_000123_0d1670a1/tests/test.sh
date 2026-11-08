#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import tempfile
import uuid
import pytest

SOURCE = "/home/user/filter_elf.cpp"
BINARY = "/home/user/filter_elf"


def test_cpp_source_exists():
    path = SOURCE
    assert os.path.isfile(path), f"C++ source file {path} does not exist."


def test_cpp_binary_exists_and_executable():
    path = BINARY
    assert os.path.isfile(path), f"Compiled binary {path} does not exist."
    assert os.stat(path).st_mode & stat.S_IXUSR, f"Compiled binary {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled binary {path} is not an ELF executable."


def test_source_compiles():
    rebuilt = os.path.join(tempfile.gettempdir(), "filter_elf_rebuilt_" + uuid.uuid4().hex)
    result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"
    os.environ["REBUILT_FILTER_ELF"] = rebuilt


def exercise_filter(program):
    with tempfile.TemporaryDirectory(prefix="filter_elf_cases_") as directory:
        token = uuid.uuid4().hex
        cases = [
            (f"valid elf {token}", b"\x7fELF" + os.urandom(37), True),
            (f"also_valid_{token}", b"\x7fELF" + os.urandom(11), True),
            (f"wrong_magic_{token}", b"NOPE" + os.urandom(19), False),
            (f"almost_elf_{token}", b"\x7fELX" + os.urandom(13), False),
            (f"short_{token}", b"\x7fEL", False),
            (f"empty_{token}", b"", False),
        ]
        paths = []
        expected = []
        for name, contents, valid in cases:
            path = os.path.abspath(os.path.join(directory, name))
            with open(path, "wb") as f:
                f.write(contents)
            paths.append(path)
            if valid:
                expected.append(path)

        missing = os.path.join(directory, "missing_" + token)
        input_paths = [paths[2], paths[0], missing, paths[4], paths[1], paths[3], paths[5]]
        expected_in_input_order = [paths[0], paths[1]]
        result = subprocess.run(
            [program],
            input="".join(path + "\n" for path in input_paths),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{program} exited with {result.returncode}. stderr: {result.stderr}"
        )
        assert result.stdout.splitlines() == expected_in_input_order, (
            f"{program} did not filter paths by their first four ELF magic bytes. "
            f"Expected {expected_in_input_order}, got {result.stdout.splitlines()}"
        )

        empty_result = subprocess.run(
            [program], input="", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert empty_result.returncode == 0
        assert empty_result.stdout == "", f"{program} produced output for empty input."


def test_submitted_binary_filters_elf_headers():
    exercise_filter(BINARY)


def test_cpp_source_implements_filter():
    rebuilt = os.environ.get("REBUILT_FILTER_ELF")
    if not rebuilt or not os.path.isfile(rebuilt):
        rebuilt = os.path.join(tempfile.gettempdir(), "filter_elf_rebuilt_" + uuid.uuid4().hex)
        result = subprocess.run(
            ["g++", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"
    exercise_filter(rebuilt)


def test_curated_list_output():
    path = "/home/user/curated_list.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "backend_api-curated",
        "service_worker-curated"
    ]

    assert lines == expected_lines, (
        f"Contents of {path} do not match the expected output. "
        f"Expected: {expected_lines}, but got: {lines}"
    )


def test_curated_list_is_sorted():
    path = "/home/user/curated_list.txt"
    if not os.path.isfile(path):
        pytest.fail(f"Output file {path} does not exist.")

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == sorted(lines), f"The output file {path} is not sorted alphabetically."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
