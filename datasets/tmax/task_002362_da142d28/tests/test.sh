#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict
import pytest

DATASET = '/home/user/dataset'
OUTPUT = '/home/user/top_papers.out'
EXECUTABLE = '/home/user/analyze'
SOURCE = '/home/user/analyze.c'
CJSON_DIR = '/app/cJSON-1.7.15'


def get_expected_top_20():
    valid_years = set()
    with open(os.path.join(DATASET, 'papers.csv'), 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) >= 3:
                pid = int(parts[0])
                year = int(parts[2])
                if year >= 2015:
                    valid_years.add(pid)

    in_degrees = defaultdict(int)
    for pid in valid_years:
        in_degrees[pid] = 0

    with open(os.path.join(DATASET, 'citations.txt'), 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                src, tgt = int(parts[0]), int(parts[1])
                if src in valid_years and tgt in valid_years:
                    in_degrees[tgt] += 1

    top_20 = sorted(in_degrees.items(), key=lambda x: (-x[1], x[0]))[:20]

    with open(os.path.join(DATASET, 'metadata.json'), 'r') as f:
        metadata = json.load(f)
    keyword_map = {item['id']: item['keywords'] for item in metadata}

    return [
        f"ID:{pid} | CITATIONS:{count} | KEYWORDS:{','.join(keyword_map.get(pid, []))}"
        for pid, count in top_20
    ]


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def assert_output_correct():
    actual_lines = read_output()
    expected_lines = get_expected_top_20()
    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def run_clean(executable):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, \
        f"Execution of {executable} failed. Stderr: {result.stderr}"
    assert_output_correct()


def write_independent_fixture():
    with open(os.path.join(DATASET, 'papers.csv'), 'w') as f:
        for pid in range(1, 31):
            year = 2015 + (pid % 9) if pid <= 25 else 2010
            f.write(f"{pid},Fixture_Paper_{pid},{year}\n")

    with open(os.path.join(DATASET, 'citations.txt'), 'w') as f:
        for target in range(1, 26):
            for j in range((31 - target) % 8):
                source = ((target + j) % 25) + 1
                f.write(f"{source} {target}\n")
        # These edges must not contribute to filtered in-degree.
        for _ in range(12):
            f.write('26 1\n')
        for target in range(26, 31):
            f.write(f"1 {target}\n")

    metadata = [
        {'id': pid, 'keywords': [f'fixture{pid}', 'even' if pid % 2 == 0 else 'odd']}
        for pid in range(30, 0, -1)
    ]
    with open(os.path.join(DATASET, 'metadata.json'), 'w') as f:
        json.dump(metadata, f)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "/home/user/analyze executable does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/analyze is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/analyze is not an ELF executable."


def test_output_file_correctness():
    assert_output_correct()


def test_c_source_and_vendored_cjson_build():
    assert os.path.isfile(SOURCE), "/home/user/analyze.c does not exist."
    with open(SOURCE, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]cJSON\.h[>\"]', source), \
        "analyze.c does not include cJSON.h."
    assert 'cJSON_Parse' in source, "analyze.c does not parse JSON with cJSON."

    makefile = os.path.join(CJSON_DIR, 'Makefile')
    with open(makefile, 'r', errors='replace') as f:
        make_text = f.read()
    assert not re.search(r'^\s*CC\s*=\s*gec\s*$', make_text, re.MULTILINE), \
        "The vendored cJSON Makefile compiler typo was not fixed."

    archive = os.path.join(CJSON_DIR, 'libcjson.a')
    assert os.path.isfile(archive), "The vendored cJSON static library was not built."

    symbols = subprocess.run(
        ['nm', EXECUTABLE], capture_output=True, text=True, timeout=5
    )
    assert 'cJSON_Parse' in symbols.stdout, \
        "/home/user/analyze is not linked with cJSON."


def test_program_generates_results_and_execution_time():
    files = ['papers.csv', 'citations.txt', 'metadata.json']
    with tempfile.TemporaryDirectory() as backup_dir, tempfile.TemporaryDirectory() as build_dir:
        for name in files:
            shutil.copy2(os.path.join(DATASET, name), os.path.join(backup_dir, name))

        rebuilt = os.path.join(build_dir, 'analyze-rebuilt')
        compile_result = subprocess.run(
            [
                'gcc', '-O2', SOURCE,
                '-I' + CJSON_DIR,
                os.path.join(CJSON_DIR, 'libcjson.a'),
                '-lm', '-o', rebuilt
            ],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, \
            f"analyze.c could not be rebuilt against vendored cJSON: {compile_result.stderr}"

        try:
            write_independent_fixture()
            run_clean(EXECUTABLE)
            run_clean(rebuilt)
        finally:
            for name in files:
                shutil.copy2(os.path.join(backup_dir, name), os.path.join(DATASET, name))

        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        result = subprocess.run(
            ['/usr/bin/time', '-f', '%e', EXECUTABLE],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, \
            f"Execution of {EXECUTABLE} failed. Stderr: {result.stderr}"

        # Check the output produced by this timed execution, not a pre-existing file.
        assert_output_correct()

        time_output = result.stderr.strip().split('\n')[-1]
        try:
            execution_time = float(time_output)
        except ValueError:
            pytest.fail(f"Could not parse execution time from output: {time_output}")

        threshold = 0.5
        assert execution_time <= threshold, \
            f"Execution time {execution_time}s exceeded the threshold of {threshold}s."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
