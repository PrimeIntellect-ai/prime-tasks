#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import struct
import subprocess

import pytest

PROCESS = "/home/user/process"
SOURCE = "/home/user/process.c"
RECORDS = "/home/user/records.bin"


@pytest.fixture(scope="session", autouse=True)
def restore_records_file():
    with open(RECORDS, "rb") as f:
        original = f.read()
    try:
        yield
    finally:
        with open(RECORDS, "wb") as f:
            f.write(original)


def test_original_final_state_assertions():
    """Retain the original checks on the requested final artifacts."""
    assert os.path.isfile(PROCESS), f"Compiled executable not found at {PROCESS}"
    st = os.stat(PROCESS)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), \
        f"File {PROCESS} is not executable"

    answer_path = "/home/user/answer.txt"
    assert os.path.isfile(answer_path), f"Output file not found at {answer_path}"
    with open(answer_path, "r") as f:
        content = f.read().strip()
    assert content == "103", f"Expected answer.txt to contain '103', but got '{content}'"

    log_path = "/home/user/valgrind.log"
    assert os.path.isfile(log_path), f"Valgrind log not found at {log_path}"
    with open(log_path, "r") as f:
        content = f.read()
    expected_phrase = "All heap blocks were freed -- no leaks are possible"
    assert expected_phrase in content, \
        f"Valgrind log does not contain the expected success message: '{expected_phrase}'"


def make_records(target_position, count):
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 2000000000), count)
    records = []
    for i in range(count):
        if i == target_position:
            a = rng.randrange(0, 1338)
            b = 1337 - a
        else:
            while True:
                a = rng.randrange(0, 4000)
                b = rng.randrange(0, 4000)
                if a + b != 1337:
                    break
        records.append((ids[i], a, b))
    return records, ids[target_position]


def run_under_valgrind(executable, target_position, count):
    records, expected_id = make_records(target_position, count)
    with open(RECORDS, "wb") as f:
        for record in records:
            f.write(struct.pack("<III", *record))

    result = subprocess.run(
        [
            "valgrind",
            "--leak-check=full",
            "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all",
            "--error-exitcode=99",
            executable,
        ],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    stderr = result.stderr.decode("utf-8", errors="replace")
    assert result.returncode == 0, \
        f"{executable} failed under Valgrind (exit {result.returncode}):\n{stderr}"
    assert result.stdout == f"{expected_id}\n".encode(), \
        f"{executable} produced {result.stdout!r}; expected {expected_id!r} followed by a newline"
    assert "All heap blocks were freed -- no leaks are possible" in stderr, \
        f"Valgrind did not confirm that all allocations were freed for {executable}:\n{stderr}"


def test_program_and_fixed_source_on_generated_inputs():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"
    with open(PROCESS, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROCESS} is not a compiled ELF executable"

    rebuilt = "/tmp/process_rebuilt_from_submission"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O0", "-g", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        "The submitted process.c does not compile:\n" + compile_result.stderr.decode("utf-8", errors="replace")

    for executable in (PROCESS, rebuilt):
        run_under_valgrind(executable, target_position=0, count=5)
        run_under_valgrind(executable, target_position=6, count=7)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
