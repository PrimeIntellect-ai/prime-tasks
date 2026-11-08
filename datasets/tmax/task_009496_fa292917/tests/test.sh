#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import secrets
import subprocess
import tempfile


def rle_encode(s):
    if not s:
        return ""
    result = []
    count = 1
    prev = s[0]
    for char in s[1:]:
        if char == prev:
            count += 1
        else:
            result.append(f"{count}{prev}")
            prev = char
            count = 1
    result.append(f"{count}{prev}")
    return "".join(result)


def test_chunks_directory_and_files():
    chunks_dir = "/home/user/chunks"
    assert os.path.isdir(chunks_dir), f"Directory {chunks_dir} does not exist."

    chunk_files = sorted(glob.glob(os.path.join(chunks_dir, "x*")))
    assert len(chunk_files) == 4, f"Expected 4 chunk files (e.g., xaa, xab, xac, xad), found {len(chunk_files)}."
    assert [os.path.basename(path) for path in chunk_files] == ["xaa", "xab", "xac", "xad"], "Chunk files do not use the expected split naming convention."

    with open("/home/user/raw_dataset.txt", "r") as f:
        raw_lines = f.read().splitlines()
    assert len(raw_lines) == 20, "Original dataset should contain exactly 20 lines."

    for chunk_index, file_path in enumerate(chunk_files):
        with open(file_path, "r") as f:
            lines = f.read().splitlines()
        assert len(lines) == 5, f"Chunk file {file_path} should contain exactly 5 lines."
        expected_lines = [
            f"{i + 1},{raw_lines[chunk_index * 5 + i]}"
            for i in range(5)
        ]
        for i, line in enumerate(lines):
            expected_prefix = f"{i + 1},"
            assert line.startswith(expected_prefix), f"Line {i + 1} in {file_path} does not start with '{expected_prefix}'."
        assert lines == expected_lines, f"Chunk file {file_path} does not contain the corresponding formatted raw-data lines."


def test_compress_script_executable():
    script_path = "/home/user/compress.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def run_compressor(file_path):
    result = subprocess.run(
        ["/home/user/compress.sh", file_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"compress.sh failed for {file_path}: {result.stderr}"
    return result.stdout.splitlines()


def test_compress_script_on_derived_probe():
    probe_lines = []
    expected = []
    alphabet = "ACGT"
    for i in range(1, 6):
        sequence = "".join(secrets.choice(alphabet) for _ in range(80 + i))
        probe_lines.append(f"{i},{sequence}")
        expected.append(f"{i},{rle_encode(sequence)}")

    fd, probe_path = tempfile.mkstemp(prefix="rle_probe_", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(probe_lines) + "\n")
        actual = run_compressor(probe_path)
        assert actual == expected, f"compress.sh produced incorrect output for a valid input file. Expected {expected}, got {actual}."
    finally:
        os.unlink(probe_path)


def test_compress_script_on_chunks_and_merged_output():
    chunk_files = sorted(glob.glob("/home/user/chunks/x*"))
    combined_output = []
    for file_path in chunk_files:
        with open(file_path, "r") as f:
            formatted_lines = f.read().splitlines()
        expected = []
        for line in formatted_lines:
            prefix, sequence = line.split(",", 1)
            expected.append(f"{prefix},{rle_encode(sequence)}")
        actual = run_compressor(file_path)
        assert actual == expected, f"compress.sh output for {file_path} is incorrect."
        combined_output.extend(actual)

    with open("/home/user/final_dataset.rle", "r") as f:
        final_lines = f.read().splitlines()
    assert final_lines == combined_output, "final_dataset.rle is not the combined output of compress.sh over the chunks in alphabetical order."


def test_final_dataset_content():
    raw_path = "/home/user/raw_dataset.txt"
    final_path = "/home/user/final_dataset.rle"

    assert os.path.isfile(raw_path), f"Original dataset {raw_path} is missing."
    assert os.path.isfile(final_path), f"Final dataset {final_path} is missing."

    with open(raw_path, "r") as f:
        raw_lines = f.read().splitlines()

    expected_lines = []
    for i, line in enumerate(raw_lines):
        line_num = (i % 5) + 1
        compressed = rle_encode(line)
        expected_lines.append(f"{line_num},{compressed}")

    with open(final_path, "r") as f:
        final_lines = f.read().splitlines()

    assert len(final_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {final_path}, found {len(final_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, final_lines)):
        assert expected == actual, f"Line {i + 1} in {final_path} is incorrect. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
