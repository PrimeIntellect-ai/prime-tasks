#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SOURCE = "/home/user/process_logs.c"
BINARY = "/home/user/process_logs"
REBUILT = "/tmp/rebuilt_process_logs"
RAW = "/home/user/raw_logs.txt"
OUTPUT = "/home/user/rolling_stats.csv"

CANONICAL_RAW = """[2023-10-12 10:00:00.123] INFO duration=100
[2023-10-12 10:00:00.456] INFO duration=200
[2023-10-12 10:00:01.001] ERROR something wrong
[2023-10-12 10:00:02.999] INFO duration=150
junk line
[2023-10-12 10:00:05.000] INFO duration=50
[2023-10-12 10:00:07.123] INFO duration=200
[2023-10-12 10:00:08.000] INFO duration=250
"""

CANONICAL_EXPECTED = """2023-10-12 10:00:00,100.00
2023-10-12 10:00:02,125.00
2023-10-12 10:00:05,100.00
2023-10-12 10:00:07,133.33
2023-10-12 10:00:08,166.67"""


def run_case(executable, raw_content, expected):
    with open(RAW, "w") as f:
        f.write(raw_content)
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == expected, (
        f"Output from {executable} does not match expected output.\n"
        f"Expected:\n{expected}\n\nGot:\n{content}"
    )


def make_random_case(rng):
    seconds = rng.sample(range(60), 7)
    order = [seconds[0], seconds[0], seconds[1], seconds[2],
             seconds[1], seconds[3], seconds[4], seconds[4],
             seconds[5], seconds[6]]
    values = [rng.randint(1, 5000) for _ in order]
    seen = set()
    kept = []
    lines = []

    malformed = [
        "junk line",
        "[2023-10-12 11:22:33.123] ERROR duration=99",
        "[2023-10-12 11:22:33.12] INFO duration=99",
        "[2023-10-12 11:22:33.123]  INFO duration=99",
        " [2023-10-12 11:22:33.123] INFO duration=99",
        "[2023-10-12 11:22:33.123] INFO duration=99 trailing",
        "[2023-10-12 11:22:33.123 INFO duration=99",
        "[2023-10-12 11:22:33.123] INFO duration=12x",
    ]

    for i, (second, value) in enumerate(zip(order, values)):
        if i < len(malformed):
            lines.append(malformed[i])
        millis = rng.randrange(1000)
        lines.append(
            f"[2023-10-12 11:22:{second:02d}.{millis:03d}] INFO duration={value}"
        )
        if second not in seen:
            seen.add(second)
            kept.append((second, value))

    expected_lines = []
    durations = []
    for second, value in kept:
        durations.append(value)
        window = durations[-3:]
        average = sum(window) / len(window)
        expected_lines.append(
            f"2023-10-12 11:22:{second:02d},{average:.2f}"
        )
    return "\n".join(lines) + "\n", "\n".join(expected_lines)


def test_c_source_exists():
    path = SOURCE
    assert os.path.exists(path), f"C source file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."


def test_compiled_binary_exists():
    path = BINARY
    assert os.path.exists(path), f"Compiled binary {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary."


def test_source_compiles():
    result = subprocess.run(
        ["gcc", SOURCE, "-o", REBUILT], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"C source does not compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_rolling_stats_csv_content():
    run_case(BINARY, CANONICAL_RAW, CANONICAL_EXPECTED)


def test_program_on_altered_inputs():
    rng = random.SystemRandom()
    for _ in range(3):
        raw_content, expected = make_random_case(rng)
        run_case(BINARY, raw_content, expected)
        run_case(REBUILT, raw_content, expected)


def test_zz_restore_required_output():
    run_case(BINARY, CANONICAL_RAW, CANONICAL_EXPECTED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
