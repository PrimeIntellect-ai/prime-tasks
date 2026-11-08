#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

FILTER_C = Path("/home/user/filter.c")
PIPELINE = Path("/home/user/pipeline.sh")
RAW = Path("/home/user/raw.jsonl")
CLEAN = Path("/home/user/clean.jsonl")
FILTER_BIN = Path("/home/user/filter")

CANONICAL_RAW = [
    r'{"ts":"2023-10-01T10:00:00Z","user":"admin","key":"database","val":"mysql"}',
    r'{"ts":"2023-10-01T10:05:00Z","user":"admin","key":"password","val":"super\u0053ecret\u0021"}',
    r'{"ts":"2023-10-01T10:00:00Z","user":"admin","key":"database","val":"mysql"}',
    r'{"ts":"2023-10-01T10:10:00Z","user":"alice","key":"api_key","val":"sk_test_\u0031\u0032\u0033"}',
    r'{"ts":"2023-10-01T10:15:00Z","user":"bob","key":"theme","val":"dark"}',
    r'{"ts":"2023-10-01T10:15:00Z","user":"bob","key":"theme","val":"dark"}',
    r'{"ts":"2023-10-01T10:20:00Z","user":"charlie","key":"greeting","val":"hello\u0020world"}',
]

EXPECTED_CANONICAL = [
    r'{"ts":"2023-10-01T10:00:00Z","user":"admin","key":"database","val":"mysql"}',
    r'{"ts":"2023-10-01T10:05:00Z","user":"admin","key":"password","val":"***"}',
    r'{"ts":"2023-10-01T10:10:00Z","user":"alice","key":"api_key","val":"***"}',
    r'{"ts":"2023-10-01T10:15:00Z","user":"bob","key":"theme","val":"dark"}',
    r'{"ts":"2023-10-01T10:20:00Z","user":"charlie","key":"greeting","val":"hello world"}',
]


def reference_filter(line):
    decoded = re.sub(
        r"\\u00([0-9A-Fa-f]{2})",
        lambda match: chr(int(match.group(1), 16)),
        line,
    )
    if '"key":"password"' in decoded or '"key":"api_key"' in decoded:
        decoded, count = re.subn(r'("val":")[^"]*("})$', r'\1***\2', decoded)
        assert count == 1
    return decoded


def run_pipeline(lines):
    RAW.write_text("\n".join(lines) + "\n")
    if CLEAN.exists():
        CLEAN.unlink()
    if FILTER_BIN.exists() or FILTER_BIN.is_symlink():
        FILTER_BIN.unlink()

    env = os.environ.copy()
    env["LC_ALL"] = "C"
    result = subprocess.run(
        [str(PIPELINE)],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert FILTER_BIN.is_file(), "pipeline.sh did not compile /home/user/filter"
    assert os.access(FILTER_BIN, os.X_OK), "/home/user/filter is not executable"
    assert CLEAN.is_file(), "pipeline.sh did not create /home/user/clean.jsonl"


def test_pipeline_files_exist():
    assert os.path.isfile("/home/user/filter.c"), "Missing /home/user/filter.c"
    assert os.path.isfile("/home/user/pipeline.sh"), "Missing /home/user/pipeline.sh"
    assert os.access("/home/user/pipeline.sh", os.X_OK), "/home/user/pipeline.sh is not executable"


def test_clean_jsonl_output_after_running_pipeline():
    run_pipeline(CANONICAL_RAW)

    with open(CLEAN, "r") as f:
        content = f.read().strip()

    expected_sorted = sorted(EXPECTED_CANONICAL)
    actual_lines = content.split("\n") if content else []

    assert len(actual_lines) == len(expected_sorted), (
        f"Expected {len(expected_sorted)} lines in {CLEAN}, found {len(actual_lines)}"
    )
    for expected, actual in zip(expected_sorted, actual_lines):
        assert expected == actual, (
            f"Line mismatch in {CLEAN}.\nExpected: {expected}\nActual: {actual}"
        )


def test_filter_c_compiles_and_processes_generated_input(tmp_path):
    binary = tmp_path / "compiled_filter"
    compile_result = subprocess.run(
        ["gcc", str(FILTER_C), "-o", str(binary)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"filter.c failed to compile\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    token = secrets.token_hex(8)
    lines = [
        rf'{{"id":"{token}-1","key":"normal","val":"hello\u0020world\u0021"}}',
        rf'{{"id":"{token}-2","key":"password","val":"secret-{token}\u0021"}}',
        rf'{{"id":"{token}-3","key":"api_key","val":"key-\u0041\u006a-{token}"}}',
        rf'{{"id":"{token}-4","key":"passw\u006Frd","val":"decoded-key-{token}"}}',
        rf'{{"id":"{token}-5","key":"password_backup","val":"keep-{token}\u003Dyes"}}',
    ]
    input_text = "\n".join(lines) + "\n"
    expected = "\n".join(reference_filter(line) for line in lines) + "\n"
    result = subprocess.run(
        [str(binary)],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"compiled filter failed: {result.stderr}"
    assert result.stdout == expected, (
        f"filter output mismatch\nExpected:\n{expected}\nActual:\n{result.stdout}"
    )


def test_pipeline_on_generated_input_sorts_and_deduplicates():
    token = secrets.token_hex(10)
    lines = [
        rf'{{"id":"z-{token}","key":"normal","val":"last\u0021"}}',
        rf'{{"id":"a-{token}","key":"password","val":"pw-{token}\u003Dvalue"}}',
        rf'{{"id":"m-{token}","key":"api_key","val":"api-{token}"}}',
        rf'{{"id":"b-{token}","key":"normal","val":"space\u0020value"}}',
        rf'{{"id":"c-{token}","key":"passw\u006Frd","val":"hidden-{token}"}}',
        rf'{{"id":"d-{token}","key":"password_hint","val":"keep-{token}\u0021"}}',
        rf'{{"id":"b-{token}","key":"normal","val":"space\u0020value"}}',
        rf'{{"id":"z-{token}","key":"normal","val":"last\u0021"}}',
    ]
    # Avoid giving a hardcoded fixture: expected answers are derived from fresh input.
    expected = sorted(set(reference_filter(line) for line in lines))
    run_pipeline(lines)
    actual = CLEAN.read_text().splitlines()
    assert actual == expected, (
        "Generated pipeline output was not decoded, masked, sorted, and deduplicated correctly.\n"
        f"Expected: {expected}\nActual: {actual}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
