#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
RAW = f"{HOME}/raw_events.csv"
CLEAN = f"{HOME}/clean_events.csv"
AGG = f"{HOME}/aggregated_events.csv"
SOURCE = f"{HOME}/etl_processor.c"
PROCESSOR = f"{HOME}/etl_processor"
SCRIPT = f"{HOME}/run_pipeline.sh"

ORIGINAL_ROWS = [
    "1700000000,101,Alice Smith,alice@example.com,click",
    "1700000050,102,Bob Jones,bob@example.com,view",
    "1700000000,101,Alice Smith,alice@example.com,click",
    "1700003500,103,Charlie Brown,charlie@example.com,purchase",
    "1700003600,101,Alice Smith,alice@example.com,view",
    "1700003600,101,Alice Smith,alice@example.com,view",
    "1700007200,104,Diana Prince,diana@example.com,click",
    "1700000050,102,Bob Jones,bob@example.com,view",
]

EXPECTED_ORIGINAL_CLEAN = [
    "1700000000,101,MASKED,101@anonymized.local,click",
    "1700000050,102,MASKED,102@anonymized.local,view",
    "1700003500,103,MASKED,103@anonymized.local,purchase",
    "1700003600,101,MASKED,101@anonymized.local,view",
    "1700007200,104,MASKED,104@anonymized.local,click",
]

EXPECTED_ORIGINAL_AGG = [
    "1699999200,click,1",
    "1699999200,view,1",
    "1700002800,purchase,1",
    "1700002800,view,1",
    "1700006400,click,1",
]


def write_rows(rows):
    with open(RAW, "w", newline="") as f:
        f.write("\n".join(rows) + "\n")


def read_lines(path):
    assert os.path.isfile(path), f"{path} was not created by the pipeline."
    with open(path, "r") as f:
        return f.read().strip().splitlines()


def expected_for(rows):
    seen = set()
    clean = []
    counts = {}
    for line in rows:
        fields = tuple(line.split(","))
        assert len(fields) == 5
        if fields in seen:
            continue
        seen.add(fields)
        timestamp, user_id, _name, _email, event_type = fields
        clean.append(
            f"{timestamp},{user_id},MASKED,{user_id}@anonymized.local,{event_type}"
        )
        key = ((int(timestamp) // 3600) * 3600, event_type)
        counts[key] = counts.get(key, 0) + 1
    aggregated = [
        f"{bucket},{event_type},{counts[(bucket, event_type)]}"
        for bucket, event_type in sorted(counts)
    ]
    return clean, aggregated


def test_01_run_pipeline_and_original_content():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"{SCRIPT} is not executable."

    write_rows(ORIGINAL_ROWS)
    for path in (CLEAN, AGG, PROCESSOR):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [SCRIPT], cwd=HOME, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT} failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    assert os.path.isfile(PROCESSOR), f"{PROCESSOR} was not recreated."
    mode = os.stat(PROCESSOR).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), (
        f"{PROCESSOR} is not executable."
    )
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{PROCESSOR} is not a compiled ELF executable."
        )

    assert read_lines(CLEAN) == EXPECTED_ORIGINAL_CLEAN, (
        f"Content of {CLEAN} does not match the expected output."
    )
    assert read_lines(AGG) == EXPECTED_ORIGINAL_AGG, (
        f"Content of {AGG} does not match the expected output."
    )


def test_02_processor_handles_unseen_inputs():
    # Random values prevent a submission from passing by emitting the fixed fixture's answers.
    for _ in range(3):
        base = secrets.randbelow(100000) * 3600 + 1400000000
        base -= base % 3600
        uid1 = str(10000 + secrets.randbelow(80000))
        uid2 = str(10000 + secrets.randbelow(80000))
        uid3 = str(10000 + secrets.randbelow(80000))
        tag = secrets.token_hex(5)
        event_a = f"alpha_{tag}"
        event_b = f"zeta_{tag}"
        event_c = f"middle_{tag}"

        first = f"{base + 3599},{uid1},Name {tag},{tag}@one.test,{event_b}"
        second = f"{base + 1},{uid2},Other {tag},{tag}@two.test,{event_a}"
        rows = [
            first,
            second,
            first,
            f"{base + 3600},{uid1},Name {tag},{tag}@one.test,{event_a}",
            f"{base + 7205},{uid3},Third {tag},{tag}@three.test,{event_c}",
            f"{base + 3600},{uid1},Name {tag},{tag}@one.test,{event_a}",
            # This is not an exact duplicate because its source email differs.
            f"{base + 1},{uid2},Other {tag},different-{tag}@two.test,{event_a}",
            f"{base + 7199},{uid3},Fourth {tag},{tag}@four.test,{event_b}",
        ]
        expected_clean, expected_agg = expected_for(rows)
        write_rows(rows)
        for path in (CLEAN, AGG):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [PROCESSOR], cwd=HOME, capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f"Running compiled processor failed with return code {result.returncode}.\n"
            f"Stderr: {result.stderr}"
        )
        assert read_lines(CLEAN) == expected_clean, (
            "clean_events.csv is incorrect for an unseen input."
        )
        assert read_lines(AGG) == expected_agg, (
            "aggregated_events.csv is incorrect for an unseen input."
        )


def test_03_cron_txt_content():
    file_path = f"{HOME}/cron.txt"
    assert os.path.isfile(file_path), f"{file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) >= 6, "cron.txt content is incomplete or malformed."
    cron_schedule = " ".join(parts[:5])
    assert cron_schedule == "0 * * * *", (
        f"Expected cron schedule '0 * * * *', but got '{cron_schedule}'."
    )
    assert SCRIPT in content, (
        "cron.txt does not contain the expected script path "
        "'/home/user/run_pipeline.sh'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
