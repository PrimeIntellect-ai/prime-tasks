#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import os
import secrets
import struct
import subprocess
import time

import pytest

SOURCE = "/home/user/extract_moves.c"
EXECUTABLE = "/home/user/extract_moves"
FINAL_OUTPUT = "/home/user/datasets/combined_moves.bin"


def test_c_file_exists():
    """Test that the C source code file exists."""
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_output_file_exists_and_size():
    """Test that the binary output file exists and has the correct size."""
    assert os.path.exists(FINAL_OUTPUT), f"Output file {FINAL_OUTPUT} is missing. Did you run the xargs command?"
    assert os.path.isfile(FINAL_OUTPUT), f"{FINAL_OUTPUT} is not a regular file."
    filesize = os.path.getsize(FINAL_OUTPUT)
    assert filesize == 48, f"Expected output file to be exactly 48 bytes, got {filesize} bytes."


def test_output_file_content():
    """Test that the binary output file contains the correct float pairs."""
    assert os.path.exists(FINAL_OUTPUT), f"Output file {FINAL_OUTPUT} is missing."
    expected_pairs = {
        (1.0, 2.0),
        (3.0, 4.0),
        (-1.5, 10.0),
        (5.0, -2.5),
        (100.5, 200.5),
        (101.0, 201.0),
    }
    actual_pairs = set()
    filesize = os.path.getsize(FINAL_OUTPUT)
    assert filesize % 8 == 0, "File size is not a multiple of 8 bytes."
    with open(FINAL_OUTPUT, "rb") as f:
        for _ in range(filesize // 8):
            x, y = struct.unpack("ff", f.read(8))
            actual_pairs.add((round(x, 4), round(y, 4)))
    expected_pairs_rounded = {(round(x, 4), round(y, 4)) for x, y in expected_pairs}
    assert actual_pairs == expected_pairs_rounded, (
        f"Extracted pairs do not match expected pairs.\n"
        f"Expected: {expected_pairs_rounded}\nActual: {actual_pairs}"
    )


@pytest.fixture(scope="session")
def binaries(tmp_path_factory):
    """Exercise both the submitted executable and a fresh build of its source."""
    build_dir = tmp_path_factory.mktemp("build")
    rebuilt = build_dir / "extract_moves_rebuilt"
    result = subprocess.run(
        ["gcc", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Source did not compile with gcc:\n{result.stderr}"
    return [EXECUTABLE, str(rebuilt)]


def pack_pair(pair):
    return struct.pack("=ff", pair[0], pair[1])


def read_pairs(path):
    data = path.read_bytes()
    assert len(data) % 8 == 0, "Output was not a sequence of two-float records."
    return [struct.unpack("=ff", data[i:i + 8]) for i in range(0, len(data), 8)]


def test_fresh_parsing_append_and_exact_prefix_rules(binaries, tmp_path):
    base = secrets.randbelow(500000) + 10000
    pairs = [
        (base / 8.0, -(base + 11) / 8.0),
        (-(base + 23) / 8.0, (base + 37) / 8.0),
        ((base + 41) / 8.0, (base + 53) / 8.0),
    ]
    seed = ((base + 101) / 8.0, -(base + 103) / 8.0)

    for index, binary in enumerate(binaries):
        work = tmp_path / f"parse_{index}"
        work.mkdir()
        input_file = work / "fresh.gcode"
        output_file = work / "moves.bin"
        input_file.write_text(
            f"G28\n"
            f"G1 X{pairs[0][0]} Y{pairs[0][1]} Z0.2\n"
            f"G1 E1.0 Y{pairs[1][1]} Z4 X{pairs[1][0]}\n"
            f"G1  X{pairs[2][0]}   Y{pairs[2][1]} E2\n"
            f"G1 X{base / 8.0} E1\n"
            f"G1 Y{base / 8.0} E1\n"
            f"G0 X{base / 8.0} Y{base / 8.0}\n"
            f"G10 X{base / 8.0} Y{base / 8.0}\n"
            f" G1 X{base / 8.0} Y{base / 8.0}\n"
            f"G1\tX{base / 8.0} Y{base / 8.0}\n"
        )
        output_file.write_bytes(pack_pair(seed))
        result = subprocess.run(
            [binary, str(input_file), str(output_file)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode == 0, f"{binary} failed on a fresh valid input."
        expected = pack_pair(seed) + b"".join(pack_pair(pair) for pair in pairs)
        assert output_file.read_bytes() == expected, (
            f"{binary} did not parse fresh G1 lines correctly or did not append to the output."
        )


def test_requires_exactly_two_arguments(binaries, tmp_path):
    for binary in binaries:
        no_args = subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        assert no_args.returncode != 0, f"{binary} accepted zero arguments."
        extra = subprocess.run(
            [binary, str(tmp_path / "a"), str(tmp_path / "b"), str(tmp_path / "c")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
        assert extra.returncode != 0, f"{binary} accepted more than two arguments."


def test_exclusive_lock_blocks_until_released(binaries, tmp_path):
    base = secrets.randbelow(500000) + 600000
    pair = (base / 8.0, -(base + 7) / 8.0)

    for index, binary in enumerate(binaries):
        input_file = tmp_path / f"lock_{index}.gcode"
        output_file = tmp_path / f"lock_{index}.bin"
        input_file.write_text(f"G1 X{pair[0]} Y{pair[1]}\n")
        output_file.touch()

        with open(output_file, "r+b", buffering=0) as holder:
            # Linux flock and POSIX record locks are separate, so hold both;
            # an implementation using either permitted API must wait.
            fcntl.flock(holder.fileno(), fcntl.LOCK_EX)
            fcntl.lockf(holder.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen([binary, str(input_file), str(output_file)])
            try:
                time.sleep(0.30)
                was_blocked = proc.poll() is None
            finally:
                fcntl.lockf(holder.fileno(), fcntl.LOCK_UN)
                fcntl.flock(holder.fileno(), fcntl.LOCK_UN)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                pytest.fail(f"{binary} did not finish after the output lock was released.")

        assert was_blocked, f"{binary} wrote without waiting for an exclusive output-file lock."
        assert proc.returncode == 0, f"{binary} failed after the lock was released."
        assert output_file.read_bytes() == pack_pair(pair)


def test_concurrent_execution_produces_complete_records(binaries, tmp_path):
    base = secrets.randbelow(500000) + 1200000
    expected = [((base + i * 17) / 8.0, -(base + i * 17 + 5) / 8.0) for i in range(24)]

    for binary_index, binary in enumerate(binaries):
        work = tmp_path / f"concurrent_{binary_index}"
        work.mkdir()
        output_file = work / "combined.bin"
        processes = []
        for i, pair in enumerate(expected):
            input_file = work / f"input_{i}.gcode"
            input_file.write_text(
                f"G1 X{pair[0]} Y{pair[1]} E1\n"
                f"G1 X{pair[0]}\n"
                f"G0 X0 Y0\n"
            )
            processes.append(subprocess.Popen([binary, str(input_file), str(output_file)]))

        for proc in processes:
            proc.wait(timeout=8)
            assert proc.returncode == 0, f"Concurrent invocation of {binary} failed."

        actual = read_pairs(output_file)
        assert len(actual) == len(expected), "Concurrent output had missing or partial records."
        assert collections.Counter(actual) == collections.Counter(expected), (
            "Concurrent output did not contain exactly the records from all fresh input files."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
