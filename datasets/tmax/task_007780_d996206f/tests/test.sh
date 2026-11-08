#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SOURCE = "/home/user/process_loc.c"
EXECUTABLE = "/home/user/process_loc"
INPUT = "/home/user/translations.csv"
OUTPUT = "/home/user/hourly_stats.csv"
COMPILED_TEST_EXECUTABLE = "/tmp/process_loc_from_source"


def test_source_file_exists():
    """Test that the C source code file was created."""
    assert os.path.exists(SOURCE), f"Missing required file: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Path is not a file: {SOURCE}"


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.exists(EXECUTABLE), f"Missing compiled executable: {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"Path is not a file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled executable is not an ELF binary: {EXECUTABLE}"


def read_output():
    assert os.path.exists(OUTPUT), f"Missing output file: {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Path is not a file: {OUTPUT}"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(program, expected_lines):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    actual_lines = read_output()
    assert actual_lines == expected_lines, (
        f"The contents of {OUTPUT} do not match the expected output.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def make_generated_input():
    records = [
        (1712340001, "es_ES", "idA", "Alpha\nBeta"),
        (1712343599, "es_ES", "idB", ""),
        (1712343600, "fr_FR", "idC", "Ne doit pas compter"),
        (1712347205, "es_ES", "idD", "Uno, dos\n\nTRES 123"),
    ]
    alphabet = "abcXYZ 0123,.!?\n"
    base = 1720000000 + secrets.randbelow(500000)
    for i in range(36):
        ts = base + secrets.randbelow(5 * 3600)
        locale = "es_ES" if secrets.randbelow(4) != 0 else "fr_FR"
        text = "".join(alphabet[secrets.randbelow(len(alphabet))]
                       for _ in range(secrets.randbelow(90)))
        records.append((ts, locale, f"r{i}", text))

    # Randomize record order so chronological sorting must be performed.
    for i in range(len(records) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        records[i], records[j] = records[j], records[i]

    totals = {}
    chunks = []
    for ts, locale, msg_id, text in records:
        chunks.append(f'{ts},{locale},{msg_id},"{text}"\n')
        if locale == "es_ES":
            bucket = (ts // 3600) * 3600
            count = sum(('A' <= ch <= 'Z') or ('a' <= ch <= 'z') for ch in text)
            totals[bucket] = totals.get(bucket, 0) + count

    expected = [f"{bucket},{totals[bucket]}" for bucket in sorted(totals)]
    return "".join(chunks).encode("utf-8"), expected


def test_hourly_stats_content_and_behavior():
    """Compile and execute the implementation on the supplied and generated CSVs."""
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", COMPILED_TEST_EXECUTABLE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"Could not compile {SOURCE}.\nstdout: {compile_result.stdout}\n"
        f"stderr: {compile_result.stderr}"
    )

    with open(INPUT, "rb") as f:
        original_input = f.read()

    expected_original = [
        "1699999200,20",
        "1700002800,28",
        "1700006400,11"
    ]
    valid_original_output = None

    try:
        # The required executable must actually generate the supplied result.
        run_and_check(EXECUTABLE, expected_original)
        with open(OUTPUT, "rb") as f:
            valid_original_output = f.read()

        generated_input, generated_expected = make_generated_input()
        with open(INPUT, "wb") as f:
            f.write(generated_input)

        # Exercise both the submitted executable and a fresh build of its source.
        run_and_check(EXECUTABLE, generated_expected)
        run_and_check(COMPILED_TEST_EXECUTABLE, generated_expected)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if valid_original_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(valid_original_output)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
