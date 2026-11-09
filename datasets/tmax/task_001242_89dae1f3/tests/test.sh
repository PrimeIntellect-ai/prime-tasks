#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
from collections import Counter

SCRIPT_PATH = "/home/user/prepare_data.sh"
RAW_PATH = "/home/user/raw_data.jsonl"
OUTPUT_PATH = "/home/user/training_data.jsonl"
EMBEDDER_PATH = "/opt/embedder.py"


def compute_embedding(text):
    length = len(text)
    vowels = sum(1 for c in text.lower() if c in 'aeiou')
    consonants = sum(1 for c in text.lower() if c in 'bcdfghjklmnpqrstvwxyz')
    return [length, vowels, consonants]


def get_expected_data():
    raw_data = [
        {"id": 10, "text": "Great product", "label": "POSITIVE"},
        {"id": 15, "text": "Terrible experience", "label": "NEGATIVE"},
        {"id": "2", "text": "String ID invalid", "label": "POSITIVE"},
        {"id": 8, "text": "Missing label"},
        {"id": 3, "text": "Okay", "label": "NEUTRAL"},
        {"id": 12, "text": "Loved it", "label": "POSITIVE"},
        {"id": 5, "text": "Not bad", "label": "POSITIVE"},
        {"id": 20, "text": "Worst thing ever", "label": "NEGATIVE"},
        {"id": 1, "text": "Awesome", "label": "POSITIVE"},
        {"id": 7, "text": "Hated it", "label": "NEGATIVE"},
        {"id": 25, "text": 12345, "label": "POSITIVE"}
    ]

    valid_records = []
    for record in raw_data:
        if "id" in record and isinstance(record["id"], (int, float)) and not isinstance(record["id"], bool):
            if "text" in record and isinstance(record["text"], str):
                if "label" in record and record["label"] in ["POSITIVE", "NEGATIVE"]:
                    valid_records.append(record)

    valid_records.sort(key=lambda x: x["id"])
    top_5 = valid_records[:5]

    expected = []
    for record in top_5:
        r = record.copy()
        r["embedding"] = compute_embedding(r["text"])
        expected.append(r)

    return expected


def test_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_is_bash():
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, "prepare_data.sh must be an executable Bash script."


def test_training_data_exists():
    output_path = OUTPUT_PATH
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."


def test_training_data_contents():
    output_path = OUTPUT_PATH
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 records in {output_path}, but found {len(lines)}."

    parsed_records = []
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
            parsed_records.append(record)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {output_path} is not valid JSON."

    expected_records = get_expected_data()

    for i in range(5):
        actual = parsed_records[i]
        expected = expected_records[i]

        assert actual.get("id") == expected["id"], f"Record {i+1}: expected id {expected['id']}, got {actual.get('id')}"
        assert actual.get("text") == expected["text"], f"Record {i+1}: expected text {expected['text']}, got {actual.get('text')}"
        assert actual.get("label") == expected["label"], f"Record {i+1}: expected label {expected['label']}, got {actual.get('label')}"
        assert actual.get("embedding") == expected["embedding"], f"Record {i+1}: expected embedding {expected['embedding']}, got {actual.get('embedding')}"


def _snapshot(path):
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(os.stat(path).st_mode)


def _restore(path, snapshot):
    data, mode = snapshot
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def test_script_processes_changed_input_and_uses_embedder():
    nonce = secrets.token_hex(12)
    call_log = f"/tmp/embedder_calls_{nonce}.jsonl"
    records = [
        {"id": 42, "text": f"late item {nonce}", "label": "POSITIVE"},
        {"id": "-100", "text": f"invalid string id {nonce}", "label": "NEGATIVE"},
        {"id": 9, "text": f"ninth item {nonce}", "label": "NEGATIVE"},
        {"id": -3, "text": f"first item {nonce}", "label": "POSITIVE"},
        {"id": 11, "text": 123, "label": "POSITIVE"},
        {"id": 2, "text": f"third item {nonce}", "label": "NEGATIVE"},
        {"id": True, "text": f"boolean id {nonce}", "label": "POSITIVE"},
        {"id": 0, "text": f"second item {nonce}", "label": "NEGATIVE"},
        {"id": 7.5, "text": f"fourth item {nonce}", "label": "POSITIVE"},
        {"id": 1, "text": f"invalid label {nonce}", "label": "positive"},
        {"id": 100, "text": f"last item {nonce}", "label": "NEGATIVE"},
        {"text": f"missing id {nonce}", "label": "POSITIVE"},
    ]

    def dynamic_embedding(text):
        digest = hashlib.sha256((nonce + "\0" + text).encode("utf-8")).digest()
        return [len(text), int.from_bytes(digest[:4], "big"), sum(digest) % 997]

    valid = [
        record for record in records
        if isinstance(record.get("id"), (int, float))
        and not isinstance(record.get("id"), bool)
        and isinstance(record.get("text"), str)
        and record.get("label") in ("POSITIVE", "NEGATIVE")
    ]
    selected = sorted(valid, key=lambda record: record["id"])[:5]
    expected = [dict(record, embedding=dynamic_embedding(record["text"])) for record in selected]

    raw_snapshot = _snapshot(RAW_PATH)
    output_snapshot = _snapshot(OUTPUT_PATH)
    embedder_snapshot = _snapshot(EMBEDDER_PATH)

    embedder_source = f'''#!/usr/bin/env python3
import hashlib
import json
import sys
NONCE = {nonce!r}
LOG_PATH = {call_log!r}
text = sys.argv[1] if len(sys.argv) > 1 else ""
with open(LOG_PATH, "a", encoding="utf-8") as log:
    log.write(json.dumps(text) + "\\n")
digest = hashlib.sha256((NONCE + "\\0" + text).encode("utf-8")).digest()
print(json.dumps([len(text), int.from_bytes(digest[:4], "big"), sum(digest) % 997]))
'''

    try:
        with open(RAW_PATH, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        with open(EMBEDDER_PATH, "w", encoding="utf-8") as f:
            f.write(embedder_source)
        os.chmod(EMBEDDER_PATH, 0o755)
        os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"prepare_data.sh failed on changed input:\nstdout={result.stdout}\nstderr={result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), "prepare_data.sh did not recreate training_data.jsonl."

        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 5, f"Changed input should produce exactly 5 records, found {len(lines)}."
        actual = [json.loads(line) for line in lines]
        assert actual == expected, f"Output for changed input was incorrect. Expected {expected}, got {actual}."

        assert os.path.isfile(call_log), "The provided embedder was not invoked."
        with open(call_log, "r", encoding="utf-8") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        call_counts = Counter(calls)
        for record in selected:
            assert call_counts[record["text"]] >= 1, f"Embedder was not called for selected text {record['text']!r}."
    finally:
        _restore(RAW_PATH, raw_snapshot)
        _restore(OUTPUT_PATH, output_snapshot)
        _restore(EMBEDDER_PATH, embedder_snapshot)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
