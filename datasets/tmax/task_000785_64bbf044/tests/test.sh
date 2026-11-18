#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def compute_rle(text: bytes) -> bytes:
    if not text:
        return b""

    result = bytearray()
    i = 0
    n = len(text)

    while i < n:
        char = text[i]
        count = 1
        while i + count < n and text[i + count] == char and count < 255:
            count += 1

        if count >= 4:
            result.append(0x1B)
            result.append(char)
            result.append(count)
            i += count
        else:
            result.append(char)
            i += 1

    return bytes(result)


def test_processed_directory_exists():
    assert os.path.isdir("/home/user/docs_processed"), "/home/user/docs_processed directory is missing"


def test_rle_files_content():
    expected_texts = {
        "file1.rle": b"abbbbccc",
        "file2.rle": b"Helloooooo Universe",
        "file3.rle": b"A" * 256
    }

    for filename, raw_text in expected_texts.items():
        filepath = os.path.join("/home/user/docs_processed", filename)
        assert os.path.isfile(filepath), f"Expected processed file {filepath} is missing"

        expected_rle = compute_rle(raw_text)
        with open(filepath, "rb") as f:
            actual_rle = f.read()

        assert actual_rle == expected_rle, f"Content mismatch in {filename}. Expected hex: {expected_rle.hex()}, got: {actual_rle.hex()}"


def test_manifest_file():
    manifest_path = "/home/user/docs_processed/manifest.txt"
    assert os.path.isfile(manifest_path), "manifest.txt is missing"

    expected_texts = {
        "file1.rle": b"abbbbccc",
        "file2.rle": b"Helloooooo Universe",
        "file3.rle": b"A" * 256
    }

    expected_hashes = {}
    for filename, raw_text in expected_texts.items():
        expected_rle = compute_rle(raw_text)
        expected_hashes[filename] = hashlib.sha256(expected_rle).hexdigest()

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in manifest.txt, got {len(lines)}"

    filenames_in_manifest = [line.split()[1] for line in lines if len(line.split()) >= 2]
    assert filenames_in_manifest == sorted(filenames_in_manifest), "Manifest entries are not sorted alphabetically by filename"

    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        file_hash, filename = parts

        assert "/" not in filename, f"Manifest should only contain base filenames, found: {filename}"
        assert filename in expected_hashes, f"Unexpected filename in manifest: {filename}"
        assert file_hash == expected_hashes[filename], f"Hash mismatch for {filename} in manifest"


def make_wal(path: Path, operations, garbage=b""):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(b"DOCW")
        for opcode, value in operations:
            if opcode == 0x01:
                encoded = bytes(b ^ 0xAA for b in value)
                f.write(struct.pack("<BH", opcode, len(encoded)))
                f.write(encoded)
            elif opcode == 0x02:
                f.write(struct.pack("<BH", opcode, value))
            elif opcode == 0xFF:
                f.write(b"\xff")
        f.write(garbage)


def output_matches(processed: Path, expected):
    if not processed.is_dir():
        return False
    rle_files = sorted(p.name for p in processed.glob("*.rle") if p.is_file())
    if rle_files != sorted(expected):
        return False
    for name, raw in expected.items():
        if (processed / name).read_bytes() != compute_rle(raw):
            return False

    manifest = processed / "manifest.txt"
    if not manifest.is_file():
        return False
    wanted = [
        f"{hashlib.sha256(compute_rle(expected[name])).hexdigest()}  {name}"
        for name in sorted(expected)
    ]
    return manifest.read_text().splitlines() == wanted


def test_z_dynamic_c_parser_and_bash_workflow():
    home = Path("/home/user")
    raw = home / "docs_raw"
    processed = home / "docs_processed"

    def outside_data_dirs(p: Path):
        return not (p == raw or raw in p.parents or p == processed or processed in p.parents)

    c_sources = [p for p in home.rglob("*.c") if p.is_file() and outside_data_dirs(p)]
    assert c_sources, "No C parser source file was written"

    scripts = []
    for p in home.rglob("*"):
        if not p.is_file() or not outside_data_dirs(p):
            continue
        try:
            first = p.open("rb").readline(256)
        except OSError:
            continue
        if p.suffix in (".sh", ".bash") or (first.startswith(b"#!") and b"bash" in first):
            scripts.append(p)
    assert scripts, "No bash processing script was written"

    existing_elfs = []
    for p in home.rglob("*"):
        if not p.is_file() or not outside_data_dirs(p):
            continue
        try:
            if p.open("rb").read(4) == b"\x7fELF" and (p.stat().st_mode & 0o111):
                existing_elfs.append(p)
        except OSError:
            pass
    assert existing_elfs, "No compiled C executable was found"

    token = uuid.uuid4().hex[:12].encode("ascii")
    names = [f"dyn_{uuid.uuid4().hex[:10]}_{i}" for i in range(4)]
    expected = {
        names[0] + ".rle": b"pre-" + token + b"-" + b"Q" * 4 + b"xyz",
        names[1] + ".rle": b"start-" + token + b"-replacement",
        names[2] + ".rle": b"R" * 600 + token,
        names[3] + ".rle": b"a" + b"b" * 3 + b"c" * 4 + token + b"z" * 5,
    }

    with tempfile.TemporaryDirectory(prefix="wal_verify_") as td:
        td = Path(td)
        fixture = td / "raw"
        make_wal(fixture / "one" / (names[0] + ".wal"), [
            (0x01, b"pre-" + token + b"-" + b"Q" * 4 + b"xyz"),
            (0xFF, None),
        ], b"\x01\x08\x00THIS_IS_TRAILING_GARBAGE")
        make_wal(fixture / "deep" / "two" / (names[1] + ".wal"), [
            (0x01, b"start-" + token + b"-remove-this"),
            (0x02, len(b"remove-this")),
            (0x01, b"replacement"),
            (0xFF, None),
        ], b"ignored-after-commit")
        make_wal(fixture / (names[2] + ".wal"), [
            (0x01, b"R" * 600),
            (0x01, token),
            (0xFF, None),
        ], b"\xff\x00\x01garbage")
        make_wal(fixture / "other" / (names[3] + ".wal"), [
            (0x01, expected[names[3] + ".rle"]),
            (0xFF, None),
        ])

        wal_inputs = sorted(fixture.rglob("*.wal"))

        compiled = []
        compile_sets = [[src] for src in c_sources]
        if len(c_sources) > 1:
            compile_sets.append(c_sources)
        for idx, sources in enumerate(compile_sets):
            binary = td / f"compiled_candidate_{idx}"
            try:
                result = subprocess.run(
                    ["gcc", "-std=c11", "-O2", *map(str, sources), "-o", str(binary)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
                )
                if result.returncode == 0:
                    compiled.append(binary)
            except (OSError, subprocess.TimeoutExpired):
                pass
        assert compiled, "The submitted C source could not be compiled with gcc"

        def parser_passes(binary: Path):
            outdir = td / ("parser_" + uuid.uuid4().hex)
            outdir.mkdir()
            for wal in wal_inputs:
                out = outdir / (wal.stem + ".rle")
                try:
                    result = subprocess.run(
                        [str(binary), str(wal), str(out)],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
                    )
                except (OSError, subprocess.TimeoutExpired):
                    return False
                if result.returncode != 0 or not out.is_file():
                    return False
                if out.read_bytes() != compute_rle(expected[out.name]):
                    return False
            return True

        assert any(parser_passes(p) for p in compiled), "Compiled submitted C source does not correctly parse dynamic WAL inputs"
        assert any(parser_passes(p) for p in existing_elfs), "No submitted compiled executable correctly parses dynamic WAL inputs"

        raw_backup = home / ("docs_raw.verifier_backup." + uuid.uuid4().hex)
        processed_backup = home / ("docs_processed.verifier_backup." + uuid.uuid4().hex)
        os.rename(raw, raw_backup)
        os.rename(processed, processed_backup)
        try:
            workflow_ok = False
            for script in scripts:
                for cwd in dict.fromkeys((script.parent, home)):
                    if raw.exists():
                        shutil.rmtree(raw)
                    if processed.exists():
                        shutil.rmtree(processed)
                    shutil.copytree(fixture, raw)
                    try:
                        result = subprocess.run(
                            ["bash", str(script)], cwd=str(cwd),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
                        )
                    except (OSError, subprocess.TimeoutExpired):
                        continue
                    if result.returncode == 0 and output_matches(processed, expected):
                        workflow_ok = True
                        break
                if workflow_ok:
                    break
            assert workflow_ok, "No submitted bash script correctly processed the dynamic recursive WAL set and generated the sorted manifest"
        finally:
            if raw.exists():
                shutil.rmtree(raw)
            if processed.exists():
                shutil.rmtree(processed)
            os.rename(raw_backup, raw)
            os.rename(processed_backup, processed)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
