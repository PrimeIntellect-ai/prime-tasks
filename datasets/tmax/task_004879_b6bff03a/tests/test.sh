#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile

AUTH_PREFIX_PATH = "/home/user/auth_prefix.txt"
EXPECTED_PREFIX = "delta_seven_uniform_nine"
LOG_FILTER_DIR = "/home/user/log_filter"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
RAW_BACKUPS_DIR = "/app/raw_backups/"
DIFF_BACKUP_TAR = "/home/user/secure_archive/diff_backup.tar"
BACKUP_SNAR = "/home/user/secure_archive/backup.snar"
BASELINE_SNAR = "/app/baseline/baseline.snar"


def run_filter(path):
    res = subprocess.run(
        ["cargo", "run", "--release", "--", path],
        cwd=LOG_FILTER_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert res.returncode == 0, f"Log filter failed for {path}:\n{res.stderr}"

    parsed = []
    for line_number, line in enumerate(res.stdout.splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(
                f"Output line {line_number} for {path} is not valid JSON: {line!r}"
            ) from exc
        assert isinstance(value, dict), f"Output line {line_number} is not a JSON object"
        parsed.append(value)
    return parsed


def test_auth_prefix_extracted():
    assert os.path.isfile(AUTH_PREFIX_PATH), f"Missing auth prefix file at {AUTH_PREFIX_PATH}"
    with open(AUTH_PREFIX_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_PREFIX, f"Expected auth prefix '{EXPECTED_PREFIX}', got '{content}'"


def test_rust_log_filter_compiles_and_runs():
    assert os.path.isdir(LOG_FILTER_DIR), f"Missing Rust project directory at {LOG_FILTER_DIR}"
    cargo_toml = os.path.join(LOG_FILTER_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Missing Cargo.toml in {LOG_FILTER_DIR}"

    res = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=LOG_FILTER_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert res.returncode == 0, f"Cargo build failed:\n{res.stderr}"


def test_adversarial_corpus_log_filter():
    clean_files = sorted(f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".json"))
    evil_files = sorted(f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".json"))
    assert clean_files, "Clean corpus is empty"
    assert evil_files, "Evil corpus is empty"

    clean_modified = []
    evil_bypassed = []

    for c_file in clean_files:
        path = os.path.join(CLEAN_CORPUS_DIR, c_file)
        with open(path, "r") as f:
            expected = [json.loads(line) for line in f if line.strip()]
        actual = run_filter(path)
        if actual != expected:
            clean_modified.append(c_file)

    for e_file in evil_files:
        path = os.path.join(EVIL_CORPUS_DIR, e_file)
        actual = run_filter(path)
        if actual:
            evil_bypassed.append(e_file)

    err_msg = []
    if evil_bypassed:
        err_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        err_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:5])}")
    assert not err_msg, " | ".join(err_msg)


def test_generated_mixed_log_filter():
    token = secrets.token_hex(10)
    positive_size = secrets.randbelow(1_000_000) + 1
    entries = [
        {"file_path": f"/backup/{token}.txt", "size_bytes": positive_size, "tag": token},
        {"file_path": f"relative/{token}.log", "size_bytes": 0},
        {"file_path": "/backup", "size_bytes": 42},
        {"file_path": f"../../etc/{token}", "size_bytes": 5},
        {"file_path": f"safe/../{token}", "size_bytes": 8},
        {"file_path": f"/etc/{token}", "size_bytes": 10},
        {"file_path": f"/backup/{token}-negative", "size_bytes": -1},
        {"file_path": f"/backup/{token}-float", "size_bytes": 1.5},
        {"file_path": f"/backup/{token}-string", "size_bytes": "100"},
        {"file_path": f"/backup/{token}-bool", "size_bytes": True},
    ]
    expected = entries[:3]

    fd, path = tempfile.mkstemp(prefix=f"log-{token}-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
        assert run_filter(path) == expected, "Filter did not emit exactly the valid generated objects"
    finally:
        os.unlink(path)


def test_bulk_file_renaming():
    files = os.listdir(RAW_BACKUPS_DIR)
    assert len(files) > 0, f"No files found in {RAW_BACKUPS_DIR}"

    for f in files:
        assert f.startswith(f"{EXPECTED_PREFIX}-"), (
            f"File {f} in {RAW_BACKUPS_DIR} is not properly prefixed with {EXPECTED_PREFIX}-"
        )

    expected = {f"{EXPECTED_PREFIX}-file_{i:02d}.bin" for i in range(1, 51)}
    assert set(files) == expected, "Raw backup directory does not contain exactly all 50 renamed files"
    for name in expected:
        assert os.path.isfile(os.path.join(RAW_BACKUPS_DIR, name)), f"{name} is not a regular file"


def test_differential_backup_archive():
    assert os.path.isfile(DIFF_BACKUP_TAR), f"Missing differential backup tar at {DIFF_BACKUP_TAR}"
    assert os.path.isfile(BACKUP_SNAR), f"Missing snapshot file at {BACKUP_SNAR}"
    assert os.path.isfile(BASELINE_SNAR), f"Missing baseline snapshot at {BASELINE_SNAR}"
    assert os.path.getsize(BACKUP_SNAR) > 0, "Snapshot file is empty"

    expected_names = {f"{EXPECTED_PREFIX}-file_{i:02d}.bin" for i in range(1, 51)}
    archived = {}
    has_incremental_directory_record = False

    with tarfile.open(DIFF_BACKUP_TAR, "r:") as tar:
        members = tar.getmembers()
        has_incremental_directory_record = any(
            member.type == tarfile.GNUTYPE_DUMPDIR for member in members
        )
        for member in members:
            if not member.isfile():
                continue
            basename = os.path.basename(member.name.rstrip("/"))
            assert basename not in archived, f"Duplicate archived file basename: {basename}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file {member.name}"
            archived[basename] = extracted.read()

    bin_files = [name for name in archived if name.endswith(".bin")]
    assert len(bin_files) > 0, "No .bin files found in the differential backup tar"
    for name in bin_files:
        assert name.startswith(f"{EXPECTED_PREFIX}-"), f"Archived file {name} is not properly prefixed"

    assert set(archived) == expected_names, (
        "Archive regular-file contents do not exactly match the 50 renamed raw backup files"
    )
    for name in expected_names:
        with open(os.path.join(RAW_BACKUPS_DIR, name), "rb") as f:
            assert archived[name] == f.read(), f"Archived contents differ for {name}"

    assert has_incremental_directory_record, (
        "Archive lacks GNU listed-incremental directory records"
    )

    with open(BASELINE_SNAR, "rb") as f:
        baseline_bytes = f.read()
    with open(BACKUP_SNAR, "rb") as f:
        submitted_bytes = f.read()
    assert b"dummy_dir" in baseline_bytes, "Baseline snapshot lacks its expected directory record"
    assert b"dummy_dir" in submitted_bytes, (
        "Backup snapshot does not retain the supplied baseline snapshot's directory record"
    )
    assert submitted_bytes != baseline_bytes, "Backup snapshot was not updated by the differential backup"

    with tempfile.TemporaryDirectory() as td:
        snapshot_copy = os.path.join(td, "backup.snar")
        followup_tar = os.path.join(td, "followup.tar")
        shutil.copyfile(BACKUP_SNAR, snapshot_copy)
        res = subprocess.run(
            [
                "tar",
                "--listed-incremental=" + snapshot_copy,
                "-cf",
                followup_tar,
                RAW_BACKUPS_DIR,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert res.returncode == 0, f"Snapshot is not usable by GNU tar:\n{res.stderr}"
        with tarfile.open(followup_tar, "r:") as tar:
            repeated_bins = [m.name for m in tar.getmembers() if m.isfile() and m.name.endswith(".bin")]
        assert not repeated_bins, (
            "Snapshot does not record the archived raw backup files as already backed up"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
