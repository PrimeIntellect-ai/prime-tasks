#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest

CLEAN_CORPUS_DIR = "/app/clean_corpus"
EVIL_CORPUS_DIR = "/app/evil_corpus"
PROJECT_DIR = "/home/user/seq_filter"
EXECUTABLE_PATH = "/home/user/seq_filter/target/release/seq_filter"
LAB_NOTES = "/app/lab_notes.png"


def read_threshold():
    result = subprocess.run(
        ["tesseract", LAB_NOTES, "stdout"],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    match = re.search(r"GC_MAX_THRESHOLD\s*=\s*([01](?:\.\d+)?)", result.stdout, re.IGNORECASE)
    assert match, f"Could not OCR GC_MAX_THRESHOLD from lab notes. OCR output: {result.stdout!r}"
    threshold = float(match.group(1))
    assert 0.0 <= threshold <= 1.0
    return threshold


THRESHOLD = read_threshold()


def run_classifier(path):
    return subprocess.run(
        [EXECUTABLE_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}. Did you build the Rust project in release mode?"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable."


def test_rust_project_builds_and_uses_rayon():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(manifest), f"Rust manifest not found at {manifest}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    project_packages = [
        package for package in metadata.get("packages", [])
        if os.path.realpath(package["manifest_path"]) == os.path.realpath(manifest)
    ]
    assert project_packages, "Cargo metadata did not contain the submitted project"
    assert any(
        dependency.get("name") == "rayon"
        for package in project_packages
        for dependency in package.get("dependencies", [])
    ), "The Rust project must depend on the rayon crate"

    rust_sources = glob.glob(os.path.join(PROJECT_DIR, "src", "**", "*.rs"), recursive=True)
    assert rust_sources, "No Rust source files found under src/"
    source = "\n".join(open(path, encoding="utf-8").read() for path in rust_sources)
    assert re.search(r"(?:use\s+rayon|rayon::)", source), "Rust source does not import or reference rayon"
    assert re.search(r"(?:par_iter|par_chunks|into_par_iter|par_bridge|rayon::(?:join|scope))", source), \
        "Rust source does not use a Rayon parallel-processing API"

    build_result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build_result.returncode == 0, f"Release build failed:\n{build_result.stdout}\n{build_result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.fasta"))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.fasta"))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(failed_files)}")


def make_fasta(path, gc_count, total_count, rng):
    bases = [rng.choice("GC") for _ in range(gc_count)]
    bases.extend(rng.choice("AT") for _ in range(total_count - gc_count))
    rng.shuffle(bases)
    bases = [base.lower() if rng.randrange(2) else base for base in bases]

    split = rng.randrange(1, len(bases)) if len(bases) > 1 else len(bases)
    records = [bases[:split], bases[split:]]
    with open(path, "w", encoding="ascii") as handle:
        for index, record in enumerate(records):
            if not record:
                continue
            # Header text deliberately contains DNA letters and must not be counted.
            handle.write(f">random_GCGC_header_{index}_{uuid.uuid4().hex}\n")
            position = 0
            while position < len(record):
                width = rng.randint(1, 31)
                handle.write("".join(record[position:position + width]) + "\n")
                if rng.randrange(4) == 0:
                    handle.write("   \n")
                position += width


def test_randomized_hidden_fastas():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = []

    # Include exact boundary-adjacent cases as well as independently randomized ratios.
    for total in (20, 37, 100, 257, 509):
        boundary = int(THRESHOLD * total)
        for gc_count in {max(0, boundary - 1), boundary, min(total, boundary + 1), min(total, boundary + 2)}:
            cases.append((gc_count, total))

    for _ in range(40):
        total = rng.randint(8, 1200)
        cases.append((rng.randint(0, total), total))

    assert any(gc / total <= THRESHOLD for gc, total in cases)
    assert any(gc / total > THRESHOLD for gc, total in cases)

    with tempfile.TemporaryDirectory(prefix="seq_filter_hidden_") as directory:
        failures = []
        for gc_count, total in cases:
            path = os.path.join(directory, f"{uuid.uuid4().hex}.fa")
            make_fasta(path, gc_count, total, rng)
            expected = 1 if gc_count / total > THRESHOLD else 0
            actual = run_classifier(path)
            if actual != expected:
                failures.append((gc_count, total, expected, actual))

        assert not failures, f"Classifier failed randomized GC-content cases: {failures[:10]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
