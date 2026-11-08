#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import uuid

import pytest

EXECUTABLE = "/home/user/dataset_scanner"
SOURCE = "/home/user/dataset_scanner.c"
VENDORED = "/app/vendored/microtar-0.1.0"
LIBRARY = os.path.join(VENDORED, "libmicrotar.a")
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_checked(command, **kwargs):
    return subprocess.run(
        command, check=True, capture_output=True, text=True, timeout=30, **kwargs
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "dataset_scanner must be a compiled executable"


def test_microtar_build_and_c_source(tmp_path):
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    source_text = open(SOURCE, encoding="utf-8", errors="replace").read()
    assert re.search(r"^\s*#\s*include\s*[<\"]microtar\.h[>\"]", source_text, re.M), \
        "dataset_scanner.c must include microtar.h"
    assert re.search(r"\bmtar_open\s*\(", source_text), "scanner must use microtar"
    assert re.search(r"\bmtar_read_header\s*\(", source_text), \
        "scanner must iterate archive headers with microtar"

    assert os.path.isfile(LIBRARY), "libmicrotar.a was not produced in the vendored package"
    members = run_checked(["ar", "t", LIBRARY]).stdout.splitlines()
    assert members, "libmicrotar.a is empty"
    symbols = run_checked(["nm", "-g", LIBRARY]).stdout
    assert re.search(r"\bmtar_open\b", symbols), "libmicrotar.a lacks microtar symbols"
    assert re.search(r"\bmtar_read_header\b", symbols), "libmicrotar.a lacks header-reading support"

    # Verify the repaired package builds from a clean copy rather than relying on stale objects.
    build_dir = tmp_path / "microtar-build"
    shutil.copytree(VENDORED, build_dir)
    for pattern in ("*.o", "*.a"):
        for artifact in build_dir.glob(pattern):
            artifact.unlink()
    run_checked(["make", "-B"], cwd=build_dir)
    rebuilt_library = build_dir / "libmicrotar.a"
    assert rebuilt_library.is_file(), "The repaired Makefile did not build libmicrotar.a"
    assert run_checked(["ar", "t", str(rebuilt_library)]).stdout.splitlines()

    # Rebuild the submitted C source against the submitted static library.
    rebuilt_scanner = tmp_path / "dataset_scanner_rebuilt"
    run_checked([
        "gcc", "-std=c99", "-I", VENDORED, SOURCE, LIBRARY,
        "-o", str(rebuilt_scanner)
    ])
    assert rebuilt_scanner.is_file()


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.tar"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.tar"))

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        result = subprocess.run([EXECUTABLE, cf], capture_output=True, text=True)
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([EXECUTABLE, ef], capture_output=True, text=True)
        if result.returncode != 1 or "MALICIOUS" not in result.stdout:
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def make_tar(path, member_names):
    with tarfile.open(path, "w") as archive:
        for name in member_names:
            info = tarfile.TarInfo(name)
            info.size = 0
            archive.addfile(info)


def assert_classification(scanner, archive, malicious):
    result = subprocess.run(
        [str(scanner), str(archive)], capture_output=True, text=True, timeout=10
    )
    expected_output = "MALICIOUS" if malicious else "CLEAN"
    expected_status = 1 if malicious else 0
    assert result.returncode == expected_status, \
        f"{archive.name}: expected status {expected_status}, got {result.returncode}"
    assert result.stdout.strip() == expected_output, \
        f"{archive.name}: expected {expected_output!r}, got {result.stdout!r}"


def test_generated_archives_are_parsed(tmp_path):
    # All archives use unpredictable names in one neutral directory, so their paths
    # reveal neither their classification nor which attack they contain.
    cases = [
        (["data/table.csv", "images/a.png", "notes/..safe.txt"], False),
        (["ordinary/first.txt", "../outside.txt"], True),
        (["ordinary/first.txt", r"..\outside.txt"], True),
        (["ordinary/first.txt", "/absolute/secret.txt"], True),
        (["data/ok.txt", "data/../../outside.txt", "later/file.txt"], True),
        (["alpha/file.txt", r"windows\normal\file.txt"], False),
    ]
    secrets.SystemRandom().shuffle(cases)

    generated = []
    for members, malicious in cases:
        archive = tmp_path / (uuid.uuid4().hex + ".tar")
        make_tar(archive, members)
        generated.append((archive, malicious))

    rebuilt_scanner = tmp_path / "scanner_from_source"
    run_checked([
        "gcc", "-std=c99", "-I", VENDORED, SOURCE, LIBRARY,
        "-o", str(rebuilt_scanner)
    ])

    for scanner in (EXECUTABLE, rebuilt_scanner):
        order = generated[:]
        secrets.SystemRandom().shuffle(order)
        for archive, malicious in order:
            assert_classification(scanner, archive, malicious)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
