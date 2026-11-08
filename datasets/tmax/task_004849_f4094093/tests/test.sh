#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import string
import subprocess

SRC_DIR = "/home/user/src"
SOURCE = "/home/user/src/extractor.c"
MAKEFILE = "/home/user/src/Makefile"
RAW_FILE = "/home/user/data/raw_logs.tsv"
OUTPUT_DIR = "/home/user/output"
OUTPUT_FILE = "/home/user/output/features.csv"


def test_c_file_exists():
    """Check that the C source file exists."""
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."


def test_makefile_exists():
    """Check that the Makefile exists."""
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."


def test_pipeline_execution_and_output():
    """Run the pipeline via make and verify the provided input."""
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        ["make", "run"],
        cwd=SRC_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"'make run' failed with return code {result.returncode}.\n"
        f"stderr: {result.stderr}\nstdout: {result.stdout}"
    )
    assert os.path.isfile(OUTPUT_FILE), (
        f"Output file {OUTPUT_FILE} was not created after running 'make run'."
    )

    expected_lines = [
        "1670000000,S1,2",
        "1670000060,S2,2",
        "1670000120,S1,1",
        "1670000180,S3,0",
        "1670000240,S1,3",
    ]

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        actual_content = f.read().strip().splitlines()

    assert len(actual_content) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in output, but got {len(actual_content)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_content, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
        )


def test_extractor_and_pipeline_on_additional_input_and_create_directory():
    """Compile the submitted C source and exercise it and make run on fresh data."""
    raw_backup = open(RAW_FILE, "rb").read()
    token = "".join(secrets.choice(string.ascii_letters) for _ in range(12))
    records = [
        (str(1800000000 + secrets.randbelow(1000000)), "R" + secrets.token_hex(3),
         f"{token}42BETA...gamma"),
        (str(1801000000 + secrets.randbelow(1000000)), "N" + secrets.token_hex(3),
         "12345---_!?"),
        (str(1802000000 + secrets.randbelow(1000000)), "M" + secrets.token_hex(3),
         "One_two THREE9four;five-six"),
        (str(1803000000 + secrets.randbelow(1000000)), "Z" + secrets.token_hex(3),
         "a1B2c3D"),
    ]
    expected = [
        f"{timestamp},{sensor},{len(re.findall(r'[A-Za-z]+', message))}"
        for timestamp, sensor, message in records
    ]
    dynamic_tsv = "".join(
        f"{timestamp}\t{sensor}\t{message.encode('ascii').hex()}\n"
        for timestamp, sensor, message in records
    )

    try:
        with open(RAW_FILE, "w", encoding="ascii", newline="") as f:
            f.write(dynamic_tsv)

        compiled = "/tmp/submitted_extractor"
        build = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", compiled],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert build.returncode == 0, (
            f"extractor.c did not compile independently.\n"
            f"stderr: {build.stderr}\nstdout: {build.stdout}"
        )

        # Accept either of the interfaces permitted by the instruction: TSV on
        # stdin, or a TSV filename argument. Output may be stdout or the required
        # features.csv file.
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        direct_ok = False
        attempts = [([compiled], dynamic_tsv), ([compiled, RAW_FILE], None)]
        for command, stdin_data in attempts:
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
            try:
                result = subprocess.run(
                    command,
                    input=stdin_data,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                continue
            candidates = []
            if result.stdout.strip():
                candidates.append(result.stdout.strip().splitlines())
            if os.path.isfile(OUTPUT_FILE):
                with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
                    candidates.append(f.read().strip().splitlines())
            if result.returncode == 0 and expected in candidates:
                direct_ok = True
                break
        assert direct_ok, (
            "The independently compiled extractor.c did not correctly process "
            "the additional TSV input via stdin or a file input."
        )

        # Remove the entire directory, not just the file, to verify that the
        # submitted orchestration recreates it as required.
        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
        result = subprocess.run(
            ["make", "run"],
            cwd=SRC_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"'make run' failed on additional input.\n"
            f"stderr: {result.stderr}\nstdout: {result.stdout}"
        )
        assert os.path.isdir(OUTPUT_DIR), "'make run' did not create /home/user/output."
        assert os.path.isfile(OUTPUT_FILE), (
            "'make run' did not create /home/user/output/features.csv."
        )
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            actual = f.read().strip().splitlines()
        assert actual == expected, (
            f"Pipeline output for additional input was incorrect.\n"
            f"Expected: {expected}\nGot: {actual}"
        )
    finally:
        with open(RAW_FILE, "wb") as f:
            f.write(raw_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
