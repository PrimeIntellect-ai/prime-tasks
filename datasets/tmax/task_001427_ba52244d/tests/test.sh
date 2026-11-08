#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
MANIFEST = "/home/user/pza_tool/Cargo.toml"
PREFIX = "OMEGA_99"


def run_tool(pza_path, output_dir):
    cmd = [
        "cargo", "run",
        "--manifest-path", MANIFEST,
        "--",
        pza_path,
        output_dir,
        PREFIX,
    ]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120)


def write_pza(path, entries):
    with open(path, "wb") as f:
        f.write(b"PZA\x01")
        f.write(struct.pack("<I", len(entries)))
        for archive_path, payload in entries:
            encoded = archive_path.encode("utf-8")
            f.write(struct.pack("<H", len(encoded)))
            f.write(encoded)
            f.write(struct.pack("<I", len(payload)))
            f.write(payload)


def output_files(root):
    found = []
    for current, dirs, files in os.walk(root):
        for name in files:
            found.append(Path(current) / name)
        for name in dirs:
            candidate = Path(current) / name
            if candidate.is_symlink():
                found.append(candidate)
    return found


def test_evil_corpus_rejected():
    assert os.path.exists(MANIFEST), f"Rust project manifest not found at {MANIFEST}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.pza')]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed = []

    for evil_file in evil_files:
        pza_path = os.path.join(EVIL_CORPUS, evil_file)
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_tool(pza_path, tmpdir)
            if result.returncode != 1:
                bypassed.append((evil_file, result.returncode, result.stderr))

    if bypassed:
        details = "\n".join([f"{f}: exit code {c}" for f, c, e in bypassed])
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed:\n{details}")


def test_clean_corpus_accepted():
    assert os.path.exists(MANIFEST), f"Rust project manifest not found at {MANIFEST}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.pza')]
    assert len(clean_files) > 0, "No files found in clean corpus."

    failed = []

    for clean_file in clean_files:
        pza_path = os.path.join(CLEAN_CORPUS, clean_file)
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_tool(pza_path, tmpdir)
            if result.returncode != 0:
                failed.append((clean_file, result.returncode, result.stderr))
            else:
                extracted = []
                for root, dirs, files in os.walk(tmpdir):
                    for file in files:
                        extracted.append(file)

                if not extracted:
                    failed.append((clean_file, "No files extracted", ""))
                else:
                    for f in extracted:
                        if not f.startswith(f"{PREFIX}_"):
                            failed.append((clean_file, f"File {f} missing prefix {PREFIX}_", ""))
                            break

    if failed:
        details = "\n".join([f"{f}: {c} - {e}" for f, c, e in failed])
        pytest.fail(f"{len(failed)} of {len(clean_files)} clean modified or failed:\n{details}")


def test_generated_clean_archive_exact_extraction():
    assert os.path.isfile(MANIFEST), f"Rust project manifest not found at {MANIFEST}"
    token = uuid.uuid4().hex
    entries = [
        (f"src/{token}.rs", os.urandom(41)),
        (f"docs/guides/readme_{token}.txt", ("generated-" + token).encode()),
        (f"assets/blob_{token}.bin", b"\x00\xffPZA\x01\x00payload" + os.urandom(19)),
        (f"empty_{token}.dat", b""),
    ]

    with tempfile.TemporaryDirectory() as case_dir:
        archive = Path(case_dir) / f"generated_{uuid.uuid4().hex}.pza"
        output = Path(case_dir) / "output"
        output.mkdir()
        write_pza(archive, entries)

        result = run_tool(str(archive), str(output))
        assert result.returncode == 0, result.stderr

        expected = {}
        for archive_path, payload in entries:
            source = Path(archive_path)
            destination = source.parent / f"{PREFIX}_{source.name}"
            expected[destination.as_posix()] = payload

        actual_paths = output_files(output)
        actual = {}
        for path in actual_paths:
            assert not path.is_symlink(), f"Extracted path is a symlink: {path}"
            assert path.is_file(), f"Extracted path is not a regular file: {path}"
            relative = path.relative_to(output).as_posix()
            actual[relative] = path.read_bytes()

        assert set(actual) == set(expected), (
            f"Wrong extracted paths. Expected {sorted(expected)}, got {sorted(actual)}"
        )
        for relative, payload in expected.items():
            assert actual[relative] == payload, f"Wrong payload for {relative}"


def test_generated_malicious_archives_are_transactionally_rejected():
    assert os.path.isfile(MANIFEST), f"Rust project manifest not found at {MANIFEST}"
    token = uuid.uuid4().hex

    with tempfile.TemporaryDirectory() as root_dir:
        root = Path(root_dir)
        absolute_target = root / f"absolute_{token}.txt"
        cases = [
            [
                (f"safe/first_{token}.txt", b"must never be written"),
                (f"../escaped_{token}.txt", b"traversal"),
            ],
            [(str(absolute_target), b"absolute")],
            [(f"nested/../../escaped_{token}.bin", b"nested traversal")],
            [(f"folder\\..\\..\\escaped_{token}.dat", b"backslash traversal")],
        ]

        for index, entries in enumerate(cases):
            case = root / f"case_{index}_{uuid.uuid4().hex}"
            case.mkdir()
            output = case / "output"
            output.mkdir()
            archive = case / f"input_{uuid.uuid4().hex}.pza"
            write_pza(archive, entries)
            archive_bytes = archive.read_bytes()

            before_outside = {
                p.relative_to(case).as_posix()
                for p in case.rglob("*")
                if p.is_file() or p.is_symlink()
            }
            result = run_tool(str(archive), str(output))

            assert result.returncode == 1, (
                f"Malicious archive case {index} returned {result.returncode}: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stderr.strip(), "Malicious archive rejection must print an error to stderr"
            assert output_files(output) == [], (
                f"Malicious archive case {index} wrote files before rejecting"
            )
            assert archive.read_bytes() == archive_bytes, "Tool modified its input archive"

            after_outside = {
                p.relative_to(case).as_posix()
                for p in case.rglob("*")
                if p.is_file() or p.is_symlink()
            }
            assert after_outside == before_outside, (
                f"Malicious archive case {index} wrote outside output: "
                f"{sorted(after_outside - before_outside)}"
            )
            assert not absolute_target.exists(), "Absolute-path payload was written"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
