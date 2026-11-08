#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import sqlite3
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/verify_backup.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
DB_PATH = "/app/metadata.db"


def run_filter(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(filepath)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    assert clean_files, f"No JSON files found in {CLEAN_CORPUS_DIR}."

    failed_files = []
    for filepath in clean_files:
        result = run_filter(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected (expected exit 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    assert evil_files, f"No JSON files found in {EVIL_CORPUS_DIR}."

    bypassed_files = []
    for filepath in evil_files:
        result = run_filter(filepath)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (expected non-zero exit). Offending files: {', '.join(bypassed_files)}")


def test_path_independent_generated_records(tmp_path):
    conn = sqlite3.connect(DB_PATH)
    inserted_ids = []
    cases = []
    try:
        existing = {row[0] for row in conn.execute("SELECT id FROM nodes")}
        for inbound_count in range(5):
            cluster_id = secrets.randbelow(1_000_000_000) + 1_000_000_000
            while cluster_id in existing:
                cluster_id = secrets.randbelow(1_000_000_000) + 1_000_000_000
            existing.add(cluster_id)
            inserted_ids.append(cluster_id)

            weight = secrets.randbelow(17) + 2
            conn.execute(
                "INSERT INTO nodes (id, cluster_name, centrality_weight) VALUES (?, ?, ?)",
                (cluster_id, "generated-" + uuid.uuid4().hex, weight),
            )
            for source_id in range(1, inbound_count + 1):
                conn.execute(
                    "INSERT INTO edges (source_id, target_id) VALUES (?, ?)",
                    (source_id, cluster_id),
                )

            expected = conn.execute(
                "SELECT COUNT(e.source_id) * n.centrality_weight "
                "FROM nodes n LEFT JOIN edges e ON e.target_id = n.id "
                "WHERE n.id = ? GROUP BY n.id, n.centrality_weight",
                (cluster_id,),
            ).fetchone()[0]

            valid_path = tmp_path / (uuid.uuid4().hex + ".json")
            invalid_path = tmp_path / (uuid.uuid4().hex + ".json")
            valid_path.write_text(json.dumps({
                "backup_id": "bkp-" + uuid.uuid4().hex,
                "cluster_id": cluster_id,
                "validation_hash": expected,
            }))
            invalid_path.write_text(json.dumps({
                "backup_id": "bkp-" + uuid.uuid4().hex,
                "cluster_id": cluster_id,
                "validation_hash": expected + secrets.randbelow(19) + 1,
            }))
            cases.extend([(valid_path, 0), (invalid_path, 1)])

        conn.commit()
        random.SystemRandom().shuffle(cases)

        failures = []
        for filepath, expected_code in cases:
            result = run_filter(filepath)
            if result.returncode != expected_code:
                failures.append(
                    f"{filepath.name}: expected {expected_code}, got {result.returncode}; "
                    f"stderr={result.stderr.decode(errors='replace')!r}"
                )
        assert not failures, "Generated path-neutral checks failed:\n" + "\n".join(failures)
    finally:
        if inserted_ids:
            placeholders = ",".join("?" for _ in inserted_ids)
            conn.execute(f"DELETE FROM edges WHERE target_id IN ({placeholders})", inserted_ids)
            conn.execute(f"DELETE FROM nodes WHERE id IN ({placeholders})", inserted_ids)
            conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
