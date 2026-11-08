#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re


def test_api_response_json_exists_and_valid():
    file_path = '/home/user/api_response.json'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {file_path} does not contain valid JSON."

    expected_data = [
        {"version": "1.5.0", "data": "start of v1.5"},
        {"version": "1.11.2", "data": "higher minor"},
        {"version": "2.0.1", "data": "major update"}
    ]

    assert data == expected_data, f"The content of {file_path} does not match the expected JSON structure and values."


def test_benchmark_txt_exists_and_non_empty():
    file_path = '/home/user/benchmark.txt'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    assert os.path.getsize(file_path) > 0, f"The file {file_path} is empty."

    with open(file_path, 'r') as f:
        content = f.read().lower()

    # Keep the original check for common benchmarking-tool keywords.
    keywords = ['real', 'user', 'sys', 'system', 'cpu', 'seconds']
    assert any(kw in content for kw in keywords), f"The file {file_path} does not appear to contain valid benchmark output."

    number = r'\\d+(?:\\.\\d+)?'

    # Accept standard output from shell/POSIX `time`, such as:
    # real 0m0.012s / user 0m0.010s / sys 0m0.002s
    # or: real 0.01 / user 0.00 / sys 0.00
    shell_value = rf'(?:\\d+m{number}s|{number}s?|\\d+:\\d+(?:\\.\\d+)?)'
    real_line = re.search(rf'^\\s*real\\s+{shell_value}\\s*$', content, re.MULTILINE)
    user_line = re.search(rf'^\\s*user\\s+{shell_value}\\s*$', content, re.MULTILINE)
    sys_line = re.search(rf'^\\s*(?:sys|system)\\s+{shell_value}\\s*$', content, re.MULTILINE)
    shell_time = bool(real_line and user_line and sys_line)

    # Accept GNU /usr/bin/time's default compact report.
    gnu_compact = bool(re.search(
        rf'{number}user\\s+{number}system\\s+' 
        rf'(?:\\d+:)?{number}elapsed\\s+{number}%cpu',
        content,
        re.IGNORECASE,
    ))

    # Accept GNU time -v output, requiring its independent user, system, and
    # elapsed measurements rather than merely a timing-related word.
    verbose_user = re.search(rf'^\\s*user time \\(seconds\\):\\s*{number}\\s*$', content, re.MULTILINE)
    verbose_system = re.search(rf'^\\s*system time \\(seconds\\):\\s*{number}\\s*$', content, re.MULTILINE)
    verbose_elapsed = re.search(
        rf'^\\s*elapsed \\(wall clock\\) time.*:\\s*(?:\\d+:)+{number}\\s*$',
        content,
        re.MULTILINE,
    )
    gnu_verbose = bool(verbose_user and verbose_system and verbose_elapsed)

    assert shell_time or gnu_compact or gnu_verbose, (
        f"The file {file_path} does not contain a complete, standard benchmark "
        "report with real/elapsed, user, and system timing measurements."
    )

    exit_status = re.search(r'^\\s*exit status:\\s*(\\d+)\\s*$', content, re.MULTILINE)
    if exit_status:
        assert exit_status.group(1) == '0', "The benchmarked command did not complete successfully."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
