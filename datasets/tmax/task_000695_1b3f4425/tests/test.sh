#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import subprocess
import tempfile
import time
import urllib.request
from urllib.parse import urlparse

import pytest
import redis

PRIMER = "GATCGGAAGAGCACACGTCTG"


def parse_env(path):
    env = os.environ.copy()
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                if line.startswith("export "):
                    line = line[7:]
                if "=" in line:
                    key, val = line.split("=", 1)
                    env[key.strip()] = val.strip().strip("\"'")
    return env


def read_fasta(path):
    sequences = []
    current = None
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current is not None:
                    sequences.append("".join(current).upper())
                current = []
            elif current is not None:
                current.append(line)
    if current is not None:
        sequences.append("".join(current).upper())
    return sequences


def contains_primer(sequence):
    width = len(PRIMER)
    for start in range(0, len(sequence) - width + 1):
        window = sequence[start:start + width]
        if sum(a != b for a, b in zip(window, PRIMER)) <= 1:
            return True
    return False


def expected_status(path):
    sequences = read_fasta(path)
    assert sequences, f"Test FASTA unexpectedly contained no records: {path}"
    matches = sum(contains_primer(seq) for seq in sequences)
    return 1 if matches * 20 >= len(sequences) else 0


def run_filter(script_path, fasta_path):
    try:
        result = subprocess.run(
            ["python3", script_path, fasta_path],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {fasta_path}")
    return result.returncode


def mutate_primer(mismatches, rng):
    chars = list(PRIMER)
    for position in rng.sample(range(len(chars)), mismatches):
        chars[position] = next(base for base in "ACGT" if base != chars[position])
    return "".join(chars)


def write_generated_fasta(path, count, matching_count, matching_mismatches, rng):
    records = []
    for i in range(count):
        sequence = "A" * 80
        if i < matching_count:
            insert = mutate_primer(matching_mismatches, rng)
            sequence = sequence[:23] + insert + sequence[23 + len(PRIMER):]
        elif i < matching_count + min(4, count - matching_count):
            # Two mismatches are deliberately non-matching decoys.
            insert = mutate_primer(2, rng)
            sequence = sequence[:23] + insert + sequence[23 + len(PRIMER):]
        records.append((secrets.token_hex(6), sequence))
    rng.shuffle(records)
    with open(path, "w") as f:
        for index, (name, sequence) in enumerate(records):
            f.write(f">{name}\n")
            # Exercise normal multi-line FASTA parsing as well.
            split = 31 if index % 2 else len(sequence)
            f.write(sequence[:split] + "\n")
            if split < len(sequence):
                f.write(sequence[split:] + "\n")


def test_service_configuration():
    env_file = "/home/user/services.env"
    assert os.path.exists(env_file), f"Environment file {env_file} is missing."
    assert os.path.isfile(env_file), f"Environment path {env_file} is not a regular file."

    env = parse_env(env_file)
    assert "REDIS_HOST" in env, "REDIS_HOST not defined in services.env"
    assert "REDIS_PORT" in env, "REDIS_PORT not defined in services.env"
    assert "MESH_API_URL" in env, "MESH_API_URL not defined in services.env"

    mesh_url = env["MESH_API_URL"]
    parsed = urlparse(mesh_url)
    assert parsed.scheme == "http", "MESH_API_URL must be an HTTP URL"
    assert parsed.hostname in ("127.0.0.1", "localhost"), "MESH_API_URL must address the local Mesh API"
    assert parsed.port == 8080, "MESH_API_URL must use Mesh API port 8080"
    assert parsed.path in ("", "/"), "MESH_API_URL must address the Mesh API root endpoint"

    # Remove stale success indicators so this invocation must produce them.
    try:
        old_redis = redis.Redis(
            host=env.get("REDIS_HOST", "127.0.0.1"),
            port=int(env.get("REDIS_PORT", 6379)),
            socket_connect_timeout=1,
        )
        old_redis.delete("pipeline_status")
        old_redis.close()
    except (redis.exceptions.RedisError, ValueError):
        pass
    try:
        os.remove("/home/user/worker.log")
    except FileNotFoundError:
        pass

    subprocess.run(["/bin/bash", "/app/start_services.sh"], env=env, check=True)
    time.sleep(5)

    try:
        r = redis.Redis(
            host=env.get("REDIS_HOST", "127.0.0.1"),
            port=int(env.get("REDIS_PORT", 6379)),
        )
        status = r.get("pipeline_status")
        assert status is not None, "Redis key 'pipeline_status' not found. Pipeline may have failed."
        assert status.decode("utf-8") == "COMPLETED", f"Expected pipeline_status to be 'COMPLETED', got {status.decode('utf-8')}"
    except redis.exceptions.ConnectionError:
        pytest.fail("Failed to connect to Redis. Ensure REDIS_HOST and REDIS_PORT are correct and Redis is running.")
    finally:
        if "r" in locals():
            r.close()

    assert os.path.isfile("/home/user/worker.log"), "Stats worker did not create worker.log"
    with open("/home/user/worker.log", "r") as f:
        assert "PIPELINE_SUCCESS" in f.read(), "Stats worker did not report PIPELINE_SUCCESS"

    try:
        with urllib.request.urlopen(mesh_url, timeout=5) as response:
            body = response.read().decode("utf-8")
            assert response.status == 200, f"Mesh API returned HTTP {response.status}"
            assert body == "OK", f"Unexpected Mesh API response: {body!r}"
    except Exception as exc:
        pytest.fail(f"Configured MESH_API_URL is not usable: {exc}")


def test_adversarial_filter():
    script_path = "/home/user/filter_sequences.py"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."

    clean_dir = "/app/test_data/clean/"
    evil_dir = "/app/test_data/evil/"
    clean_files = glob.glob(os.path.join(clean_dir, "*.fasta"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.fasta"))
    assert clean_files, f"No clean files found in {clean_dir}."
    assert evil_files, f"No evil files found in {evil_dir}."

    # Exercise the shipped corpus, but derive each answer from its actual content
    # rather than trusting a directory label produced by probabilistic generation.
    corpus_failures = []
    for fasta_path in clean_files + evil_files:
        expected = expected_status(fasta_path)
        actual = run_filter(script_path, fasta_path)
        if actual != expected:
            corpus_failures.append(
                f"{os.path.basename(fasta_path)} expected {expected}, got {actual}"
            )
    assert not corpus_failures, " | ".join(corpus_failures)

    # Neutral, randomized paths and exact boundary cases prevent pathname-only
    # classification and explicitly test exact and one-mismatch primer matches.
    rng = random.SystemRandom()
    cases = [
        (20, 1, 0),   # exactly 5%, exact primer: contaminated
        (21, 1, 1),   # below 5%, one mismatch: clean
        (40, 2, 1),   # exactly 5%, one mismatch: contaminated
        (40, 1, 0),   # below 5% with the same record count: clean
        (37, 2, 1),   # above 5%, one mismatch: contaminated
        (60, 2, 0),   # below 5%: clean
        (23, 0, 0),   # no matching primers: clean
    ]
    rng.shuffle(cases)

    generated_failures = []
    observed = set()
    with tempfile.TemporaryDirectory(prefix="sequence_checks_") as temp_dir:
        for count, matching_count, mismatches in cases:
            fasta_path = os.path.join(temp_dir, secrets.token_hex(12) + ".fa")
            write_generated_fasta(
                fasta_path, count, matching_count, mismatches, rng
            )
            expected = expected_status(fasta_path)
            observed.add(expected)
            actual = run_filter(script_path, fasta_path)
            if actual != expected:
                generated_failures.append(
                    f"generated case with {count} records expected {expected}, got {actual}"
                )

    assert observed == {0, 1}, "Generated tests did not include both classifications"
    assert not generated_failures, " | ".join(generated_failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
