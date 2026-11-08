#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import stat
import string
import subprocess
import tempfile
from pathlib import Path

import pytest
from PIL import Image, ImageChops, ImageDraw


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file {path} not found."
    assert not os.path.islink(path), f"{path} must not be a symbolic link."
    assert stat.S_ISREG(os.stat(path).st_mode), f"{path} must be a regular file."


def test_batch_id_recovered():
    """Check that the Batch ID in the screenshot was written to the log."""
    log_path = "/home/user/batch_id_recovery.log"
    assert os.path.exists(log_path), f"Log file {log_path} not found. Did you extract the Batch ID?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    # Preserve the original correctness assertion.
    assert "BATCH-77A90X" in content, f"Extracted Batch ID is incorrect or missing in {log_path}."

    # Independently tie the submitted value to the actual screenshot pixels.
    matches = re.findall(r"BATCH-[A-Za-z0-9_-]+", content)
    assert len(matches) == 1, "The recovery log must contain exactly one Batch ID."
    recovered = matches[0]
    screenshot = Image.open("/app/ticket_8819_screenshot.png").convert("RGB")
    rendered = Image.new("RGB", screenshot.size, color=(0, 0, 0))
    ImageDraw.Draw(rendered).text(
        (10, 40), f"Error in Batch ID: {recovered}", fill=(255, 255, 255)
    )
    assert ImageChops.difference(screenshot, rendered).getbbox() is None, \
        "The Batch ID in the recovery log does not match the attached screenshot."


def run_validator(script_path, filename):
    return subprocess.run(
        ["python3", script_path, filename],
        capture_output=True,
        text=True,
        timeout=5,
    )


def assert_validation(script_path, filename, safe):
    expected_text = "SAFE" if safe else "UNSAFE"
    expected_code = 0 if safe else 1
    res = run_validator(script_path, filename)
    assert res.returncode == expected_code, (
        f"Wrong exit code for {filename!r}: expected {expected_code}, got {res.returncode}"
    )
    assert res.stdout in (expected_text, expected_text + "\n"), (
        f"Wrong stdout for {filename!r}: expected exactly {expected_text!r}, got {res.stdout!r}"
    )


def test_validate_script_adversarial_corpus():
    """Preserve the original clean and malicious corpus checks."""
    script_path = "/home/user/validate.py"
    assert_regular_file(script_path)

    evil_corpus_path = "/app/corpora/evil_filenames.txt"
    clean_corpus_path = "/app/corpora/clean_filenames.txt"
    assert os.path.exists(evil_corpus_path), f"Evil corpus missing at {evil_corpus_path}"
    assert os.path.exists(clean_corpus_path), f"Clean corpus missing at {clean_corpus_path}"

    with open(evil_corpus_path, "r") as f:
        evil_files = [line.strip("\n") for line in f if line.strip("\n")]
    with open(clean_corpus_path, "r") as f:
        clean_files = [line.strip("\n") for line in f if line.strip("\n")]

    evil_bypassed = []
    for evil_file in evil_files:
        res = run_validator(script_path, evil_file)
        if res.returncode != 1 or res.stdout.strip() != "UNSAFE":
            evil_bypassed.append(evil_file)

    clean_modified = []
    for clean_file in clean_files:
        res = run_validator(script_path, clean_file)
        if res.returncode != 0 or res.stdout.strip() != "SAFE":
            clean_modified.append(clean_file)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {clean_modified}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_validate_script_generated_inputs():
    """Exercise the validator on unpredictable inputs derived from the stated grammar."""
    script_path = "/home/user/validate.py"
    assert_regular_file(script_path)

    alphabet = string.ascii_letters + string.digits + "_-"
    safe_names = []
    for i in range(36):
        stem = "".join(secrets.choice(alphabet) for _ in range(12 + (i % 13)))
        safe_names.append(stem + secrets.choice([".png", ".jpg", ".jpeg"]))

    token = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
    unsafe_names = [
        f"{token} file.png",
        f"../{token}.jpg",
        f"..\\{token}.jpeg",
        f"folder/{token}.png",
        f"{token}.gif",
        f"{token}.PNG",
        f"{token}.png.exe",
        f"{token}.tar.jpg",
        f"{token};echo.png",
        f"{token}&whoami.jpg",
        f"{token}|cat.jpeg",
        f"{token}$(id).png",
        f"{token}`id`.jpg",
        f"{token}>out.jpeg",
        f"{token}<in.png",
        f"{token}*.jpg",
        f"{token}?.jpeg",
        f"{token}[abc].png",
        f"{token}\nnext.jpg",
        ".png",
        "",
    ]

    for filename in safe_names:
        assert re.fullmatch(r"[A-Za-z0-9_-]+\.(png|jpg|jpeg)", filename)
        assert_validation(script_path, filename, True)
    for filename in unsafe_names:
        assert not re.fullmatch(r"[A-Za-z0-9_-]+\.(png|jpg|jpeg)", filename)
        assert_validation(script_path, filename, False)


def test_ingest_safely_processes_every_file_concurrently():
    """Run ingest.py against a fresh DB and verify no records are lost or injected."""
    ingest_path = "/home/user/pipeline/ingest.py"
    db_path = Path("/home/user/pipeline/metadata.db")
    assert_regular_file(ingest_path)

    source_dir = Path(tempfile.mkdtemp(prefix="ticket8819_ingest_"))
    backup_dir = Path(tempfile.mkdtemp(prefix="ticket8819_db_backup_"))
    db_related = [db_path, Path(str(db_path) + "-wal"), Path(str(db_path) + "-shm")]

    for path in db_related:
        if path.exists():
            os.replace(path, backup_dir / path.name)

    names = [f"image_{i:04d}_{secrets.token_hex(4)}.png" for i in range(240)]
    names += [
        "space name.png",
        "quote'name.jpg",
        "semi;colon.jpeg",
        "amp&ersand.png",
        "bracket[1].jpg",
        "--leading-option.jpeg",
        "line\nbreak.png",
        "dollar$(touch PWNED_SUB).png",
        "payload;touch PWNED_CMD;#.jpg",
        "back`touch PWNED_TICK`.jpeg",
    ]

    try:
        for name in names:
            (source_dir / name).write_bytes(b"sample image metadata\n")

        expected = {str(source_dir / name) for name in names}
        res = subprocess.run(
            ["python3", ingest_path, str(source_dir)],
            cwd=str(source_dir),
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert res.returncode == 0, (
            f"ingest.py failed with exit code {res.returncode}. "
            f"stdout={res.stdout!r}, stderr={res.stderr!r}"
        )
        assert db_path.exists(), "ingest.py did not create metadata.db"

        conn = sqlite3.connect(str(db_path))
        try:
            rows = conn.execute("SELECT filename, status FROM images").fetchall()
        finally:
            conn.close()

        actual = {row[0] for row in rows}
        assert len(rows) == len(names), (
            f"Expected {len(names)} database records but found {len(rows)}; records were dropped."
        )
        assert actual == expected, (
            f"Database filenames differ from the processed files. "
            f"Missing={sorted(expected - actual)!r}, unexpected={sorted(actual - expected)!r}"
        )
        assert all(status in ("valid", "invalid") for _, status in rows), \
            "Every image record must have a valid ingestion status."
        for marker in ("PWNED_SUB", "PWNED_CMD", "PWNED_TICK"):
            assert not (source_dir / marker).exists(), \
                f"Shell metacharacters were executed: marker {marker} was created."
    finally:
        for path in db_related:
            if path.exists():
                path.unlink()
        for saved in backup_dir.iterdir():
            os.replace(saved, db_path.parent / saved.name)
        shutil.rmtree(source_dir, ignore_errors=True)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
