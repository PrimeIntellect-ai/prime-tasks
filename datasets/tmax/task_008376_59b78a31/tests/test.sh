#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import io
import os
import secrets
import subprocess

SCRIPT_PATH = '/home/user/ticket_8492/process_logs.py'
DATA_PATH = '/home/user/ticket_8492/data.csv'
OUTPUT_PATH = '/home/user/ticket_8492/output.txt'

CANONICAL_DATA = '''1,2023-01-01,Init system,15
2,2023-01-02,Load config,25
3,2023-01-03,"Warning, missing config file",50
4,2023-01-04,Process started,10
'''


def assert_required_architecture():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    queue_modules = set()
    queue_constructors = set()
    threading_modules = set()
    thread_constructors = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'queue':
                    queue_modules.add(alias.asname or 'queue')
                if alias.name == 'threading':
                    threading_modules.add(alias.asname or 'threading')
        elif isinstance(node, ast.ImportFrom):
            if node.module == 'queue':
                for alias in node.names:
                    if alias.name == 'Queue':
                        queue_constructors.add(alias.asname or 'Queue')
            if node.module == 'threading':
                for alias in node.names:
                    if alias.name == 'Thread':
                        thread_constructors.add(alias.asname or 'Thread')

    queue_calls = 0
    thread_calls = 0
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute):
            if isinstance(func.value, ast.Name) and func.value.id in queue_modules and func.attr == 'Queue':
                queue_calls += 1
            if isinstance(func.value, ast.Name) and func.value.id in threading_modules and func.attr == 'Thread':
                thread_calls += 1
        elif isinstance(func, ast.Name):
            if func.id in queue_constructors:
                queue_calls += 1
            if func.id in thread_constructors:
                thread_calls += 1

    assert queue_calls >= 2, 'The solution must retain the input and output queue.Queue architecture.'
    assert thread_calls >= 1, 'The solution must retain worker threads.'


def run_script_and_check(expected):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            timeout=10,
            capture_output=True,
            text=True
        )
    except subprocess.TimeoutExpired:
        assert False, 'The script timed out, which indicates the threading deadlock has not been fully resolved.'

    assert result.returncode == 0, (
        f'The script failed with return code {result.returncode}.\nStderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} was not created by the script.'

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == str(expected), f"Expected the final sum to be '{expected}', but got '{content}'."


def expected_from_csv(text):
    rows = csv.reader(io.StringIO(text))
    return sum(int(row[3]) for row in rows if row)


def make_random_csv(row_count):
    rng = secrets.SystemRandom()
    stream = io.StringIO()
    writer = csv.writer(stream, lineterminator='\n')
    messages = [
        'ordinary message',
        'warning, configuration missing',
        'text with a "quoted phrase", and a comma',
        'multiple, embedded, commas',
        'a trailing comma,',
    ]
    for i in range(row_count):
        writer.writerow([
            rng.randrange(100000, 999999),
            f'2026-09-{(i % 28) + 1:02d}',
            messages[i % len(messages)] + f' #{rng.randrange(1_000_000)}',
            rng.randrange(101, 1000),
        ])
        if i % 4 == 1:
            stream.write('\n')
    return stream.getvalue()


def test_script_execution_and_output():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert_required_architecture()

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        # Retain the original fixed execution and exact output assertion.
        with open(DATA_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write(CANONICAL_DATA)
        run_script_and_check(100)

        # Exercise varying record counts, blank lines, quoted commas, and escaped quotes.
        for row_count in (3, 8, 17):
            generated = make_random_csv(row_count)
            expected = expected_from_csv(generated)
            assert expected != 100
            with open(DATA_PATH, 'w', encoding='utf-8', newline='') as f:
                f.write(generated)
            run_script_and_check(expected)
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
