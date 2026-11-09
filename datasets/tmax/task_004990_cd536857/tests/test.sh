#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import subprocess
import tempfile
import time
import urllib.request
from urllib.parse import urlparse

import pytest
from dotenv import dotenv_values
from redis import Redis

FILTER = "/home/user/filter.sh"
RNG = secrets.SystemRandom()


def make_sequence(length, gc_fraction):
    gc_count = round(length * gc_fraction)
    at_count = length - gc_count
    bases = (["G"] * (gc_count // 2) +
             ["C"] * (gc_count - gc_count // 2) +
             ["A"] * (at_count // 2) +
             ["T"] * (at_count - at_count // 2))
    RNG.shuffle(bases)
    return "".join(bases)


def make_holdouts(count=12):
    cases = []
    for _ in range(count // 2):
        length = RNG.randint(31, 79)
        cases.append((make_sequence(length, RNG.uniform(0.32, 0.50)), 0))
    for _ in range(count // 2):
        length = RNG.randint(31, 79)
        cases.append((make_sequence(length, RNG.uniform(0.72, 0.86)), 1))
    RNG.shuffle(cases)
    return cases


DIRECT_HOLDOUTS = make_holdouts()
PIPELINE_HOLDOUTS = make_holdouts(8)


def write_random_fasta(sequence):
    fd, path = tempfile.mkstemp(prefix="seq_" + secrets.token_hex(8) + "_", suffix=".fa")
    with os.fdopen(fd, "w") as f:
        f.write(">" + secrets.token_hex(16) + "\n")
        f.write(sequence + "\n")
    return path


def test_filter_script_exists():
    path = "/home/user/filter.sh"
    assert os.path.isfile(path), f"Expected {path} to exist."
    assert os.access(path, os.X_OK), f"Expected {path} to be executable."


def test_adversarial_corpus_evil():
    path = "/home/user/filter.sh"
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.fasta"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    bypassed = []
    for f in evil_files:
        result = subprocess.run([path, f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 1:
            bypassed.append(os.path.basename(f))

    assert len(bypassed) == 0, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed[:5])}"


def test_adversarial_corpus_clean():
    path = "/home/user/filter.sh"
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.fasta"))
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."

    modified = []
    for f in clean_files:
        result = subprocess.run([path, f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            modified.append(os.path.basename(f))

    assert len(modified) == 0, f"{len(modified)} of {len(clean_files)} clean modified (rejected): {', '.join(modified[:5])}"


def test_randomized_hidden_holdout_directly():
    failures = []
    for sequence, expected_code in DIRECT_HOLDOUTS:
        path = write_random_fasta(sequence)
        try:
            result = subprocess.run(
                [FILTER, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=3
            )
            if result.returncode != expected_code:
                failures.append((len(sequence), expected_code, result.returncode))
        finally:
            os.unlink(path)
    assert not failures, f"Randomized hold-out misclassifications: {failures[:5]}"


def test_configuration_files_are_corrected():
    with open("/app/nginx.conf", "r") as f:
        nginx_conf = re.sub(r"#.*", "", f.read())
    assert re.search(r"\bproxy_pass\s+[^;]+;", nginx_conf), "nginx /submit route has no proxy_pass"
    assert "5000" in nginx_conf, "nginx configuration does not route to the API on port 5000"
    syntax = subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx.conf"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert syntax.returncode == 0, syntax.stdout

    env = dotenv_values("/app/worker.env")
    redis_url = env.get("REDIS_URL")
    assert redis_url, "REDIS_URL is missing from /app/worker.env"
    parsed = urlparse(redis_url)
    assert parsed.scheme in ("redis", "rediss")
    assert parsed.hostname in ("127.0.0.1", "localhost")
    assert parsed.port == 6379, f"worker REDIS_URL uses incorrect port: {parsed.port}"


def wait_for_result(results_file, previous_count, expected, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(results_file):
            with open(results_file, "r") as f:
                lines = [line.strip() for line in f if line.strip()]
            if len(lines) > previous_count:
                new_lines = lines[previous_count:]
                assert new_lines[0] == expected, f"Expected worker result {expected}, got {new_lines[0]}"
                return len(lines)
        time.sleep(0.1)
    pytest.fail(f"Worker did not append {expected} to {results_file}")


def submit(payload):
    url = "http://localhost:8080/submit"
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "text/plain")
    try:
        response = urllib.request.urlopen(req, timeout=5)
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        response.read()
    except Exception as e:
        pytest.fail(f"Failed to submit request to {url}: {e}")


def test_end_to_end_pipeline():
    redis_conn = Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    assert redis_conn.ping(), "Redis is not running on port 6379"

    # Remove stale queued work and stale log output so only responses caused by
    # requests below can satisfy the assertions.
    redis_conn.delete("rq:queue:default")
    time.sleep(0.5)
    results_file = "/app/results.log"
    with open(results_file, "w"):
        pass
    line_count = 0

    # Preserve the original clean end-to-end case, but require a newly appended
    # classification rather than accepting arbitrary preexisting content.
    submit(b">test_seq\nATGCATGC")
    line_count = wait_for_result(results_file, line_count, "ACCEPTED")

    # Exercise randomized, neutrally named hold-outs through nginx, the API,
    # Redis, the worker, and the submitted filter.
    for sequence, expected_code in PIPELINE_HOLDOUTS:
        header = secrets.token_hex(16)
        payload = f">{header}\n{sequence}\n".encode("ascii")
        expected = "ACCEPTED" if expected_code == 0 else "REJECTED"
        submit(payload)
        line_count = wait_for_result(results_file, line_count, expected)

    with open(results_file, "r") as f:
        final_lines = [line.strip() for line in f if line.strip()]
    assert len(final_lines) >= 1 + len(PIPELINE_HOLDOUTS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
