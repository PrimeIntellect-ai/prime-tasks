#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

SOURCE_PATH = '/home/user/config_tracker.c'
EXECUTABLE_PATH = '/home/user/config_tracker'
OUTPUT_PATH = '/home/user/output.txt'


def test_c_source_exists():
    assert os.path.isfile(SOURCE_PATH), "The C source file /home/user/config_tracker.c does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"The executable {EXECUTABLE_PATH} does not exist."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"The file {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The executable must be a compiled native executable."


def test_output_file_exists_and_content():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_output = """srv-münchen (11 chars): 50 bytes, avg: 50.00
srv-londres (11 chars): 120 bytes, avg: 120.00
srv-münchen (11 chars): 60 bytes, avg: 55.00
srv-münchen (11 chars): 70 bytes, avg: 60.00
srv-münchen (11 chars): 80 bytes, avg: 70.00
srv-東京 (6 chars): 200 bytes, avg: 200.00
srv-서울 (6 chars): 150 bytes, avg: 150.00
srv-東京 (6 chars): 300 bytes, avg: 250.00
srv-서울 (6 chars): 250 bytes, avg: 200.00
srv-東京 (6 chars): 100 bytes, avg: 200.00
srv-東京 (6 chars): 400 bytes, avg: 266.67"""

    assert content == expected_output, f"The content of {OUTPUT_PATH} does not match the expected output. Found:\n{content}"


def make_inputs(directory):
    token = secrets.token_hex(5)
    a = f'edge-{token}-東京🙂'
    b = f'nœud-{token}-é'
    c = f'서버-{token}-α'
    values = [secrets.randbelow(800) + 1 for _ in range(12)]

    csv_records = [
        (a, 201, values[0]),
        (b, 202, values[1]),
        (a, 203, values[2]),
        (a, 204, values[3]),
        (a, 205, values[4]),
        (b, 206, values[5]),
    ]
    tsv_records = [
        (c, 301, values[6]),
        (a, 302, values[7]),
        (c, 303, values[8]),
        (a, 304, values[9]),
        (c, 305, values[10]),
        (c, 306, values[11]),
    ]

    csv_path = os.path.join(directory, f'{secrets.token_hex(4)}.csv')
    tsv_path = os.path.join(directory, f'{secrets.token_hex(4)}.tsv')
    with open(csv_path, 'w', encoding='utf-8', newline='') as f:
        for name, timestamp, changed in csv_records:
            f.write(f'{name},{timestamp},{changed}\n')
    with open(tsv_path, 'w', encoding='utf-8', newline='') as f:
        for name, timestamp, changed in tsv_records:
            f.write(f'{name}\t{timestamp}\t{changed}\n')

    if secrets.randbelow(2):
        paths = [csv_path, tsv_path]
        records = csv_records + tsv_records
    else:
        paths = [tsv_path, csv_path]
        records = tsv_records + csv_records

    history = {}
    expected = []
    for name, _timestamp, changed in records:
        recent = history.setdefault(name, [])
        recent.append(changed)
        if len(recent) > 3:
            del recent[0]
        expected.append(
            f'{name} ({len(name)} chars): {changed} bytes, avg: {sum(recent) / len(recent):.2f}'
        )
    return paths, '\n'.join(expected)


def run_behavior_check(executable):
    with tempfile.TemporaryDirectory(prefix='tracker-input-') as directory:
        paths, expected = make_inputs(directory)
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        result = subprocess.run(
            [executable] + paths,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f'{executable} exited with {result.returncode}. stderr:\n{result.stderr}'
        )
        assert os.path.isfile(OUTPUT_PATH), f'{executable} did not create {OUTPUT_PATH}'
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            actual = f.read().strip()
        assert actual == expected, (
            f'Incorrect dynamically generated output from {executable}.\n'
            f'Expected:\n{expected}\nFound:\n{actual}'
        )


def test_program_parsing_unicode_and_rolling_average():
    run_behavior_check(EXECUTABLE_PATH)

    with tempfile.TemporaryDirectory(prefix='tracker-build-') as directory:
        rebuilt = os.path.join(directory, 'config_tracker')
        result = subprocess.run(
            ['gcc', '-O2', SOURCE_PATH, '-o', rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f'The C source did not compile:\n{result.stderr}'
        run_behavior_check(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
