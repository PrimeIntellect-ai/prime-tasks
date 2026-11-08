#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest

SOURCE = "/home/user/coauthor_query.cpp"
EXECUTABLE = "/home/user/coauthor_query"
REBUILT = "/tmp/coauthor_query_rebuilt"
RESEARCHERS = "/home/user/researchers.csv"
AUTHORSHIP = "/home/user/authorship.csv"


def test_cpp_source_exists():
    file_path = SOURCE
    assert os.path.isfile(file_path), f"C++ source file {file_path} does not exist."


def test_executable_exists():
    file_path = EXECUTABLE
    assert os.path.isfile(file_path), f"Executable {file_path} does not exist."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {file_path} is not a compiled executable."


def test_json_output():
    file_path = "/home/user/coauthors.json"
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {file_path} as JSON: {e}")

    expected = [
        {"name": "Dr. Alonzo Church"},
        {"name": "Dr. Claude Shannon"},
        {"name": "Dr. John von Neumann"}
    ]

    assert data == expected, f"JSON output mismatch. Expected {expected}, got {data}"


def derive_expected(target):
    researchers = []
    with open(RESEARCHERS, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if line:
                researcher_id, name = line.split(",", 1)
                researchers.append((researcher_id, name))

    authorship = []
    with open(AUTHORSHIP, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if line:
                researcher_id, paper_id = line.split(",", 1)
                authorship.append((researcher_id, paper_id))

    target_ids = {rid for rid, name in researchers if name == target}
    target_papers = {paper for rid, paper in authorship if rid in target_ids}
    coauthor_ids = {
        rid for rid, paper in authorship
        if paper in target_papers and rid not in target_ids
    }
    names = sorted({name for rid, name in researchers if rid in coauthor_ids})
    return [{"name": name} for name in names]


def run_and_check(binary, target):
    result = subprocess.run(
        [binary, target], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, (
        f"{binary} failed for {target!r}: {result.stderr}"
    )
    try:
        actual = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        pytest.fail(f"{binary} emitted invalid JSON for {target!r}: {e}; output={result.stdout!r}")
    expected = derive_expected(target)
    assert actual == expected, (
        f"Wrong result from {binary} for {target!r}. Expected {expected}, got {actual}"
    )


def check_argument_handling(binary):
    no_args = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert no_args.returncode != 0, f"{binary} must reject calls with no researcher argument"

    extra_args = subprocess.run(
        [binary, "Dr. Alan Turing", "extra"], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert extra_args.returncode != 0, f"{binary} must reject calls with more than one argument"


def test_compilation_and_program_behavior():
    build = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", REBUILT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"C++ source failed to compile: {build.stderr}"

    # Exercise both the submitted executable and a fresh build of the submitted source.
    for binary in (EXECUTABLE, REBUILT):
        run_and_check(binary, "Dr. Alan Turing")
        run_and_check(binary, "Dr. Grace Hopper")
        check_argument_handling(binary)

    with open(RESEARCHERS, "rb") as f:
        original_researchers = f.read()
    with open(AUTHORSHIP, "rb") as f:
        original_authorship = f.read()

    try:
        with open(RESEARCHERS, "w", encoding="utf-8") as f:
            f.write(
                "10,Zeta Target\n"
                "11,Amy Alpha\n"
                "12,Mona Mid\n"
                "13,No Share\n"
                "14,Beta Other\n"
            )
        with open(AUTHORSHIP, "w", encoding="utf-8") as f:
            f.write(
                "10,500\n"
                "11,500\n"
                "10,501\n"
                "12,501\n"
                "11,501\n"
                "10,502\n"
                "10,502\n"
                "13,999\n"
                "14,999\n"
            )

        for binary in (EXECUTABLE, REBUILT):
            run_and_check(binary, "Zeta Target")
            run_and_check(binary, "No Share")
    finally:
        with open(RESEARCHERS, "wb") as f:
            f.write(original_researchers)
        with open(AUTHORSHIP, "wb") as f:
            f.write(original_authorship)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
