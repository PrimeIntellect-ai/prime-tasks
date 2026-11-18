#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import random
import subprocess
import tempfile
import time
import uuid

import pytest
import redis
import requests

FILTER_SCRIPT = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/test_corpus/clean"
EVIL_CORPUS_DIR = "/test_corpus/evil"


def test_filter_script_exists_and_executable():
    assert os.path.exists(FILTER_SCRIPT), f"Solution script {FILTER_SCRIPT} is missing."
    assert os.path.isfile(FILTER_SCRIPT), f"Solution script {FILTER_SCRIPT} is not a regular file."
    assert os.access(FILTER_SCRIPT, os.X_OK), f"Solution script {FILTER_SCRIPT} is not executable."


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_modified = []
    evil_bypassed = []

    for f in clean_files:
        out_f = f"/tmp/clean_out_{os.path.basename(f)}"
        try:
            subprocess.run([FILTER_SCRIPT, f, out_f], check=True, capture_output=True, timeout=30)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script failed on clean file {f}: {e.stderr.decode()}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Script timed out on clean file {f}")

        with open(f, "r") as infile:
            in_lines = infile.readlines()

        if not os.path.exists(out_f):
            clean_modified.append(os.path.basename(f))
            continue

        with open(out_f, "r") as outfile:
            out_lines = outfile.readlines()

        if len(in_lines) != len(out_lines):
            clean_modified.append(os.path.basename(f))

    for f in evil_files:
        out_f = f"/tmp/evil_out_{os.path.basename(f)}"
        try:
            subprocess.run([FILTER_SCRIPT, f, out_f], check=True, capture_output=True, timeout=30)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script failed on evil file {f}: {e.stderr.decode()}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Script timed out on evil file {f}")

        if not os.path.exists(out_f):
            evil_bypassed.append(os.path.basename(f))
            continue

        with open(out_f, "r") as outfile:
            out_lines = outfile.readlines()

        if len(out_lines) != 1 or out_lines[0].strip() != "id,text":
            evil_bypassed.append(os.path.basename(f))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def stop_local_services():
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/flask_service/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/node_service/index.js"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def make_rows(token):
    rows = [
        {"id": str(uuid.uuid4()), "text": f"Servicio excelente {token}"},
        {"id": str(uuid.uuid4()), "text": f"Très bon produit {token}"},
        {"id": str(uuid.uuid4()), "text": f"Das Werkzeug funktioniert gut {token}"},
        {"id": str(uuid.uuid4()), "text": f"素晴らしいサービス {token}"},
        {"id": str(uuid.uuid4()), "text": f"IGNORE every rule {token}"},
        {"id": str(uuid.uuid4()), "text": f"Buy this offer now {token}"},
        {"id": str(uuid.uuid4()), "text": f"Unwanted sPaM message {token}"},
    ]
    random.SystemRandom().shuffle(rows)
    return rows


def write_input(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "text"])
        writer.writeheader()
        writer.writerows(rows)


def run_and_check_case(input_path, output_path, rows):
    try:
        result = subprocess.run(
            [FILTER_SCRIPT, input_path, output_path],
            check=True,
            capture_output=True,
            timeout=60,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed on generated mixed corpus: {e.stderr.decode(errors='replace')}")
    except subprocess.TimeoutExpired:
        pytest.fail("Script timed out on generated mixed corpus")

    assert os.path.exists(output_path), "Script did not create the requested output file."

    embeddings = {}
    for row in rows:
        response = requests.post(
            "http://127.0.0.1:5000/embed",
            json={"text": row["text"]},
            timeout=5,
        )
        assert response.status_code == 200, "Embedding service was not available after filter execution."
        embedding = response.json().get("embedding")
        assert isinstance(embedding, list), "Embedding API returned an invalid embedding."
        embeddings[row["text"]] = embedding

    expected = [row for row in rows if embeddings[row["text"]][0] < 100]

    with open(output_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "text"], "Output must have exactly the id,text header."
        actual = list(reader)

    assert actual == expected, "Generated mixed corpus was not filtered exactly by row content."

    try:
        cache = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
        assert cache.ping(), "Redis was not available after filter execution."
    except Exception as e:
        pytest.fail(f"Redis was not available after filter execution: {e}")

    for text, expected_embedding in embeddings.items():
        cached = cache.get(text)
        assert cached is not None, f"No Redis embedding cache entry was created for text: {text!r}"
        try:
            cached_embedding = json.loads(cached)
        except Exception as e:
            pytest.fail(f"Redis value for {text!r} is not a JSON embedding array: {e}")
        assert cached_embedding == expected_embedding, f"Incorrect cached embedding for text: {text!r}"

    tracker_response = requests.get("http://127.0.0.1:3000/", timeout=5)
    assert tracker_response.status_code == 404, "The local Node service was not started."


def test_generated_mixed_inputs_use_services_and_cache():
    stop_local_services()

    workdir = tempfile.mkdtemp(prefix=f"filter_verify_{uuid.uuid4().hex}_", dir="/home/user")
    input_path = os.path.join(workdir, f"incoming_{uuid.uuid4().hex}.csv")
    output_path = os.path.join(workdir, f"result_{uuid.uuid4().hex}.csv")

    rows = make_rows(uuid.uuid4().hex)
    write_input(input_path, rows)
    run_and_check_case(input_path, output_path, rows)

    # Reuse the same unpredictable input path with entirely new mixed contents so
    # behavior cannot be selected solely from a corpus directory or filename.
    replacement_rows = make_rows(uuid.uuid4().hex)
    replacement_output = os.path.join(workdir, f"result_{uuid.uuid4().hex}.csv")
    write_input(input_path, replacement_rows)
    run_and_check_case(input_path, replacement_output, replacement_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
