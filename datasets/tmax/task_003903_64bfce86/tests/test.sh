#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os
import secrets
import struct
import subprocess
import tempfile


def test_output_txt_exists_and_correct():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "ID 1: 3.000000",
        "ID 3: 4.000000",
        "ID 4: 5.000000"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in output.txt, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual.strip()}'"


def test_executable_exists():
    exe_path = "/home/user/processor"
    assert os.path.isfile(exe_path), f"Compiled binary {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF binary."


def test_running_executable_reproduces_saved_output():
    expected = "ID 1: 3.000000\nID 3: 4.000000\nID 4: 5.000000\n"
    result = subprocess.run(
        ["/home/user/processor"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"processor exited with {result.returncode}:\n{result.stderr}"
    assert result.stdout == expected, f"Unexpected processor output:\n{result.stdout!r}"
    with open("/home/user/output.txt", "r") as f:
        assert f.read() == result.stdout, "output.txt is not the output produced by processor."


def make_records():
    rng = secrets.SystemRandom()
    ids = []
    while len(ids) < 7:
        candidate = rng.randrange(1, 65536)
        if candidate not in ids and (candidate >> 8) != (candidate & 0xff):
            ids.append(candidate)

    roots = [rng.randrange(2, 60) for _ in range(4)]
    return [
        (ids[0], float(roots[0] * roots[0])),
        (ids[1], -float(rng.randrange(1, 100))),
        (ids[2], float(roots[1] * roots[1])),
        (ids[3], -float(rng.randrange(1, 100))),
        (ids[4], float(roots[2] * roots[2])),
        (ids[5], -float(rng.randrange(1, 100))),
        (ids[6], float(roots[3] * roots[3])),
    ]


def exercise(executable):
    records = make_records()
    expected_lines = [
        f"ID {record_id}: {math.sqrt(value):.6f}"
        for record_id, value in records
        if value >= 0
    ]
    with tempfile.TemporaryDirectory() as workdir:
        with open(os.path.join(workdir, "data.bin"), "wb") as f:
            for record_id, value in records:
                f.write(struct.pack(">H", record_id))
                f.write(struct.pack("<d", value))

        result = subprocess.run(
            [executable],
            cwd=workdir,
            capture_output=True,
            text=True,
            timeout=10,
        )

    assert result.returncode == 0, f"processor exited with {result.returncode}:\n{result.stderr}"
    actual_lines = result.stdout.strip().splitlines()
    assert actual_lines == expected_lines, (
        "processor did not correctly decode generated records or silently skip negatives. "
        f"Expected {expected_lines!r}, got {actual_lines!r}"
    )


def test_installed_executable_on_generated_payload():
    exercise("/home/user/processor")


def test_fixed_source_compiles_and_processes_generated_payload():
    source = "/home/user/processor.c"
    assert os.path.isfile(source), f"{source} does not exist."
    with tempfile.TemporaryDirectory() as builddir:
        executable = os.path.join(builddir, "processor")
        result = subprocess.run(
            ["gcc", "-o", executable, source, "-lm"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"processor.c failed to compile:\n{result.stderr}"
        exercise(executable)


def test_no_memory_leaks():
    # Run valgrind to check for memory leaks
    exe_path = "/home/user/processor"
    assert os.path.isfile(exe_path), f"Compiled binary {exe_path} does not exist."

    try:
        result = subprocess.run(
            ["valgrind", "--leak-check=full", "--error-exitcode=1", exe_path],
            capture_output=True,
            text=True,
            cwd="/home/user"
        )
        assert result.returncode == 0, f"Valgrind reported memory leaks or errors:\n{result.stderr}"
    except FileNotFoundError:
        # If valgrind is not installed, we can't test this, but we assume it's available in the environment
        pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
