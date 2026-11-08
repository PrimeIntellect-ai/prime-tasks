#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
SOURCE = HOME / "processor.c"
BINARY = HOME / "processor"
RAW = HOME / "raw_dataset.txt"
CSV = HOME / "cleaned.csv"
LOG = HOME / "pipeline.log"
RECOMPILED = Path("/tmp/recompiled_processor")

ORIGINAL_INPUT = """---RECORD---
ID: 1
Date: 2023-01-01
Text: Hello
World
---RECORD---
ID: 2
Date: 2023-01-02
Text: Good
morning
everyone
---RECORD---
ID: 3
Text: No date here
---RECORD---
ID: 4
Date: 2023-01-04
Text: Yes
---RECORD---
ID: 5
Date: 2023-01-05
---RECORD---
ID: 6
Date: 2023-01-06
Text: The final
valid
record.
"""


def run_processor(program, raw_text):
    RAW.write_text(raw_text)
    CSV.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    result = subprocess.run(
        [str(program)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{program} failed with exit code {result.returncode}: {result.stderr}"
    )


@pytest.fixture(scope="module", autouse=True)
def verify_artifacts_and_run_original():
    assert SOURCE.is_file() and not SOURCE.is_symlink(), \
        "Expected /home/user/processor.c to be a regular source file."
    assert BINARY.is_file() and not BINARY.is_symlink(), \
        "Expected /home/user/processor to be a regular compiled file."
    assert os.access(BINARY, os.X_OK), \
        "Expected /home/user/processor to be executable."
    assert stat.S_ISREG(BINARY.stat().st_mode)
    with BINARY.open("rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "Expected /home/user/processor to be a compiled ELF executable."

    compile_result = subprocess.run(
        ["gcc", str(SOURCE), "-o", str(RECOMPILED)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        f"processor.c did not compile: {compile_result.stderr}"

    run_processor(BINARY, ORIGINAL_INPUT)
    yield


def test_cleaned_csv_content():
    csv_path = "/home/user/cleaned.csv"
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "ID,Date,Text,RollingAvgLen\n"
        "1,2023-01-01,Hello World,11.00\n"
        "2,2023-01-02,Good morning everyone,16.00\n"
        "4,2023-01-04,Yes,11.67\n"
        "6,2023-01-06,The final valid record.,14.50"
    )

    assert content == expected_content, f"The content of {csv_path} does not match the expected output."


def test_pipeline_log_content():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Expected log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "ERROR: Skipped invalid record.\n"
        "ERROR: Skipped invalid record."
    )

    assert content == expected_content, f"The content of {log_path} does not match the expected output."


def test_program_handles_additional_input():
    challenge_input = """---RECORD---
ID: 10
Date: 2024-02-01
Text: Alpha
beta
---RECORD---
Date: 2024-02-02
Text: missing id
---RECORD---
ID: 12
Date: 2024-02-03
Text: Z
---RECORD---
ID: 13
Date: 2024-02-04
Text: 
---RECORD---
ID: 14
Date: 2024-02-05
Text: starts

ends"""

    valid = [
        ("10", "2024-02-01", "Alpha beta"),
        ("12", "2024-02-03", "Z"),
        ("14", "2024-02-05", "starts  ends"),
    ]
    rows = ["ID,Date,Text,RollingAvgLen"]
    total = 0
    for index, (record_id, date, text) in enumerate(valid, 1):
        total += len(text)
        rows.append(f"{record_id},{date},{text},{total / index:.2f}")
    expected_csv = "\n".join(rows)
    expected_log = "\n".join(["ERROR: Skipped invalid record."] * 2)

    for program in (BINARY, RECOMPILED):
        run_processor(program, challenge_input)
        assert CSV.is_file(), f"{program} did not create cleaned.csv"
        assert LOG.is_file(), f"{program} did not create pipeline.log"
        assert CSV.read_text().strip() == expected_csv
        assert LOG.read_text().strip() == expected_log
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
