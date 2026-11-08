#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from collections import defaultdict


def test_cron_file_exists_and_correct():
    cron_path = "/home/user/pipeline.cron"
    assert os.path.isfile(cron_path), f"Cron file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read()

    # Check if the required cron string is in the file
    expected_cron = r"15\s+\*\s+\*\s+\*\s+\*\s+/home/user/bin/process_events"
    assert re.search(expected_cron, content), f"Cron configuration is incorrect. Expected to find '15 * * * * /home/user/bin/process_events' in {cron_path}."


def test_executable_exists():
    exe_path = "/home/user/bin/process_events"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def test_processed_events_output():
    output_path = "/home/user/data/processed_events.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_lines = [
        "2023-10-25-14,a***@corp.com,300",
        "2023-10-25-14,b***@startup.io,50",
        "2023-10-25-15,b***@startup.io,150",
        "2023-10-25-15,c***@domain.com,300",
        "2023-10-25-15,d***@test.com,50",
        "2023-10-26-09,a***@corp.com,500"
    ]

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The contents of processed_events.csv do not match the expected aggregated output. Ensure bad rows are dropped, emails are anonymized correctly, amounts are summed, and output is sorted."


def _make_case():
    tag = secrets.token_hex(6)
    domain = f"{tag}.example"
    other_domain = f"other-{tag}.test"
    year = 2024 + secrets.randbelow(2)
    month = 1 + secrets.randbelow(9)
    day = 10 + secrets.randbelow(10)
    hour1 = secrets.randbelow(12)
    hour2 = 12 + secrets.randbelow(12)

    def ts(hour, minute):
        return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:00Z"

    records = [
        (ts(hour1, 3), f"alice-{tag}@{domain}", "deposit", 10 + secrets.randbelow(90)),
        (ts(hour1, 17), f"adam-{tag}@{domain}", "withdrawal", 100 + secrets.randbelow(90)),
        (ts(hour1, 49), f"q@{other_domain}", "deposit", 200 + secrets.randbelow(90)),
        (ts(hour2, 4), f"alice-{tag}@{domain}", "deposit", 300 + secrets.randbelow(90)),
        (ts(hour2, 38), f"zulu-{tag}@{other_domain}", "withdrawal", 400 + secrets.randbelow(90)),
        (ts(hour2, 51), f"zebra-{tag}@{other_domain}", "deposit", 500 + secrets.randbelow(90)),
    ]

    groups = defaultdict(int)
    valid_lines = []
    for timestamp, email, event_type, amount in records:
        valid_lines.append(f"{timestamp},{email},{event_type},{amount}")
        username, email_domain = email.split("@", 1)
        bucket = timestamp[:10] + "-" + timestamp[11:13]
        masked = username[0] + "***@" + email_domain
        groups[(bucket, masked)] += amount

    malformed = [
        f"{ts(hour1, 22)},broken-{tag}@{domain},description",
        "continued text,700",
        "invalid,row,format",
        f"{ts(hour2, 23)},extra-{tag}@{domain},deposit,12,unexpected",
    ]
    input_lines = valid_lines[:2] + malformed[:2] + valid_lines[2:4] + malformed[2:] + valid_lines[4:]
    expected = [f"{bucket},{email},{total}" for (bucket, email), total in sorted(groups.items())]
    return ("\n".join(input_lines) + "\n").encode(), expected


def _run_and_check(executable, raw_path, output_path):
    fixture, expected = _make_case()
    with open(raw_path, "wb") as f:
        f.write(fixture)
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{executable} failed on a changed input: {result.stderr}"
    assert os.path.isfile(output_path), f"{executable} did not create {output_path}."
    with open(output_path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"{executable} produced incorrect output for a changed input."


def test_program_executes_and_processes_changed_inputs(tmp_path):
    source_path = "/home/user/process_events.c"
    exe_path = "/home/user/bin/process_events"
    raw_path = "/home/user/data/raw_events.csv"
    output_path = "/home/user/data/processed_events.csv"

    assert os.path.isfile(source_path), f"C source file {source_path} does not exist."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled executable."

    rebuilt_path = str(tmp_path / "process_events_rebuilt")
    compile_result = subprocess.run(
        ["gcc", source_path, "-o", rebuilt_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"The submitted C source does not compile with gcc: {compile_result.stderr}"

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_output = None
    if os.path.isfile(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    try:
        _run_and_check(exe_path, raw_path, output_path)
        _run_and_check(rebuilt_path, raw_path, output_path)
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
