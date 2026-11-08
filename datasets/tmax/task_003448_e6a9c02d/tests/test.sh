#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess

import pytest

BINARY_PATH = "/home/user/backup_validator/target/release/backup_validator"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
PROJECT_DIR = "/home/user/backup_validator"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_release_binary_is_compiled_project_artifact():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "src/main.rs is missing"
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "Release artifact is not an ELF executable"


def test_clean_corpus():
    clean_files = sorted(glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json")))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for f in clean_files:
        result = subprocess.run([BINARY_PATH, f], capture_output=True, text=True)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected instead of accepted): {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = sorted(glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json")))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    bypassed_files = []
    for f in evil_files:
        result = subprocess.run([BINARY_PATH, f], capture_output=True, text=True)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {', '.join(bypassed_files)}")


def pg(sql):
    result = subprocess.run(
        ["runuser", "-u", "postgres", "--", "psql", "-X", "-v", "ON_ERROR_STOP=1",
         "-d", "backups_db", "-c", sql],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"PostgreSQL setup failed: {result.stderr}"


def redis(*args):
    result = subprocess.run(["redis-cli", *args], capture_output=True, text=True)
    assert result.returncode == 0, f"Redis setup failed: {result.stderr}"
    return result.stdout


def invoke(path, should_accept):
    try:
        result = subprocess.run(
            [BINARY_PATH, path], capture_output=True, text=True, timeout=12
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Validator timed out while traversing a generated graph")

    if should_accept:
        assert result.returncode == 0, (
            f"Expected ACCEPT, got exit {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert "ACCEPT" in result.stdout, f"Expected ACCEPT in stdout, got {result.stdout!r}"
    else:
        assert result.returncode == 1, (
            f"Expected REJECT, got exit {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert "REJECT" in result.stdout, f"Expected REJECT in stdout, got {result.stdout!r}"


def test_generated_live_service_cases_and_schema_validation():
    token = secrets.token_hex(12)
    root = "n" + token + "r"
    middle = "n" + token + "m"
    leaf = "n" + token + "l"
    missing = "n" + token + "x"
    manifest_path = "/tmp/manifest_" + secrets.token_hex(12)

    def write_manifest(value):
        with open(manifest_path, "w", encoding="utf-8") as f:
            if isinstance(value, str):
                f.write(value)
            else:
                json.dump(value, f)

    def restore_graph():
        pg(f"""
            INSERT INTO backup_nodes (id, parent_id, backup_type, size_bytes) VALUES
              ('{root}', NULL, 'FULL', 9001),
              ('{middle}', '{root}', 'INCREMENTAL', 101),
              ('{leaf}', '{middle}', 'DIFFERENTIAL', 51)
            ON CONFLICT (id) DO UPDATE SET
              parent_id = EXCLUDED.parent_id,
              backup_type = EXCLUDED.backup_type,
              size_bytes = EXCLUDED.size_bytes;
        """)
        redis("SET", "manifest:" + leaf, json.dumps({"checksum": token, "status": "AVAILABLE"}))

    def invalid_archived():
        restore_graph()
        redis("SET", "manifest:" + leaf, json.dumps({"checksum": token, "status": "ARCHIVED"}))

    def invalid_missing_redis():
        restore_graph()
        redis("DEL", "manifest:" + leaf)

    def invalid_missing_parent():
        restore_graph()
        pg(f"UPDATE backup_nodes SET parent_id = '{missing}' WHERE id = '{middle}';")

    def invalid_cycle():
        restore_graph()
        pg(f"UPDATE backup_nodes SET parent_id = '{leaf}' WHERE id = '{middle}';")

    def invalid_non_full_root():
        restore_graph()
        pg(f"UPDATE backup_nodes SET backup_type = 'DIFFERENTIAL' WHERE id = '{root}';")

    def invalid_deleted_dependency():
        restore_graph()
        pg(f"DELETE FROM backup_nodes WHERE id = '{middle}';")

    try:
        restore_graph()
        write_manifest({"backup_id": leaf})
        invoke(manifest_path, True)

        mutations = [
            invalid_archived,
            invalid_missing_redis,
            invalid_missing_parent,
            invalid_cycle,
            invalid_non_full_root,
            invalid_deleted_dependency,
        ]
        random.SystemRandom().shuffle(mutations)

        # Each property is exercised in an unpredictable valid/invalid order using
        # the same generated ID and filename, so filename or ID lookup tables cannot pass.
        for make_invalid in mutations:
            if secrets.randbits(1):
                make_invalid()
                invoke(manifest_path, False)
                restore_graph()
                invoke(manifest_path, True)
            else:
                restore_graph()
                invoke(manifest_path, True)
                make_invalid()
                invoke(manifest_path, False)

        restore_graph()
        malformed = [
            "{not-json",
            {},
            {"wrong_key": leaf},
            {"backup_id": leaf, "extra": True},
            {"backup_id": 123},
            [leaf],
            None,
        ]
        random.SystemRandom().shuffle(malformed)
        for value in malformed:
            write_manifest(value if isinstance(value, str) else value)
            invoke(manifest_path, False)

        write_manifest({"backup_id": leaf})
        restore_graph()
        invoke(manifest_path, True)
    finally:
        redis("DEL", "manifest:" + leaf)
        pg(f"DELETE FROM backup_nodes WHERE id IN ('{leaf}', '{middle}', '{root}');")
        try:
            os.unlink(manifest_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
