#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

CLEANER_SCRIPT = "/home/user/cleaner.py"
CLEAN_CORPUS_DIR = Path("/home/user/corpora/clean")
EVIL_CORPUS_DIR = Path("/home/user/corpora/evil")


def normalize_msg(msg: str) -> str:
    msg = msg.lower()
    return re.sub(r'[^a-z0-9\s]', '', msg)


def is_valid_line(line: str) -> bool:
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        return False

    if not isinstance(data, dict):
        return False

    for key in ['ts', 'sensor_id', 'msg']:
        if key not in data or not isinstance(data[key], str):
            return False

    for value in data.values():
        if isinstance(value, str):
            if any(0xD800 <= ord(c) <= 0xDFFF for c in value):
                return False

    return True


def get_expected_output(filepath: Path) -> list:
    valid_records = []
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if is_valid_line(line):
                data = json.loads(line)
                data['msg'] = normalize_msg(data['msg'])
                valid_records.append(data)

    valid_records.sort(key=lambda x: x['ts'])
    return valid_records


def run_cleaner(filepath: Path) -> list:
    result = subprocess.run(
        ["python3", CLEANER_SCRIPT, str(filepath)],
        capture_output=True,
        text=True,
        check=False,
        timeout=10
    )
    if result.returncode != 0:
        raise RuntimeError(f"Script failed on {filepath.name}:\n{result.stderr}")

    records = []
    for line in result.stdout.splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def test_cleaner_script_exists():
    assert os.path.isfile(CLEANER_SCRIPT), f"Cleaner script not found at {CLEANER_SCRIPT}"
    assert os.access(CLEANER_SCRIPT, os.X_OK), "Cleaner script is not executable"


def test_clean_corpus():
    clean_files = list(CLEAN_CORPUS_DIR.glob("*.jsonl"))
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for filepath in clean_files:
        try:
            expected = get_expected_output(filepath)
            actual = run_cleaner(filepath)
            if expected != actual:
                failed_files.append(filepath.name)
        except Exception as e:
            failed_files.append(f"{filepath.name} (Error: {e})")

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified incorrectly or failed: {failed_files}"


def test_evil_corpus():
    evil_files = list(EVIL_CORPUS_DIR.glob("*.jsonl"))
    assert evil_files, "No evil corpus files found."

    failed_files = []
    for filepath in evil_files:
        try:
            expected = get_expected_output(filepath)
            actual = run_cleaner(filepath)
            if expected != actual:
                failed_files.append(filepath.name)
        except Exception as e:
            failed_files.append(f"{filepath.name} (Error: {e})")

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed or failed: {failed_files}"


def test_generated_unpredictable_corpora():
    for trial in range(3):
        token = secrets.token_hex(8)
        valid = [
            {
                "ts": f"204{trial}-07-19T12:00:30Z",
                "sensor_id": f"sensor-{token}-c",
                "msg": f"ALPHA, {token}! Value #42."
            },
            {
                "ts": f"204{trial}-07-19T12:00:01Z",
                "sensor_id": f"sensor-{token}-a",
                "msg": "Spaces stay; PUNCTUATION goes?! 9000"
            },
            {
                "ts": f"204{trial}-07-19T12:00:15Z",
                "sensor_id": f"sensor-{token}-b",
                "msg": f"Mixed_Case-{token}",
                "extra": token
            }
        ]
        lines = [json.dumps(record) for record in valid]
        lines.extend([
            '{"ts":"2040-01-01T00:00:00Z","sensor_id":"bad","msg":"broken \\u12XZ"}',
            '{"ts":"2040-01-01T00:00:00Z","sensor_id":"bad","msg":"orphan \\uD800"}',
            json.dumps({"ts": "2040-01-01T00:00:00Z", "sensor_id": "missing-msg"}),
            json.dumps({"ts": "2040-01-01T00:00:00Z", "sensor_id": 17, "msg": "wrong type"}),
            json.dumps(["not", "an", "object"]),
            "not json at all",
            ""
        ])
        random.SystemRandom().shuffle(lines)

        with tempfile.TemporaryDirectory(prefix=f"cleaner-{token}-") as directory:
            filepath = Path(directory) / f"telemetry-{secrets.token_hex(6)}.jsonl"
            filepath.write_text("\n".join(lines) + "\n", encoding="utf-8")
            expected = get_expected_output(filepath)
            actual = run_cleaner(filepath)
            assert actual == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
