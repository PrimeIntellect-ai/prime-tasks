#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess

SOURCE = "/home/user/process.cpp"
EXE = "/home/user/process"
INPUT = "/home/user/data/chats.txt"
OUTPUT_DIR = "/home/user/output"
OUTPUT = "/home/user/output/deduped.tsv"
REBUILT = "/tmp/process_from_source"


def test_01_cpp_source_exists():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."


def test_02_executable_exists_is_native_and_runs():
    assert os.path.isfile(EXE), f"{EXE} is missing."
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE} is not a compiled native executable."

    result = subprocess.run([EXE], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Running {EXE} failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )


def test_03_original_output_tsv_correct():
    assert os.path.isfile(OUTPUT), f"{OUTPUT} was not created."
    expected_lines = [
        "3600\ten\tHello world",
        "3600\tes\tHola mundo",
        "3600\tfr\tBonjour",
        "7200\ten\tHello world",
        "7200\tzh\t你好",
        "7200\tzh\t你好吗",
    ]
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual_lines = [line.strip("\n") for line in f if line.strip("\n")]
    assert actual_lines == expected_lines, (
        "The contents of deduped.tsv do not match the expected deduplicated output."
    )


def test_04_source_compiles_with_required_command():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process.cpp did not compile: {result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    with open(REBUILT, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def expected_output(records):
    seen_by_bucket = {}
    lines = []
    for timestamp, language, message in records:
        bucket = (timestamp // 3600) * 3600
        key = (language, message)
        seen = seen_by_bucket.setdefault(bucket, set())
        if key not in seen:
            seen.add(key)
            lines.append(f"{bucket}\t{language}\t{message}")
    return lines


def run_case(executable, records):
    os.makedirs(os.path.dirname(INPUT), exist_ok=True)
    with open(INPUT, "w", encoding="utf-8", newline="\n") as f:
        for timestamp, language, message in records:
            f.write(f"{timestamp}|{language}|{message}\n")

    if os.path.isdir(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)
    assert not os.path.exists(OUTPUT_DIR)

    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Running {executable} failed with return code {result.returncode}: {result.stderr}"
    )
    assert os.path.isdir(OUTPUT_DIR), "The processor did not create /home/user/output/."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} was not created."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()
    assert actual == expected_output(records), (
        f"Incorrect output from {executable}.\nExpected: {expected_output(records)!r}\n"
        f"Actual: {actual!r}"
    )


def test_05_dynamic_parsing_bucketing_deduplication_and_utf8():
    token = secrets.token_hex(12)
    base = (100000 + secrets.randbelow(800000)) * 3600
    records = [
        (base + 3, "en", f"hello-{token}"),
        (base + 8, "ja", f"こんにちは-{token}"),
        (base + 11, "en", f"hello-{token}"),
        (base + 19, "es", f"hello-{token}"),
        (base + 3599, "fr", f"café 🚀-{token}"),
        (base + 3601, "en", f"hello-{token}"),
        (base + 3604, "zh", f"你好-{token}"),
        (base + 3608, "zh", f"你好-{token}"),
        (base + 7199, "ar", f"مرحبا-{token}"),
        (base + 7200, "zh", f"你好-{token}"),
    ]

    rng = secrets.SystemRandom()
    languages = ["en", "es", "de", "ko", "pt"]
    messages = [
        f"alpha-{token}",
        f"βeta-{token}",
        f"emoji-🎉-{token}",
        f"mañana-{token}",
    ]
    generated = []
    for hour in range(4):
        for offset in range(20):
            generated.append((
                base + 10800 + hour * 3600 + offset * 41,
                rng.choice(languages),
                rng.choice(messages),
            ))

    for executable in (EXE, REBUILT):
        run_case(executable, records)
        run_case(executable, generated)


def test_06_cron_file_correct_and_single_line():
    cron_path = "/home/user/mycron"
    assert os.path.isfile(cron_path), f"{cron_path} is missing."
    with open(cron_path, "r", encoding="utf-8") as f:
        raw = f.read()
    content = raw.strip()

    pattern = r"^0\s+2\s+\*\s+\*\s+\*\s+/home/user/process$"
    match = re.search(pattern, content, re.MULTILINE)
    assert match is not None, (
        f"{cron_path} does not contain the correct cron expression. Found: {content}"
    )
    assert len(raw.splitlines()) == 1, f"{cron_path} must contain exactly one line."
    assert re.fullmatch(pattern, content) is not None, (
        f"{cron_path} must contain only the required cron entry."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
