#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

EXECUTABLE = Path("/home/user/log_organizer")
SOURCE = Path("/home/user/log_organizer.go")
CLEAN_CORPUS = Path("/app/corpus/clean")
EVIL_CORPUS = Path("/app/corpus/evil")


def run_tool(archive, output):
    return subprocess.run(
        [str(EXECUTABLE), str(archive), str(output)],
        capture_output=True,
        text=True,
        timeout=15,
    )


def add_file(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o600
    tar.addfile(info, io.BytesIO(data))


def output_files(root):
    return [p for p in Path(root).rglob("*") if p.is_file()]


def test_executable_exists():
    """Ensure the requested Go source and compiled executable exist."""
    assert SOURCE.is_file(), f"Go source not found at {SOURCE}"
    assert EXECUTABLE.is_file(), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"

    result = subprocess.run(
        ["go", "version", str(EXECUTABLE)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0 and "go1" in result.stdout.lower(), (
        "The compiled artifact is not recognized as a Go executable: "
        + result.stdout + result.stderr
    )


def test_shipped_corpora():
    """Retain the checks against the archives supplied by the task."""
    assert CLEAN_CORPUS.is_dir(), f"Clean corpus directory missing: {CLEAN_CORPUS}"
    assert EVIL_CORPUS.is_dir(), f"Evil corpus directory missing: {EVIL_CORPUS}"

    clean_files = sorted(CLEAN_CORPUS.glob("*.tar.gz"))
    evil_files = sorted(EVIL_CORPUS.glob("*.tar.gz"))
    assert clean_files, "Clean corpus contains no archives"
    assert evil_files, "Evil corpus contains no archives"

    clean_failed = []
    evil_failed = []

    for archive in clean_files:
        with tempfile.TemporaryDirectory() as out_dir:
            result = run_tool(archive, out_dir)
            if result.returncode != 0:
                clean_failed.append(
                    f"{archive.name} (rejected with exit code {result.returncode})"
                )
                continue

            extracted = set(os.listdir(out_dir))
            if archive.name == "app_logs.tar.gz":
                expected = {"SECURELOG_web.txt", "SECURELOG_db.txt"}
                if not expected.issubset(extracted):
                    clean_failed.append(
                        f"{archive.name} (missing expected renamed files, got {extracted})"
                    )
                else:
                    for name in expected:
                        path = Path(out_dir, name)
                        if not path.is_file() or path.read_bytes() != b"test":
                            clean_failed.append(
                                f"{archive.name} ({name} did not preserve file contents)"
                            )

    for archive in evil_files:
        with tempfile.TemporaryDirectory() as out_dir:
            result = run_tool(archive, out_dir)
            combined = result.stdout + result.stderr
            if result.returncode == 0:
                evil_failed.append(f"{archive.name} (exit code 0 - bypassed)")
                continue
            if os.listdir(out_dir):
                evil_failed.append(
                    f"{archive.name} (files written to out_dir despite being evil: "
                    f"{os.listdir(out_dir)})"
                )
            if "MALICIOUS ARCHIVE" not in combined:
                evil_failed.append(f"{archive.name} (required rejection message missing)")

    errors = []
    if evil_failed:
        errors.append(
            f"{len(evil_failed)} evil-corpus failures: " + ", ".join(evil_failed)
        )
    if clean_failed:
        errors.append(
            f"{len(clean_failed)} clean-corpus failures: " + ", ".join(clean_failed)
        )
    assert not errors, " | ".join(errors)


def test_unseen_clean_archive_is_extracted_renamed_and_preserved():
    """Exercise recursive processing with names and contents chosen at test time."""
    token = secrets.token_hex(7)
    entries = {
        f"root_{token}.log": secrets.token_bytes(37),
        f"service/nested_{token}.log": secrets.token_bytes(513),
        f"service/deeper/audit_{token}.log": secrets.token_bytes(1027),
    }

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        archive = tmp / f"clean_{token}.tar.gz"
        out = tmp / "output"
        out.mkdir()

        with tarfile.open(archive, "w:gz") as tar:
            for directory in ("service", "service/deeper"):
                info = tarfile.TarInfo(directory)
                info.type = tarfile.DIRTYPE
                info.mode = 0o700
                tar.addfile(info)
            for name, data in entries.items():
                add_file(tar, name, data)

        result = run_tool(archive, out)
        assert result.returncode == 0, result.stdout + result.stderr

        found = {}
        for path in output_files(out):
            found.setdefault(path.name, []).append(path)

        expected_names = {
            f"SECURELOG_{Path(name).stem}.txt" for name in entries
        }
        assert set(found) == expected_names, (
            f"Wrong output filenames: expected {expected_names}, got {set(found)}"
        )

        for original, data in entries.items():
            renamed = f"SECURELOG_{Path(original).stem}.txt"
            assert len(found[renamed]) == 1, f"Expected exactly one {renamed}"
            assert found[renamed][0].read_bytes() == data, (
                f"Contents were not preserved for {original}"
            )


def test_unseen_malicious_archives_are_atomic_and_reported():
    """Test traversal spellings, absolute paths, and cleanup after a safe prefix."""
    token = secrets.token_hex(7)

    with tempfile.TemporaryDirectory() as tmp_name:
        base = Path(tmp_name)
        work = base / "work"
        work.mkdir()

        cases = [
            ("parent", f"../escaped_{token}.log"),
            ("embedded", f"safe/../embedded_{token}.log"),
            ("deep", f"dir/../../deep_{token}.log"),
            ("backslash", f"..\\backslash_{token}.log"),
            ("backslash_embedded", f"dir\\..\\win_{token}.log"),
            ("absolute", str(base / f"absolute_{token}.log")),
        ]

        for label, malicious_name in cases:
            case_dir = work / label
            case_dir.mkdir()
            archive = case_dir / "input.tar.gz"
            out = case_dir / "output"
            out.mkdir()

            with tarfile.open(archive, "w:gz") as tar:
                # A correct implementation must remove this if a later header is evil.
                add_file(tar, f"safe_prefix_{token}.log", secrets.token_bytes(41))
                add_file(tar, malicious_name, secrets.token_bytes(43))

            result = run_tool(archive, out)
            combined = result.stdout + result.stderr
            assert result.returncode != 0, f"{label} traversal was accepted"
            assert "MALICIOUS ARCHIVE" in combined, (
                f"{label} rejection did not print MALICIOUS ARCHIVE"
            )
            assert list(out.iterdir()) == [], (
                f"{label} rejection left output artifacts: {list(out.iterdir())}"
            )

            absolute_target = base / f"absolute_{token}.log"
            assert not absolute_target.exists(), "Absolute archive path was written"
            assert not (case_dir / f"escaped_{token}.log").exists()
            assert not (case_dir / f"deep_{token}.log").exists()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
