#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import math
import os
import tarfile
import unicodedata
from collections import defaultdict

# Immutable copy of the input fixture, supplied only when verification runs.
PRISTINE_RECORDS = [
    {"timestamp": "2023-10-01T10:00:00Z", "context_key": "btn.save", "lang": "fr", "source": "Save", "target": "Enregistrer"},
    {"timestamp": "2023-10-01T12:00:00Z", "context_key": "btn.save", "lang": "fr", "source": "Save", "target": "Sauvegarder"},
    {"timestamp": "2023-10-02T10:00:00Z", "context_key": "btn.cancel", "lang": "fr", "source": "Cancel", "target": "Annuler"},
    {"timestamp": "2023-10-03T10:00:00Z", "context_key": "btn.ok", "lang": "fr", "source": "OK", "target": "OK"},
    {"timestamp": "2023-10-04T10:00:00Z", "context_key": "btn.delete", "lang": "fr", "source": "Delete", "target": "Supprimer"},
    {"timestamp": "2023-10-05T10:00:00Z", "context_key": "btn.edit", "lang": "fr", "source": "Edit", "target": "Modifier"},
    {"timestamp": "2023-10-06T10:00:00Z", "context_key": "btn.close", "lang": "fr", "source": "Close", "target": "Fermer"},
    {"timestamp": "2023-10-15T08:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "ファイル"},
    {"timestamp": "2023-10-15T09:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "ファイル"},
    {"timestamp": "2023-10-15T10:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "ファイル"},
    {"timestamp": "2023-10-16T08:30:00Z", "context_key": "menu.edit", "lang": "ja", "source": "Edit", "target": "編集"},
    {"timestamp": "2023-11-01T08:30:00Z", "context_key": "lbl.name", "lang": "es", "source": "Name", "target": "Nombre"},
    {"timestamp": "2023-11-02T08:30:00Z", "context_key": "lbl.age", "lang": "es", "source": "Age", "target": "Edad"},
    {"timestamp": "2023-11-03T08:30:00Z", "context_key": "lbl.email", "lang": "es", "source": "Email", "target": "Correo"},
]


def read_jsonl(path):
    records = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def get_expected_data():
    records = copy.deepcopy(PRISTINE_RECORDS)

    # 1. Normalize and deduplicate
    dedup_map = {}
    for r in records:
        key = (r.get('context_key'), r.get('lang'))
        r['target'] = unicodedata.normalize('NFKC', r.get('target', ''))

        if key not in dedup_map:
            dedup_map[key] = r
        elif r.get('timestamp', '') > dedup_map[key].get('timestamp', ''):
            dedup_map[key] = r

    dedup_records = list(dedup_map.values())

    # 2. Add month
    for r in dedup_records:
        r['month'] = r.get('timestamp', '')[:7]

    # 3. Stratified sampling
    groups = defaultdict(list)
    for r in dedup_records:
        groups[(r['month'], r['lang'])].append(r)

    review_records = []
    for (month, lang), group in groups.items():
        group.sort(key=lambda x: x['context_key'])
        n_sample = math.ceil(len(group) * 0.2)
        review_records.extend(group[:n_sample])

    return dedup_records, review_records


def test_raw_input_unchanged():
    raw_file = "/home/user/translations_raw.jsonl"
    assert os.path.exists(raw_file), f"Missing raw file: {raw_file}"
    assert read_jsonl(raw_file) == PRISTINE_RECORDS, "The provided raw input was modified"


def test_remote_sync_archive():
    local_archive = "/home/user/translations_archive.tar.gz"
    archive_path = "/home/user/remote_sync/translations_archive.tar.gz"
    assert os.path.exists(local_archive), f"Archive not found: {local_archive}"
    assert os.path.exists(archive_path), f"Archive not found in remote_sync: {archive_path}"

    with open(local_archive, 'rb') as f:
        local_archive_bytes = f.read()
    with open(archive_path, 'rb') as f:
        remote_archive_bytes = f.read()
    assert remote_archive_bytes == local_archive_bytes, "remote_sync archive is not a copy of the generated archive"

    expected_files = {
        'translations_dedup.jsonl': '/home/user/translations_dedup.jsonl',
        'translations_review.jsonl': '/home/user/translations_review.jsonl',
    }
    with tarfile.open(archive_path, 'r:gz') as tar:
        names = [os.path.basename(n) for n in tar.getnames()]
        assert 'translations_dedup.jsonl' in names, "translations_dedup.jsonl missing from tar archive"
        assert 'translations_review.jsonl' in names, "translations_review.jsonl missing from tar archive"

        for basename, source_path in expected_files.items():
            matches = [m for m in tar.getmembers() if os.path.basename(m.name) == basename]
            assert len(matches) == 1, f"Expected exactly one {basename} in tar archive"
            assert matches[0].isfile(), f"{basename} in tar archive is not a regular file"
            extracted = tar.extractfile(matches[0])
            assert extracted is not None
            with open(source_path, 'rb') as f:
                expected_bytes = f.read()
            assert extracted.read() == expected_bytes, f"Archived {basename} does not match the generated file"


def test_dedup_file_content():
    dedup_file = "/home/user/translations_dedup.jsonl"
    assert os.path.exists(dedup_file), f"Missing dedup file: {dedup_file}"

    expected_dedup, _ = get_expected_data()

    actual_dedup = []
    with open(dedup_file, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                assert line.strip() == json.dumps(json.loads(line), sort_keys=True, ensure_ascii=False), "JSON keys in translations_dedup.jsonl are not sorted alphabetically."
                actual_dedup.append(json.loads(line))

    assert len(actual_dedup) == len(expected_dedup), f"Expected {len(expected_dedup)} deduplicated records, got {len(actual_dedup)}"

    expected_dedup_sorted = sorted(expected_dedup, key=lambda x: (x.get('context_key', ''), x.get('lang', '')))
    actual_dedup_sorted = sorted(actual_dedup, key=lambda x: (x.get('context_key', ''), x.get('lang', '')))

    for exp, act in zip(expected_dedup_sorted, actual_dedup_sorted):
        assert exp == act, f"Mismatch in deduplicated record.\nExpected: {exp}\nGot: {act}"


def test_review_file_content():
    review_file = "/home/user/translations_review.jsonl"
    assert os.path.exists(review_file), f"Missing review file: {review_file}"

    _, expected_review = get_expected_data()

    actual_review = []
    with open(review_file, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                assert line.strip() == json.dumps(json.loads(line), sort_keys=True, ensure_ascii=False), "JSON keys in translations_review.jsonl are not sorted alphabetically."
                actual_review.append(json.loads(line))

    assert len(actual_review) == len(expected_review), f"Expected {len(expected_review)} review records, got {len(actual_review)}"

    expected_review_sorted = sorted(expected_review, key=lambda x: (x.get('context_key', ''), x.get('lang', '')))
    actual_review_sorted = sorted(actual_review, key=lambda x: (x.get('context_key', ''), x.get('lang', '')))

    for exp, act in zip(expected_review_sorted, actual_review_sorted):
        assert exp == act, f"Mismatch in review record.\nExpected: {exp}\nGot: {act}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
