#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

SOURCE = Path('/home/user/detect_spam.c')
EXECUTABLE = Path('/home/user/detect_spam')
LOG = Path('/home/user/chat_logs.txt')
OUTPUT = Path('/home/user/suspicious_patterns.csv')


def test_c_source_file_exists():
    assert os.path.exists('/home/user/detect_spam.c'), "The C source file /home/user/detect_spam.c does not exist."


def test_executable_exists():
    assert os.path.exists('/home/user/detect_spam'), "The compiled executable /home/user/detect_spam does not exist."
    assert os.access('/home/user/detect_spam', os.X_OK), "The file /home/user/detect_spam is not executable."


def test_output_file_exists():
    assert os.path.exists('/home/user/suspicious_patterns.csv'), "The output file /home/user/suspicious_patterns.csv does not exist."


def test_output_file_content():
    expected_records = [
        ["2023-10-01T12:00:30Z", "U01", "U03", "1", "3"],
        ["2023-10-01T12:01:10Z", "U03", "U04", "1", "3"],
        ["2023-10-01T12:05:10Z", "U05", "U06", "2", "2"],
        ["2023-10-01T12:05:30Z", "U05", "U08", "1", "4"],
        ["2023-10-01T12:05:30Z", "U08", "U05", "0", "5"]
    ]

    actual_records = []
    with open('/home/user/suspicious_patterns.csv', 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_records.append([col.strip() for col in row])

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records in suspicious_patterns.csv, but found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, f"Record {i+1} mismatch. Expected: {','.join(expected)}, Actual: {','.join(actual)}"


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def expected_records(entries):
    result = []
    for i, (when, current_user, current_message) in enumerate(entries):
        previous_in_window = []
        for j in range(i):
            delta = int((when - entries[j][0]).total_seconds())
            if 0 <= delta <= 60:
                previous_in_window.append(entries[j])

        window_count = len(previous_in_window) + 1
        for _, previous_user, previous_message in previous_in_window:
            distance = levenshtein(previous_message, current_message)
            if previous_user != current_user and distance <= 2:
                result.append([
                    when.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    previous_user,
                    current_user,
                    str(distance),
                    str(window_count),
                ])
    return result


def write_log(entries):
    text = ''.join(
        f"{when.strftime('%Y-%m-%dT%H:%M:%SZ')} | {user} | {message}\n"
        for when, user, message in entries
    )
    LOG.write_text(text, encoding='utf-8')


def read_output():
    assert OUTPUT.is_file(), 'The program did not create suspicious_patterns.csv.'
    text = OUTPUT.read_text(encoding='utf-8')
    assert ', ' not in text, 'Output contains spaces after commas.'
    return [row for row in csv.reader(text.splitlines()) if row]


def run_case(program, entries):
    write_log(entries)
    if OUTPUT.exists():
        OUTPUT.unlink()
    completed = subprocess.run(
        [str(program)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert completed.returncode == 0, (
        f'{program} exited with status {completed.returncode}: '
        f'{completed.stderr.decode("utf-8", errors="replace")}'
    )
    actual = read_output()
    expected = expected_records(entries)
    assert actual == expected, f'Behavioral output mismatch. Expected {expected}, got {actual}'


def make_cases():
    rng = secrets.SystemRandom()
    alphabet = ['界', '猫', 'λ', 'Ж', '🙂', 'é', '中', 'ø', 'あ', 'ß']
    chars = rng.sample(alphabet, 6)
    stem = ''.join(chars)
    replacement = next(c for c in alphabet if c not in chars)
    variant = stem[:2] + replacement + stem[3:]
    short = stem[:-1]
    token = secrets.token_hex(5)
    users = [f'R{secrets.token_hex(4)}' for _ in range(7)]
    base = datetime(2024, 2, 28, 23, 59, 30, tzinfo=timezone.utc)

    offsets = [0, 11, 23, 60, 61, 70, 120, 121, 125, 186, 3605]
    messages = [
        stem,
        variant,
        stem + '🙂',
        stem,
        short,
        short,
        variant,
        stem,
        'unrelated-' + token,
        'unrelated-' + token[:-1] + 'x',
        stem,
    ]
    user_indexes = [0, 1, 0, 2, 3, 3, 4, 5, 6, 0, 1]
    case_one = [
        (base + timedelta(seconds=offset), users[user_indexes[i]], messages[i])
        for i, offset in enumerate(offsets)
    ]

    pool = [stem, variant, short, stem + '🙂', 'noise-' + token]
    case_two = []
    current = base + timedelta(hours=3)
    for i in range(22):
        if i:
            current += timedelta(seconds=rng.choice([0, 1, 7, 19, 31, 59, 60, 61, 73]))
        message = rng.choice(pool)
        user = rng.choice(users)
        case_two.append((current, user, message))

    return [case_one, case_two]


def test_z_execute_submitted_program_and_source_on_additional_inputs():
    assert SOURCE.is_file(), 'detect_spam.c must be a regular file.'
    assert EXECUTABLE.is_file(), 'detect_spam must be a regular file.'
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'detect_spam is not a compiled executable.'

    rebuilt = Path('/tmp/detect_spam_rebuilt')
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert compile_result.returncode == 0, (
        'detect_spam.c does not compile: ' +
        compile_result.stderr.decode('utf-8', errors='replace')
    )

    original_log = LOG.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        cases = make_cases()
        for program in (EXECUTABLE, rebuilt):
            for entries in cases:
                run_case(program, entries)
    finally:
        LOG.write_bytes(original_log)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
