#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
import random
import shutil
import subprocess
import tempfile
from collections import defaultdict
from datetime import datetime

C_PATH = "/home/user/aggregate.c"
PIPELINE_PATH = "/home/user/pipeline.sh"
LOG_PATH = "/home/user/loc_events.log"
OUTPUT_PATH = "/home/user/daily_velocity.csv"


def expected_lines(data):
    seen_hashes = set()
    aggregated = defaultdict(int)
    reader = csv.reader(data.splitlines())
    for row in reader:
        if not row:
            continue
        ts, h, lang, words = int(row[0]), row[1], row[2], int(row[3])
        if h not in seen_hashes:
            seen_hashes.add(h)
            date = datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")
            aggregated[(date, lang)] += words
    return [f"{date},{lang},{words}" for (date, lang), words in sorted(aggregated.items())]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_c_program_exists():
    path = C_PATH
    assert os.path.exists(path), f"C program {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_pipeline_script_exists_and_executable():
    path = PIPELINE_PATH
    assert os.path.exists(path), f"Bash script {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"Bash script {path} is not executable."


def test_c_program_compiles_and_handles_unseen_input():
    binary = os.path.join(tempfile.mkdtemp(prefix="aggregate-test-"), "aggregate")
    compiled = subprocess.run(
        ["gcc", "-O2", C_PATH, "-o", binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compiled.returncode == 0, f"aggregate.c did not compile with gcc -O2:\n{compiled.stderr}"

    rng = random.SystemRandom()
    hashes = [hashlib.md5(os.urandom(24)).hexdigest() for _ in range(180)]
    langs = ["es-ES", "fr-FR", "de-DE", "ja-JP", "pt-BR"]
    rows = []
    timestamp = 1696118300

    # Ensure every hash occurs, then add duplicates whose language, date, and
    # word count may differ from their first occurrence.
    choices = hashes[:] + [rng.choice(hashes) for _ in range(520)]
    for h in choices:
        timestamp += rng.randint(1, 9000)
        rows.append(f"{timestamp},{h},{rng.choice(langs)},{rng.randint(1, 50)}")
    data = "\n".join(rows) + "\n"

    env = os.environ.copy()
    env["TZ"] = "EST5EDT"
    result = subprocess.run(
        [binary],
        input=data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"Compiled aggregate program failed:\n{result.stderr}"
    actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert sorted(actual) == sorted(expected_lines(data)), \
        "The compiled C program did not correctly deduplicate and aggregate unseen input in UTC."


def test_pipeline_runs_on_input_and_regenerates_output():
    crafted = "\n".join([
        "1696118399,00000000000000000000000000000001,es-ES,7",
        "1696118400,00000000000000000000000000000002,fr-FR,11",
        "1696118460,00000000000000000000000000000001,ja-JP,99",
        "1696204799,00000000000000000000000000000003,es-ES,5",
        "1696204800,00000000000000000000000000000004,de-DE,13",
        "1696204900,00000000000000000000000000000002,fr-FR,88",
        "1696291200,00000000000000000000000000000005,fr-FR,3",
        "1696291300,00000000000000000000000000000006,es-ES,17",
    ]) + "\n"

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    env = os.environ.copy()
    env["TZ"] = "EST5EDT"
    try:
        with open(LOG_PATH, "w") as f:
            f.write(crafted)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [PIPELINE_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=30,
        )
        assert result.returncode == 0, f"pipeline.sh failed on test input:\n{result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), "pipeline.sh did not create daily_velocity.csv."
        assert read_nonempty_lines(OUTPUT_PATH) == expected_lines(crafted), \
            "pipeline.sh did not produce the required sorted output for unseen input."
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)

    # Run the executable script again against the real supplied log and require
    # it to regenerate, rather than relying on a pre-created output file.
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [PIPELINE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"pipeline.sh failed on loc_events.log:\n{result.stderr}"


def test_daily_velocity_output():
    log_path = LOG_PATH
    output_path = OUTPUT_PATH

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    seen_hashes = set()
    aggregated = defaultdict(int)

    with open(log_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            ts, h, lang, words = int(row[0]), row[1], row[2], int(row[3])
            if h not in seen_hashes:
                seen_hashes.add(h)
                dt = datetime.utcfromtimestamp(ts).strftime('%Y-%m-%d')
                aggregated[(dt, lang)] += words

    expected = sorted([(k[0], k[1], v) for k, v in aggregated.items()])
    expected_lines_for_log = [f"{date},{lang},{words}" for date, lang, words in expected]

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines_for_log, "The output in daily_velocity.csv does not match the expected aggregated data. Ensure duplicates are ignored (only the first occurrence counts) and it is sorted correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
