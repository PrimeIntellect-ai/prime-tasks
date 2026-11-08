#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import secrets
import subprocess

SOURCE_PATH = '/home/user/process_configs.c'
EXEC_PATH = '/home/user/process_configs'
INPUT_PATH = '/home/user/config_events.csv'
OUTPUT_PATH = '/home/user/normalized_configs.csv'
COMPILED_PATH = '/tmp/process_configs_from_source'


def get_expected_output(input_file):
    events = []
    with open(input_file, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 3:
                events.append((int(row[0]), row[1], row[2]))

    if not events:
        return []

    first_ts = events[0][0]
    w_start = first_ts - (first_ts % 60)

    windows = {}
    last_window = w_start

    for ts, cat, desc in events:
        w = ts - (ts % 60)
        while last_window < w:
            if last_window not in windows:
                windows[last_window] = {}
            last_window += 60

        if w not in windows:
            windows[w] = {}

        if cat not in windows[w]:
            windows[w][cat] = desc

        last_window = w

    expected_lines = []
    for w in sorted(windows.keys()):
        for cat in ['DB', 'NET', 'SEC']:
            desc = windows[w].get(cat, 'NO_CHANGE')
            expected_lines.append(f"{w},{cat},{desc}")

    return expected_lines


def compile_source():
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', SOURCE_PATH, '-o', COMPILED_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"process_configs.c does not compile as C:\n{result.stderr}"


def write_events(events):
    with open(INPUT_PATH, 'w', newline='') as f:
        for ts, cat, desc in events:
            f.write(f"{ts},{cat},{desc}\n")


def run_and_check(program, events):
    write_events(events)
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)

    result = subprocess.run(
        [program],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}: {result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"{program} did not create {OUTPUT_PATH}."

    expected_lines = get_expected_output(INPUT_PATH)
    actual_lines = []
    with open(OUTPUT_PATH, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                actual_lines.append(stripped)

    assert actual_lines == expected_lines, (
        f"Output from {program} does not match the expected normalized timeline."
    )


def hidden_cases():
    token = secrets.token_hex(6)
    base = (secrets.randbelow(500000000) + 1800000000) // 60 * 60

    boundary_and_gaps = [
        (base + 1, 'NET', f'net_first_{token}'),
        (base + 1, 'NET', f'net_duplicate_{token}'),
        (base + 59, 'DB', f'db_edge_{token}'),
        (base + 60, 'SEC', f'sec_boundary_{token}'),
        (base + 121, 'DB', f'db_later_{token}'),
        (base + 121, 'DB', f'db_later_duplicate_{token}'),
        (base + 300, 'DB', f'db_after_gap_{token}'),
        (base + 301, 'NET', f'net_after_gap_{token}'),
        (base + 302, 'SEC', f'sec_after_gap_{token}'),
    ]

    random_events = []
    for window_index in [0, 2, 5, 6, 9]:
        categories = ['DB', 'NET', 'SEC']
        chosen = [cat for cat in categories if secrets.randbelow(2)]
        if not chosen:
            chosen = [categories[secrets.randbelow(3)]]
        for cat in chosen:
            offset = secrets.randbelow(60)
            desc = f'{cat.lower()}_{window_index}_{secrets.token_hex(5)}'
            random_events.append((base + 1200 + window_index * 60 + offset, cat, desc))
            if secrets.randbelow(3) == 0 and offset < 59:
                random_events.append((base + 1200 + window_index * 60 + offset + 1,
                                      cat, f'duplicate_{secrets.token_hex(5)}'))
    random_events.sort(key=lambda event: event[0])

    return [boundary_and_gaps, random_events]


def test_source_and_executable_exist():
    assert os.path.exists(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    assert os.path.exists(EXEC_PATH), f"Executable {EXEC_PATH} is missing."

    st = os.stat(EXEC_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {EXEC_PATH} is not executable."
    assert stat.S_ISREG(st.st_mode), f"File {EXEC_PATH} is not a regular executable file."
    with open(EXEC_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {EXEC_PATH} is not a compiled executable."

    compile_source()


def test_normalized_configs_output():
    assert os.path.exists(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()

    original_events = []
    with open(INPUT_PATH, 'r', newline='') as f:
        for row in csv.reader(f):
            if len(row) == 3:
                original_events.append((int(row[0]), row[1], row[2]))

    if not os.path.exists(COMPILED_PATH):
        compile_source()

    cases = [original_events] + hidden_cases()
    try:
        for program in [EXEC_PATH, COMPILED_PATH]:
            for events in cases:
                run_and_check(program, events)
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        restore = subprocess.run(
            [EXEC_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert restore.returncode == 0, (
            f"{EXEC_PATH} failed while processing the original fixture: {restore.stderr}"
        )

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    expected_lines = get_expected_output(INPUT_PATH)
    actual_lines = []
    with open(OUTPUT_PATH, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                actual_lines.append(stripped)

    assert actual_lines == expected_lines, (
        "The contents of normalized_configs.csv do not match the expected output."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
