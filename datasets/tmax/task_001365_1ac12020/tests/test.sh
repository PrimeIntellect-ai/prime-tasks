#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/loc_filter"
SOURCE = "/home/user/loc_filter.c"


def run_filter(executable, duration, data):
    return subprocess.run(
        [executable, f"{duration:.6f}"],
        input=data,
        capture_output=True,
        text=True,
        timeout=4,
    )


def assert_result(executable, duration, data, expected):
    result = run_filter(executable, duration, data)
    expected_code = 0 if expected == "ACCEPT" else 1
    assert result.returncode == expected_code, (
        f"Expected exit {expected_code} for {expected}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"Expected stdout {expected!r}, got {result.stdout!r}"
    )


def make_line(start, end, text, style=0):
    if style % 3 == 0:
        return f'{{"start_ts": {start:.8f}, "end_ts": {end:.8f}, "text": "{text}"}}\n'
    if style % 3 == 1:
        return f'{{  "text" : "{text}", "start_ts"   : {start:.8f}, "end_ts" : {end:.8f} }}\n'
    return f'{{\t"start_ts"\t:\t{start:.8f},\t"text": "{text}",\t"end_ts"\t:\t{end:.8f}\t}}\n'


@pytest.fixture(scope="session")
def rebuilt_executable():
    assert os.path.exists(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty"

    build_dir = tempfile.mkdtemp(prefix="loc_filter_build_")
    rebuilt = os.path.join(build_dir, "loc_filter_rebuilt")
    result = subprocess.run(
        ["/usr/bin/gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"C source failed to compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    return rebuilt


def test_loc_filter_executable_exists():
    executable_path = "/home/user/loc_filter"
    assert os.path.exists(executable_path), f"Executable not found at {executable_path}"
    assert os.path.isfile(executable_path), f"{executable_path} is not a file"
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled native executable"


def test_clean_corpus():
    executable_path = "/home/user/loc_filter"
    clean_dir = "/app/corpus/clean/"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.jsonl')]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, 'r') as f:
            result = subprocess.run([executable_path, "14.25"], stdin=f, capture_output=True, text=True)

        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected or crashed). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    executable_path = "/home/user/loc_filter"
    evil_dir = "/app/corpus/evil/"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.jsonl')]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, 'r') as f:
            result = subprocess.run([executable_path, "14.25"], stdin=f, capture_output=True, text=True)

        if result.returncode != 1 or "REJECT" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted or wrong exit code). Offending files: {', '.join(failed_files)}")


def test_generated_unseen_inputs(rebuilt_executable):
    rng = random.SystemRandom()
    executables = [EXECUTABLE, rebuilt_executable]
    alphabet = string.ascii_letters + string.digits

    cases = []

    # Valid, randomized multi-line files. These include arbitrary spacing,
    # files without the visible fixture's words, valid escapes, and end times
    # both below and within the allowed 0.1-second duration tolerance.
    for case_index in range(10):
        duration = rng.uniform(7.0, 31.0)
        lines = []
        count = rng.randint(1, 5)
        for line_index in range(count):
            start = rng.uniform(0.0, duration * 0.65)
            if line_index == count - 1 and case_index % 2 == 0:
                end = duration + rng.uniform(0.01, 0.07)
            else:
                end = rng.uniform(start + 0.01, duration)
            token = ''.join(rng.choice(alphabet) for _ in range(rng.randint(8, 30)))
            if line_index % 2 == 0:
                token += " \\u" + f"{rng.randrange(65536):04X}"
            lines.append(make_line(start, end, token, rng.randrange(3)))
        cases.append((duration, ''.join(lines), "ACCEPT"))

    # Randomized timing failures: reversed/equal timestamps and duration
    # violations. Several contain the word from the visible clean fixture.
    for index in range(12):
        duration = rng.uniform(6.0, 35.0)
        mode = index % 3
        if mode == 0:
            start = rng.uniform(1.0, duration)
            end = start - rng.uniform(0.001, min(0.9, start))
        elif mode == 1:
            start = rng.uniform(0.0, duration * 0.8)
            end = start
        else:
            start = rng.uniform(0.0, duration * 0.7)
            end = duration + rng.uniform(0.15, 2.0)
        token = "World_" + ''.join(rng.choice(alphabet) for _ in range(16))
        cases.append((duration, make_line(start, end, token, index), "REJECT"))

    # Malformed unicode escapes with the bad character in each of the four
    # required hex positions, plus truncated escapes and malformed data late
    # in a large input line.
    hexchars = "0123456789abcdefABCDEF"
    badchars = "gGzZ_-+/"
    for index in range(12):
        duration = rng.uniform(8.0, 25.0)
        prefix_len = index % 4
        prefix = ''.join(rng.choice(hexchars) for _ in range(prefix_len))
        bad = rng.choice(badchars)
        malformed = "prefix" + ''.join(rng.choice(alphabet) for _ in range(10)) + " \\u" + prefix + bad + "tail"
        cases.append((duration, make_line(0.25, duration * 0.7, malformed, index), "REJECT"))

    for length in range(4):
        duration = rng.uniform(9.0, 20.0)
        truncated = "short_" + ''.join(rng.choice(alphabet) for _ in range(6)) + " \\u" + ''.join(rng.choice(hexchars) for _ in range(length))
        cases.append((duration, make_line(0.1, duration * 0.5, truncated, length), "REJECT"))

    duration = rng.uniform(10.0, 20.0)
    long_text = ''.join(rng.choice(alphabet) for _ in range(180000)) + " \\u12Q4"
    cases.append((duration, make_line(0.0, duration * 0.9, long_text, 2), "REJECT"))

    # A late anomaly ensures the complete stream, rather than only its first
    # object, is checked.
    duration = rng.uniform(11.0, 22.0)
    good_lines = ''.join(
        make_line(i * 0.2, i * 0.2 + 0.1, ''.join(rng.choice(alphabet) for _ in range(20)), i)
        for i in range(20)
    )
    cases.append((duration, good_lines + make_line(3.0, 2.5, "World_late_failure", 1), "REJECT"))

    rng.shuffle(cases)
    for executable in executables:
        for duration, data, expected in cases:
            assert_result(executable, duration, data, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
