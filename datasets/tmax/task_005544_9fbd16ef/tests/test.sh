#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import shutil
import struct
import subprocess

MASTER_INDEX_PATH = "/home/user/dataset/master_index.csv"
RAW_DIR = "/home/user/dataset/raw"
SOURCE_PATH = "/home/user/process_sensor.cpp"
EXECUTABLE_PATH = "/home/user/process_sensor"
COMPILED_TEST_PATH = "/tmp/verifier_process_sensor"


def read_expected_raw_results():
    expected = {}
    for root, _, files in os.walk(RAW_DIR):
        for name in files:
            if not (name.endswith(".bin") or name.endswith(".tsv")):
                continue
            path = os.path.join(root, name)
            if name.endswith(".bin"):
                with open(path, "rb") as f:
                    data = f.read()
                assert len(data) == 80, f"Binary file {path} is not 80 bytes"
                values = struct.unpack("<10d", data)
            else:
                with open(path, "r") as f:
                    values = [float(x) for x in f.read().split()]
                assert len(values) == 10, f"TSV file {path} does not contain 10 values"
            expected[path] = f"{sum(values) / 10.0:.4f}"
    return expected


def test_master_index_exists():
    assert os.path.isfile(MASTER_INDEX_PATH), f"Expected output file {MASTER_INDEX_PATH} does not exist."


def test_master_index_line_count():
    with open(MASTER_INDEX_PATH, "r") as f:
        lines = f.readlines()
    assert len(lines) == 100, f"Expected exactly 100 lines in {MASTER_INDEX_PATH}, but got {len(lines)}."


def test_master_index_format_and_no_corruption():
    with open(MASTER_INDEX_PATH, "r") as f:
        lines = f.readlines()

    pattern = re.compile(r'^/home/user/dataset/raw/.*,[0-9]+\.[0-9]{4}\n?$')
    bad_lines = []
    for i, line in enumerate(lines):
        if not pattern.match(line):
            bad_lines.append((i + 1, line.strip()))
    assert not bad_lines, f"Found {len(bad_lines)} corrupted or incorrectly formatted lines (file locking likely failed). Examples: {bad_lines[:5]}"


def test_master_index_exact_contents():
    with open(MASTER_INDEX_PATH, "r") as f:
        lines = f.read().splitlines()

    results = {}
    rendered_results = {}
    for line in lines:
        parts = line.split(',')
        if len(parts) == 2:
            path, mean_str = parts
            results[path] = float(mean_str)
            rendered_results[path] = mean_str

    total_sum = sum(results.values())
    expected_sum = sum(range(100))
    assert abs(total_sum - expected_sum) < 1e-6, f"Expected sum of averages to be {expected_sum:.4f}, got {total_sum:.4f}"
    assert len(results) == 100, f"Expected 100 unique file paths, got {len(results)}"

    for path in results:
        assert path.startswith(RAW_DIR), f"Path {path} does not start with {RAW_DIR}"
        assert path.endswith('.bin') or path.endswith('.tsv'), f"Path {path} does not end with .bin or .tsv"

    expected = read_expected_raw_results()
    assert len(expected) == 100, f"Expected 100 raw sensor files, found {len(expected)}"
    assert set(rendered_results) == set(expected), "master_index.csv paths do not exactly match the raw dataset files"
    mismatches = {
        path: (rendered_results[path], expected[path])
        for path in expected
        if rendered_results[path] != expected[path]
    }
    assert not mismatches, f"Incorrect means for raw files: {list(mismatches.items())[:5]}"


def test_program_artifacts_and_locking_call_exist():
    assert os.path.isfile(SOURCE_PATH), f"Missing C++ source file {SOURCE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), f"Missing executable {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled executable"

    subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", COMPILED_TEST_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    symbols = subprocess.run(
        ["nm", "-D", COMPILED_TEST_PATH],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).stdout
    assert re.search(r'\b(flock|fcntl)(?:@|$)', symbols, re.MULTILINE), "Compiled source does not call flock() or fcntl()"


def test_z_program_reads_stdin_formats_and_survives_eight_way_concurrency():
    with open(MASTER_INDEX_PATH, "rb") as f:
        original_index = f.read()

    def invoke(executable, i):
        value = float(i) + 0.25
        if i % 2 == 0:
            flag = "--bin"
            path = f"/home/user/dataset/raw/verifier/concurrent_{i}.bin"
            payload = struct.pack("<10d", *([value] * 10))
        else:
            flag = "--tsv"
            path = f"/home/user/dataset/raw/verifier/concurrent_{i}.tsv"
            payload = ("\t".join([str(value)] * 10) + "\n").encode()
        result = subprocess.run(
            [executable, flag, path],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        return path, f"{value:.4f}"

    try:
        open(MASTER_INDEX_PATH, "wb").close()

        # Exercise the submitted compiled artifact directly for both input formats.
        direct_expected = dict([invoke(EXECUTABLE_PATH, 1000), invoke(EXECUTABLE_PATH, 1001)])
        with open(MASTER_INDEX_PATH, "r") as f:
            direct_lines = f.read().splitlines()
        assert sorted(direct_lines) == sorted(f"{p},{v}" for p, v in direct_expected.items())

        # Recompile the submitted source and exercise it with exactly eight workers.
        open(MASTER_INDEX_PATH, "wb").close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            pairs = list(pool.map(lambda i: invoke(COMPILED_TEST_PATH, i), range(160)))

        with open(MASTER_INDEX_PATH, "r") as f:
            lines = f.read().splitlines()
        expected_lines = {f"{path},{mean}" for path, mean in pairs}
        assert len(lines) == 160, f"Concurrent run produced {len(lines)} lines instead of 160"
        assert len(set(lines)) == 160, "Concurrent run produced duplicate or merged lines"
        assert set(lines) == expected_lines, "Concurrent execution produced missing, corrupted, or incorrect output"
    finally:
        with open(MASTER_INDEX_PATH, "wb") as f:
            f.write(original_index)
        if os.path.exists(COMPILED_TEST_PATH):
            os.remove(COMPILED_TEST_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
