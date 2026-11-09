#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import unicodedata
import uuid

import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
EXPECTED_CLEAN = {}
EXPECTED_EVIL = {}


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def prepare_corpora():
    for corpus_dir in (CLEAN_DIR, EVIL_DIR):
        os.makedirs(corpus_dir, exist_ok=True)
        for name in os.listdir(corpus_dir):
            path = os.path.join(corpus_dir, name)
            if name.endswith(".json") and os.path.isfile(path):
                os.remove(path)
        shutil.rmtree(os.path.join(corpus_dir, "sanitized"), ignore_errors=True)

    token = uuid.uuid4().hex
    clean_batches = {
        "clean_multilingual.json": [
            {"id": f"clean-{token}-1", "timestamp": "2026-01-01T00:00:00Z", "text": "Bonjour, café déjà vu.", "retry_count": 0},
            {"id": f"clean-{token}-2", "timestamp": "2026-01-01T00:00:01Z", "text": "مرحبا بالعالم", "retry_count": 1},
            {"id": f"clean-{token}-3", "timestamp": "2026-01-01T00:00:02Z", "text": "こんにちは世界 🌍", "retry_count": 0},
        ],
        "clean_more.json": [
            {"id": f"clean-{token}-4", "timestamp": "2026-01-02T10:00:00Z", "text": "Заявка обработана успешно", "retry_count": 2},
            {"id": f"clean-{token}-5", "timestamp": "2026-01-02T10:00:01Z", "text": "한국어 고객 지원 기록", "retry_count": 0},
        ],
    }

    nfc_text = "Résumé du client à Montréal"
    nfd_text = unicodedata.normalize("NFD", nfc_text)
    first_a = {"id": f"evil-{token}-a", "timestamp": "2026-02-01T00:00:00Z", "text": nfc_text, "retry_count": 0}
    duplicate_a = {"id": first_a["id"], "timestamp": "2026-02-01T00:00:01Z", "text": nfd_text, "retry_count": 1}

    first_b = {"id": f"evil-{token}-b", "timestamp": "2026-02-01T00:01:00Z", "text": "客户请求已经解决", "retry_count": 0}
    duplicate_b = {"id": first_b["id"], "timestamp": "2026-02-01T00:01:01Z", "text": "客户请求\u200b已经解决", "retry_count": 2}

    first_c = {"id": f"evil-{token}-c", "timestamp": "2026-02-02T00:00:00Z", "text": "Normal service transcript with steady text density", "retry_count": 0}
    duplicate_c = {"id": first_c["id"], "timestamp": "2026-02-02T00:00:01Z", "text": "Normal service transcript" + ("\u200b" * 80) + " with steady text density", "retry_count": 4}

    first_d = {"id": f"evil-{token}-d", "timestamp": "2026-02-02T00:02:00Z", "text": "Texto válido en español", "retry_count": 0}
    duplicate_d = {"id": first_d["id"], "timestamp": "2026-02-02T00:02:01Z", "text": "Texto válido en espa\u200bñol", "retry_count": 3}

    evil_batches = {
        "evil_unicode.json": [first_a, duplicate_a, first_b, duplicate_b],
        "evil_changepoint.json": [first_c, duplicate_c, first_d, duplicate_d],
    }

    for filename, records in clean_batches.items():
        write_json(os.path.join(CLEAN_DIR, filename), records)
        EXPECTED_CLEAN[filename] = records

    for filename, records in evil_batches.items():
        write_json(os.path.join(EVIL_DIR, filename), records)

    EXPECTED_EVIL["evil_unicode.json"] = [first_a, first_b]
    EXPECTED_EVIL["evil_changepoint.json"] = [first_c, first_d]


@pytest.fixture(scope="session", autouse=True)
def run_agent_tool():
    prepare_corpora()

    app_dir = "/home/user/etl_filter"
    assert os.path.isdir(app_dir), f"Rust application directory missing at {app_dir}"
    assert os.path.isfile(os.path.join(app_dir, "Cargo.toml")), "Cargo.toml is missing"

    res_clean = subprocess.run(
        ["cargo", "run", "--release", "--", "--input-dir", CLEAN_DIR],
        cwd=app_dir,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert res_clean.returncode == 0, f"Cargo run failed on clean corpus.\nSTDOUT:\n{res_clean.stdout}\nSTDERR:\n{res_clean.stderr}"

    res_evil = subprocess.run(
        ["cargo", "run", "--release", "--", "--input-dir", EVIL_DIR],
        cwd=app_dir,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert res_evil.returncode == 0, f"Cargo run failed on evil corpus.\nSTDOUT:\n{res_evil.stdout}\nSTDERR:\n{res_evil.stderr}"


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def test_audio_baseline():
    baseline_path = "/home/user/audio_baseline.txt"
    assert os.path.isfile(baseline_path), f"Audio baseline output missing at {baseline_path}"
    with open(baseline_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "0.00", f"Expected average amplitude to be '0.00', but got '{content}'"


def test_clean_corpus_preserved():
    sanitized_dir = os.path.join(CLEAN_DIR, "sanitized")
    assert os.path.isdir(sanitized_dir), f"Sanitized directory not created for clean corpus at {sanitized_dir}"

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]
    assert len(clean_files) > 0, "No JSON files found in clean corpus"

    failed_files = []
    for filename in clean_files:
        san_path = os.path.join(sanitized_dir, filename)
        if not os.path.isfile(san_path):
            failed_files.append(filename)
            continue
        try:
            san_data = load_json(san_path)
        except (json.JSONDecodeError, UnicodeDecodeError):
            failed_files.append(filename)
            continue

        orig_data = load_json(os.path.join(CLEAN_DIR, filename))
        if len(orig_data) != len(san_data) or san_data != EXPECTED_CLEAN[filename]:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified or omitted: {failed_files}"


def test_evil_corpus_filters_only_duplicates():
    sanitized_dir = os.path.join(EVIL_DIR, "sanitized")
    assert os.path.isdir(sanitized_dir), f"Sanitized directory not created for evil corpus at {sanitized_dir}"

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    assert len(evil_files) > 0, "No JSON files found in evil corpus"

    failed_files = []
    for filename in evil_files:
        san_path = os.path.join(sanitized_dir, filename)
        if not os.path.isfile(san_path):
            failed_files.append(filename)
            continue
        try:
            san_data = load_json(san_path)
        except (json.JSONDecodeError, UnicodeDecodeError):
            failed_files.append(filename)
            continue

        if san_data != EXPECTED_EVIL[filename]:
            failed_files.append(filename)

    assert not failed_files, f"Duplicate filtering or first-seen record preservation failed for: {failed_files}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
