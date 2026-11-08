#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from collections import Counter


def test_analyzer_files_exist():
    assert os.path.isfile('/home/user/analyzer.c'), "C source file /home/user/analyzer.c is missing."
    assert os.path.isfile('/home/user/analyzer'), "Executable /home/user/analyzer is missing."
    assert os.access('/home/user/analyzer', os.X_OK), "/home/user/analyzer is not executable."


def test_stats_csv_content():
    stats_path = '/home/user/stats.csv'
    assert os.path.isfile(stats_path), f"Output file {stats_path} is missing."

    expected_lines = [
        "ErrorCode,Count",
        "403,1",
        "404,2",
        "500,2"
    ]

    with open(stats_path, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"Content of {stats_path} is incorrect. Expected {expected_lines}, got {actual_lines}"


def test_monitor_log_content():
    monitor_path = '/home/user/monitor.log'
    assert os.path.isfile(monitor_path), f"Monitor log file {monitor_path} is missing."

    expected_content = "Processed 7 lines. Found 5 critical errors."

    with open(monitor_path, 'r') as f:
        content = f.read()

    assert expected_content in content, f"Expected '{expected_content}' in {monitor_path}, but got '{content}'"


def make_case(directory):
    codes = secrets.SystemRandom().sample(range(100, 1000), 3)
    a, b, c = codes
    nonce = secrets.token_hex(8)
    lines = [
        f"[{nonce}] [INFO] startup ErrorCode: {c}",
        f"prefix-{nonce} [ERROR] worker ErrorCode: {a} - first",
        f"[{nonce}] [FATAL] database ErrorCode: {b} - second",
        f"[{nonce}] [WARN] ignored ErrorCode: {a}",
        f"noise [ERROR] node ErrorCode: {a} - repeated",
        f"[{nonce}] [FATAL] cache ErrorCode: {c} - third",
        f"[{nonce}] [DEBUG] no critical marker",
        f"[{nonce}] [ERROR] gateway ErrorCode: {b} - repeated"
    ]
    input_path = os.path.join(directory, f"input-{nonce}.log")
    output_path = os.path.join(directory, f"output-{nonce}.csv")
    with open(input_path, 'w') as f:
        f.write('\n'.join(lines))

    counts = Counter([a, b, a, c, b])
    expected_csv = ["ErrorCode,Count"] + [
        f"{code},{counts[code]}" for code in sorted(counts)
    ]
    return input_path, output_path, len(lines), 5, expected_csv


def exercise(executable):
    with tempfile.TemporaryDirectory(prefix='analyzer-test-') as directory:
        input_path, output_path, line_count, critical_count, expected_csv = make_case(directory)
        with open(output_path, 'w') as f:
            f.write('stale,data\n999,999\n')

        marker = f"preexisting-{secrets.token_hex(8)}\n".encode()
        with open('/home/user/monitor.log', 'wb') as f:
            f.write(marker)

        result = subprocess.run(
            [executable, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        assert result.returncode == 0, (
            f"Analyzer exited with {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "Analyzer did not create the requested CSV output."
        with open(output_path, 'r') as f:
            actual_csv = [line.strip() for line in f.readlines() if line.strip()]
        assert actual_csv == expected_csv, f"Expected {expected_csv}, got {actual_csv}"

        expected_monitor = marker + (
            f"Processed {line_count} lines. Found {critical_count} critical errors.\n"
        ).encode()
        with open('/home/user/monitor.log', 'rb') as f:
            actual_monitor = f.read()
        assert actual_monitor == expected_monitor, (
            "Analyzer must preserve the monitor log and append exactly one correctly formatted line."
        )


def test_analyzer_executes_on_alternate_input():
    with open('/home/user/analyzer', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/analyzer must be a compiled executable."
    exercise('/home/user/analyzer')


def test_source_compiles_uses_posix_regex_and_behaves():
    with open('/home/user/analyzer.c', 'r', errors='replace') as f:
        source = f.read()
    assert 'regex.h' in source, "analyzer.c must include the POSIX regex header."
    assert 'regcomp' in source and 'regexec' in source, (
        "analyzer.c must compile and execute POSIX regular expressions."
    )

    with tempfile.TemporaryDirectory(prefix='analyzer-build-') as directory:
        rebuilt = os.path.join(directory, 'analyzer')
        result = subprocess.run(
            ['gcc', '-o', rebuilt, '/home/user/analyzer.c'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20
        )
        assert result.returncode == 0, (
            f"analyzer.c does not compile with the required command: {result.stderr!r}"
        )
        exercise(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
