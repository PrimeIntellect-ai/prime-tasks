#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import socket
import string
import subprocess
import tempfile
import uuid

import pytest
import redis
from dotenv import dotenv_values


def test_services_running():
    # Preserve the original service reachability assertions.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(('127.0.0.1', 6379))
        assert result == 0, "Redis is not running or not reachable on 127.0.0.1:6379"

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(('127.0.0.1', 5000))
        assert result == 0, "Flask API is not running or not reachable on 127.0.0.1:5000"


def test_service_configuration():
    env_path = "/app/services/flask/.env"
    assert os.path.isfile(env_path), f"Missing {env_path}"
    values = dotenv_values(env_path)
    assert values.get("REDIS_HOST") == "127.0.0.1", "REDIS_HOST is not configured as required"
    assert values.get("REDIS_PORT") == "6379", "REDIS_PORT is not configured as required"


def test_raw_data_downloaded():
    # Preserve the original assertion that the pipeline was run by the agent.
    raw_data_dir = "/home/user/raw_data"
    assert os.path.isdir(raw_data_dir), f"Directory {raw_data_dir} does not exist"
    txt_files = glob.glob(os.path.join(raw_data_dir, "*.txt"))
    assert len(txt_files) > 0, f"No .txt files found in {raw_data_dir}. ETL script may not have run or saved files correctly."


def test_etl_script_executes_and_saves_twenty_api_responses():
    etl_script = "/home/user/etl.sh"
    assert os.path.isfile(etl_script), f"ETL script {etl_script} does not exist"
    assert os.access(etl_script, os.X_OK), f"ETL script {etl_script} is not executable"

    raw_data_dir = "/home/user/raw_data"
    if os.path.isdir(raw_data_dir):
        for entry in os.scandir(raw_data_dir):
            if entry.is_file() or entry.is_symlink():
                os.unlink(entry.path)
            elif entry.is_dir():
                import shutil
                shutil.rmtree(entry.path)
    else:
        os.makedirs(raw_data_dir, exist_ok=True)

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=False)
    client.ping()
    client.flushdb()

    result = subprocess.run(
        [etl_script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
        env={**os.environ, "LC_ALL": "C.UTF-8"},
    )
    assert result.returncode == 0, (
        f"ETL script exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )

    files = glob.glob(os.path.join(raw_data_dir, "*.txt"))
    assert len(files) == 20, f"ETL must save exactly 20 API responses; found {len(files)} text files"

    keys = client.keys("*")
    assert len(keys) == 20, f"Expected exactly 20 API-generated Redis records; found {len(keys)}"

    seen_ids = set()
    for path in files:
        stem = os.path.basename(path)[:-4]
        try:
            parsed = uuid.UUID(stem)
        except ValueError as exc:
            raise AssertionError(f"Output filename is not an API UUID: {os.path.basename(path)}") from exc
        assert str(parsed) == stem.lower(), f"Output filename is not a canonical UUID: {stem}"
        assert stem not in seen_ids, f"Duplicate response ID {stem}"
        seen_ids.add(stem)

        redis_value = client.get(stem)
        assert redis_value is not None, f"No matching API/Redis response exists for output {stem}.txt"
        with open(path, "rb") as handle:
            saved = handle.read()
        assert saved in (redis_value, redis_value + b"\n"), (
            f"Saved content for {stem}.txt does not match the text returned by the API"
        )

    redis_ids = {key.decode("utf-8") for key in keys}
    assert seen_ids == redis_ids, "Saved files do not correspond exactly to the 20 API responses"


def test_adversarial_filter_corpus():
    # Preserve the original fixed-corpus assertions.
    filter_script = "/home/user/filter.sh"
    assert os.path.isfile(filter_script), f"Filter script {filter_script} does not exist"
    assert os.access(filter_script, os.X_OK), f"Filter script {filter_script} is not executable"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_modified = []
    evil_bypassed = []
    for c_file in clean_files:
        result = subprocess.run(["bash", filter_script, c_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(c_file))

    for e_file in evil_files:
        result = subprocess.run(["bash", filter_script, e_file], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(e_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not error_messages, " | ".join(error_messages)


def test_adversarial_filter_randomized_inputs():
    filter_script = "/home/user/filter.sh"
    rng = random.SystemRandom()
    cases = []

    # Random boundary and above-boundary cases using unambiguous ASCII members
    # of the POSIX alnum and punct classes.
    for _ in range(40):
        alnum_count = rng.randint(1, 160)
        clean_punct = alnum_count // 2
        evil_punct = clean_punct + 1

        clean_chars = [rng.choice(string.ascii_letters + string.digits) for _ in range(alnum_count)]
        clean_chars += [rng.choice(string.punctuation) for _ in range(clean_punct)]
        clean_chars += [rng.choice(" \t\n") for _ in range(rng.randint(0, 20))]
        rng.shuffle(clean_chars)
        cases.append(("".join(clean_chars), 0))

        evil_chars = [rng.choice(string.ascii_letters + string.digits) for _ in range(alnum_count)]
        evil_chars += [rng.choice(string.punctuation) for _ in range(evil_punct)]
        evil_chars += [rng.choice(" \t\n") for _ in range(rng.randint(0, 20))]
        rng.shuffle(evil_chars)
        cases.append(("".join(evil_chars), 1))

    cases.extend([
        (" \t\n", 0),
        ("abcXYZ012345", 0),
        ("!@#$%^&*()", 1),
    ])

    for hidden in ("\u200b", "\u200c", "\u200d", "\ufeff"):
        surrounding = "".join(rng.choice(string.ascii_letters + string.digits + " ") for _ in range(80))
        position = rng.randrange(len(surrounding) + 1)
        cases.append((surrounding[:position] + hidden + surrounding[position:], 1))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="filter-check-") as directory:
        for text, expected in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
            try:
                result = subprocess.run(
                    [filter_script, path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                    env={**os.environ, "LC_ALL": "C.UTF-8"},
                )
            except subprocess.TimeoutExpired:
                failures.append("filter timed out")
                continue
            if result.returncode != expected:
                failures.append(
                    f"expected exit {expected}, got {result.returncode} "
                    f"for alnum={sum(c.isascii() and c.isalnum() for c in text)}, "
                    f"punct={sum(c in string.punctuation for c in text)}"
                )

    assert not failures, f"Randomized filter failures ({len(failures)}): " + " | ".join(failures[:8])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
