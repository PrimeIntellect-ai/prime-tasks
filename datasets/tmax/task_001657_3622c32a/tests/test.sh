#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/log_analyzer.c"
EXECUTABLE = "/home/user/log_analyzer_fixed"
PROVIDED_LOG = "/home/user/data/event_log.bin"
EXPECTED_PROVIDED = b"Processed 6 events, Type1 length sum: 216\n"


def run_analyzer(executable, log_path, extra_env=None):
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    try:
        proc = subprocess.run(
            [executable, log_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out while processing {log_path}")
    assert proc.returncode == 0, (
        f"{executable} exited with {proc.returncode} while processing {log_path}; "
        f"stderr={proc.stderr.decode(errors='replace')!r}"
    )
    return proc.stdout


def write_log(path, events):
    with open(path, "wb") as f:
        for index, (event_type, length) in enumerate(events):
            assert 0 <= length <= 65535
            f.write(struct.pack("<IHH", 0x45564E54, event_type, length))
            f.write(bytes([(index * 37 + event_type) & 0xff]) * length)


def expected_output(events):
    total = sum(length for event_type, length in events if event_type == 1)
    return f"Processed {len(events)} events, Type1 length sum: {total}\n".encode()


def generated_cases():
    cases = [
        [(1, 0), (1, 1), (1, 63), (1, 64), (1, 65), (1, 100), (1, 1024)],
        [(2, 65535), (1, 65535), (3, 17), (1, 64), (2, 9)],
    ]
    rng = random.SystemRandom()
    for _ in range(4):
        events = [(1, 64), (1, 65), (1, rng.randint(4096, 65535))]
        for _ in range(rng.randint(4, 10)):
            events.append((rng.choice([1, 1, 2, 3]), rng.randint(0, 65535)))
        rng.shuffle(events)
        cases.append(events)
    return cases


def exercise(executable, extra_env=None):
    with tempfile.TemporaryDirectory() as td:
        for index, events in enumerate(generated_cases()):
            path = os.path.join(td, f"case_{index}.bin")
            write_log(path, events)
            actual = run_analyzer(executable, path, extra_env)
            assert actual == expected_output(events), (
                f"Wrong output for generated case {index}: {actual!r}"
            )


def test_result_file_exists():
    assert os.path.isfile("/home/user/result.txt"), "/home/user/result.txt is missing"


def test_result_file_content():
    with open("/home/user/result.txt", "r") as f:
        content = f.read().strip()
    expected_output_text = "Processed 6 events, Type1 length sum: 216"
    assert content == expected_output_text, f"Expected '{expected_output_text}', but got '{content}'"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is missing"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable"


def test_source_code_modified():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing"


def test_submitted_program_and_result_are_from_provided_log():
    actual = run_analyzer(EXECUTABLE, PROVIDED_LOG)
    assert actual == EXPECTED_PROVIDED, f"Unexpected program output: {actual!r}"
    with open("/home/user/result.txt", "rb") as f:
        result = f.read()
    assert result == actual, "result.txt is not the exact output of the fixed program on event_log.bin"


def test_submitted_program_handles_edge_and_large_lengths():
    exercise(EXECUTABLE)


def test_fixed_source_is_memory_safe_and_matches_behavior():
    with tempfile.TemporaryDirectory() as td:
        sanitized = os.path.join(td, "log_analyzer_sanitized")
        compile_proc = subprocess.run(
            [
                "gcc", SOURCE, "-o", sanitized,
                "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-g"
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_proc.returncode == 0, (
            "The modified source does not compile: "
            + compile_proc.stderr.decode(errors="replace")
        )
        exercise(sanitized, {"ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1"})
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
