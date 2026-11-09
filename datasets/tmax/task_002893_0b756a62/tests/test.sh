#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

P7ZIP_DIR = Path("/app/p7zip_16.02")
SEVEN_ZA = P7ZIP_DIR / "bin/7za"
ARCHIVE = Path("/home/user/project_logs.7z.001")
LOGS_DIR = Path("/home/user/logs")
SCRIPT = Path("/home/user/filter_records.sh")


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, timeout=60, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {args}\n"
        f"stdout: {result.stdout[-2000:]!r}\n"
        f"stderr: {result.stderr[-2000:]!r}"
    )
    return result


def tree_manifest(root):
    root = Path(root)
    manifest = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            manifest[rel] = ("symlink", os.readlink(path))
        elif path.is_dir():
            manifest[rel] = ("dir",)
        elif path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest[rel] = ("file", path.stat().st_size, digest)
        else:
            manifest[rel] = ("other",)
    return manifest


def test_phase1_extraction(tmp_path):
    # Preserve the original state assertions.
    assert LOGS_DIR.is_dir(), f"Directory {LOGS_DIR} does not exist. Extraction failed or was not performed."
    extracted_files = os.listdir(LOGS_DIR)
    assert len(extracted_files) > 0, f"Directory {LOGS_DIR} is empty. No files were extracted."

    # The deliberately broken compiler definition must have been repaired.
    machine = P7ZIP_DIR / "makefile.machine"
    assert machine.is_file(), f"Missing build configuration: {machine}"
    config = machine.read_text(errors="replace")
    assert "CXX=g++++" not in config, "The misspelled C++ compiler definition was not fixed."
    assert re.search(r"(?m)^\s*CXX\s*=\s*g\+\+\s*$", config), "makefile.machine does not define CXX as g++."

    # A real compiled standalone extractor must exist and run.
    assert SEVEN_ZA.is_file(), f"Compiled extractor {SEVEN_ZA} does not exist."
    assert os.access(SEVEN_ZA, os.X_OK), f"Compiled extractor {SEVEN_ZA} is not executable."
    assert SEVEN_ZA.read_bytes()[:4] == b"\x7fELF", "bin/7za is not a compiled ELF executable."
    info = run_checked([str(SEVEN_ZA), "i"])
    banner = info.stdout + info.stderr
    assert b"7-Zip" in banner and b"16.02" in banner, "bin/7za is not the expected p7zip 16.02 extractor."

    # Validate and independently re-extract the supplied multipart archive,
    # then require the agent's extraction to match it exactly.
    run_checked([str(SEVEN_ZA), "t", str(ARCHIVE)])
    expected_dir = tmp_path / "expected_project_logs"
    expected_dir.mkdir()
    run_checked([str(SEVEN_ZA), "x", "-y", f"-o{expected_dir}", str(ARCHIVE)])
    assert tree_manifest(LOGS_DIR) == tree_manifest(expected_dir), (
        "The contents of /home/user/logs do not exactly match the supplied multipart archive."
    )

    # Exercise the built extractor on a fresh unpredictable archive, preventing
    # a fixed response tailored only to project_logs.7z.001.
    fresh_source = tmp_path / "fresh_source"
    fresh_source.mkdir()
    (fresh_source / "alpha.bin").write_bytes(os.urandom(4097))
    nested = fresh_source / ("nested_" + secrets.token_hex(6))
    nested.mkdir()
    (nested / "beta.txt").write_bytes((secrets.token_hex(80) + "\n").encode())
    fresh_archive = tmp_path / ("probe_" + secrets.token_hex(8) + ".7z")
    run_checked([str(SEVEN_ZA), "a", str(fresh_archive), fresh_source.name], cwd=tmp_path)
    run_checked([str(SEVEN_ZA), "t", str(fresh_archive)])
    fresh_out = tmp_path / "fresh_out"
    fresh_out.mkdir()
    run_checked([str(SEVEN_ZA), "x", "-y", f"-o{fresh_out}", str(fresh_archive)])
    assert tree_manifest(fresh_out / fresh_source.name) == tree_manifest(fresh_source)


def run_filter(path):
    result = subprocess.run(
        ["bash", str(SCRIPT), str(path)], capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"filter_records.sh exited with {result.returncode} for {path}: {result.stderr!r}"
    )
    return result.stdout


def expected_records(data):
    output = bytearray()
    current = None
    for line in data.splitlines(keepends=True):
        logical = line[:-1] if line.endswith(b"\n") else line
        if current is None:
            if logical == b"[RECORD_START]":
                current = bytearray(line)
        else:
            current.extend(line)
            if logical == b"[RECORD_END]":
                record = bytes(current)
                if b"\x7fELF" not in record and b"\x89PNG" not in record:
                    output.extend(record)
                current = None
    return bytes(output)


def test_phase2_filter_script(tmp_path):
    # Preserve all original corpus assertions.
    assert SCRIPT.is_file(), f"Script {SCRIPT} does not exist."

    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir) if os.path.isfile(os.path.join(clean_corpus_dir, f))]
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir) if os.path.isfile(os.path.join(evil_corpus_dir, f))]

    clean_failures = []
    for cf in clean_files:
        with open(cf, "rb") as f:
            expected_output = f.read()
        if run_filter(cf) != expected_output:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if run_filter(ef) != b"":
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")
    assert not error_messages, " | ".join(error_messages)

    # Generate unpredictable mixed corpora so behavior cannot be hardcoded to
    # the four inspectable files. These cover multiple records, orphaned text,
    # malformed trailing records, binary magic at varied positions, decoy tags,
    # and a correctly bounded final record without a trailing newline.
    for corpus_index in range(6):
        token = secrets.token_hex(18).encode()
        parts = [b"orphan-" + token + b"\n", b"[RECORD_END]\n"]
        for record_index in range(18):
            body = bytearray()
            body.extend(b"[RECORD_START]\n")
            body.extend(b"id=" + str(record_index).encode() + b"-" + secrets.token_hex(20).encode() + b"\n")
            body.extend(b"prefix [RECORD_START] suffix\n")
            body.extend(b"prefix [RECORD_END] suffix\n")
            kind = (record_index + corpus_index) % 4
            if kind == 1:
                body.extend(b"evil-before-\x7fELF-after\n")
            elif kind == 2:
                body.extend(b"\x89PNG" + secrets.token_hex(9).encode() + b"\n")
            elif kind == 3:
                body.extend(secrets.token_hex(8).encode() + b"\x7fELF\x89PNG\n")
            else:
                body.extend(b"clean=" + secrets.token_hex(30).encode() + b"\n")
            if record_index == 17 and corpus_index % 2 == 0:
                body.extend(b"[RECORD_END]")
            else:
                body.extend(b"[RECORD_END]\n")
            parts.append(bytes(body))
            parts.append(b"outside-" + secrets.token_hex(5).encode() + b"\n")

        # An incomplete record must never be emitted.
        parts.extend([
            b"[RECORD_START]\n",
            b"unterminated-" + secrets.token_hex(15).encode() + b"\n",
        ])
        data = b"".join(parts)
        case = tmp_path / ("case_" + secrets.token_hex(12) + ".log")
        case.write_bytes(data)
        assert run_filter(case) == expected_records(data), f"Incorrect output for generated corpus {corpus_index}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
