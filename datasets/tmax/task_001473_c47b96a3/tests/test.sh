#!/bin/bash
mkdir -p /logs/verifier

if ! redis-cli ping >/dev/null 2>&1; then
    redis-server --daemonize yes >/dev/null 2>&1
fi

if ! python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8080),1); s.close()' >/dev/null 2>&1; then
    nginx >/dev/null 2>&1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile
import uuid

import requests

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
SCRIPT_PATH = "/home/user/pipeline.py"
CONFIG_PATH = "/var/www/html/config.json"


def redis_cmd(*args):
    result = subprocess.run(
        ["redis-cli", "--raw", *map(str, args)],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.rstrip("\n")


def redis_list(key):
    value = redis_cmd("LRANGE", key, "0", "-1")
    return [] if not value else value.splitlines()


def install_config(forbidden_tags):
    with open(CONFIG_PATH, "w", encoding="utf-8") as config_file:
        json.dump({"forbidden_tags": forbidden_tags}, config_file)
    response = requests.get("http://localhost:8080/config.json", timeout=5)
    response.raise_for_status()
    assert response.json() == {"forbidden_tags": forbidden_tags}


def run_pipeline(input_path):
    output_path = tempfile.mktemp(suffix=".jsonl")
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "--input", input_path, "--output", output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Pipeline failed for {input_path}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), "Pipeline did not create the requested output file"
    with open(output_path, "r", encoding="utf-8") as output_file:
        lines = output_file.readlines()
    os.remove(output_path)
    records = []
    for line in lines:
        assert line.strip(), "Output contains a blank JSONL line"
        value = json.loads(line)
        assert isinstance(value, dict), "Every output line must be a JSON object"
        records.append(value)
    return records


def test_pipeline_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus_normalization_deduplication_and_report():
    redis_cmd("FLUSHDB")
    token = "blockedtag-" + uuid.uuid4().hex
    install_config(["<script>", "<iframe>", token])

    records = [
        {
            "record_id": "clean-" + uuid.uuid4().hex,
            "title": "  First title  ",
            "description": "Ordinary description",
            "extra": 1,
        },
        {
            "record_id": "clean-" + uuid.uuid4().hex,
            "title": "\tSecond title\n",
            "description": "Valid UTF-8: café and 雪",
            "extra": {"keep": True},
        },
        {
            "record_id": "clean-" + uuid.uuid4().hex,
            "title": "Already normalized",
            "description": "Harmless text",
            "extra": None,
        },
    ]

    filename = "clean_" + uuid.uuid4().hex + ".jsonl"
    input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
    with open(input_path, "w", encoding="utf-8") as input_file:
        for record in records:
            input_file.write(json.dumps(record, ensure_ascii=False) + "\n")

    sentinel = "before-clean-" + uuid.uuid4().hex
    redis_cmd("RPUSH", "processing_reports", sentinel)
    output = run_pipeline(input_path)

    expected = []
    for record in records:
        normalized = dict(record)
        normalized["title"] = normalized["title"].strip()
        expected.append(normalized)
    assert output == expected
    for record in output:
        assert record.get("title") == record.get("title", "").strip()

    assert int(redis_cmd("SCARD", "seen_ids")) == len(records)
    for record in records:
        assert redis_cmd("SISMEMBER", "seen_ids", record["record_id"]) == "1"

    report = f"Report for {filename}: {len(records)} accepted, 0 dropped."
    assert redis_list("processing_reports") == [sentinel, report]

    # Running the same records again must drop all of them using Redis state.
    redis_cmd("DEL", "processing_reports")
    second_sentinel = "before-repeat-" + uuid.uuid4().hex
    redis_cmd("RPUSH", "processing_reports", second_sentinel)
    repeated_output = run_pipeline(input_path)
    assert repeated_output == []
    repeated_report = f"Report for {filename}: 0 accepted, {len(records)} dropped."
    assert redis_list("processing_reports") == [second_sentinel, repeated_report]
    assert int(redis_cmd("SCARD", "seen_ids")) == len(records)
    os.remove(input_path)


def test_adversarial_corpus_is_dropped_and_reported():
    redis_cmd("FLUSHDB")
    token = "dynamicforbidden-" + uuid.uuid4().hex
    install_config(["<script>", "<iframe>", "<object>", token])

    duplicate_id = "existing-" + uuid.uuid4().hex
    redis_cmd("SADD", "seen_ids", duplicate_id)

    records = [
        {
            "record_id": "evil-" + uuid.uuid4().hex,
            "title": " Forbidden dynamic tag ",
            "description": "prefix " + token.swapcase() + " suffix",
        },
        {
            "record_id": "evil-" + uuid.uuid4().hex,
            "title": " Forbidden configured tag ",
            "description": "contains <IFRAME> in mixed case",
        },
        {
            "record_id": "evil-" + uuid.uuid4().hex,
            "title": " Replacement character ",
            "description": "bad replacement: \ufffd",
        },
        {
            "record_id": duplicate_id,
            "title": " Duplicate ",
            "description": "Otherwise valid",
        },
    ]
    invalid_id = "invalid-" + uuid.uuid4().hex

    filename = "evil_" + uuid.uuid4().hex + ".jsonl"
    input_path = os.path.join(EVIL_CORPUS_DIR, filename)
    with open(input_path, "wb") as input_file:
        for record in records:
            input_file.write((json.dumps(record, ensure_ascii=False) + "\n").encode("utf-8"))
        input_file.write(
            b'{"record_id":"'
            + invalid_id.encode("ascii")
            + b'","title":" Invalid bytes ","description":"broken '
            + b'\xff'
            + b' text"}\n'
        )

    input_count = len(records) + 1
    sentinel = "before-evil-" + uuid.uuid4().hex
    redis_cmd("RPUSH", "processing_reports", sentinel)
    output = run_pipeline(input_path)
    assert output == [], f"Expected all adversarial records to be dropped, got {output!r}"

    # Dropped records must not be added to seen_ids; only the preexisting ID remains.
    assert int(redis_cmd("SCARD", "seen_ids")) == 1
    assert redis_cmd("SISMEMBER", "seen_ids", duplicate_id) == "1"

    report = f"Report for {filename}: 0 accepted, {input_count} dropped."
    assert redis_list("processing_reports") == [sentinel, report]
    os.remove(input_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
