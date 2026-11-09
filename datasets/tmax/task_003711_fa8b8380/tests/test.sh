#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import gzip
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/validator"
SOURCE = "/home/user/validator.cpp"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
REBUILT = "/tmp/validator_rebuilt"


def run_validator(executable, manifest):
    try:
        return subprocess.run(
            [executable, manifest], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out while validating {manifest}")


def test_executable_exists_and_is_runnable():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you compile your C++ code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The validator must be a compiled executable."


def test_cpp_source_exists_and_compiles():
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-lz", "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"validator.cpp does not compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_adversarial_corpus_validation():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json.gz"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json.gz"))

    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    clean_rejected = []
    for clean_file in clean_files:
        result = subprocess.run([EXECUTABLE, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([EXECUTABLE, evil_file], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def policy_accepts(manifest):
    return (
        "author" in manifest
        and "build_id" in manifest
        and manifest.get("total_uncompressed_bytes") < 50000000
        and isinstance(manifest.get("chunks"), list)
        and len(manifest["chunks"]) == 3
        and manifest.get("compression_format") == "gzip"
    )


def test_randomized_hidden_manifests():
    rng = random.SystemRandom()
    token = secrets.token_hex(8)
    base = {
        "artifact_name": "artifact_" + token,
        "author": "team_" + secrets.token_hex(5),
        "build_id": "build_" + secrets.token_hex(6),
        "compression_format": "gzip",
        "total_uncompressed_bytes": rng.randint(1, 49999998),
        "chunks": [
            {"part": i + 1, "size": rng.randint(1, 20000000)}
            for i in range(3)
        ],
    }

    cases = []
    cases.append(copy.deepcopy(base))

    boundary_valid = copy.deepcopy(base)
    boundary_valid["total_uncompressed_bytes"] = 49999999
    cases.append(boundary_valid)

    for missing in ("author", "build_id"):
        item = copy.deepcopy(base)
        del item[missing]
        cases.append(item)

    for size in (50000000, 50000001, rng.randint(50000002, 90000000)):
        item = copy.deepcopy(base)
        item["total_uncompressed_bytes"] = size
        cases.append(item)

    for count in (0, 1, 2, 4, 5):
        item = copy.deepcopy(base)
        item["chunks"] = [
            {"part": i + 1, "size": rng.randint(1, 1000000)}
            for i in range(count)
        ]
        cases.append(item)

    for fmt in ("bzip2", "GZIP", "gzip ", "zstd", ""):
        item = copy.deepcopy(base)
        item["compression_format"] = fmt
        cases.append(item)

    combined = copy.deepcopy(base)
    del combined["build_id"]
    combined["chunks"] = [{"part": 1, "size": 1}]
    combined["compression_format"] = "zstd"
    combined["total_uncompressed_bytes"] = 70000000
    cases.append(combined)

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="manifest_checks_") as directory:
        written = []
        for index, manifest in enumerate(cases):
            path = os.path.join(
                directory,
                f"{secrets.token_hex(10)}_{rng.randrange(1000000)}.json.gz",
            )
            items = list(manifest.items())
            rng.shuffle(items)
            with gzip.open(path, "wt", encoding="utf-8") as stream:
                json.dump(dict(items), stream, separators=(",", ":"))
            written.append((path, policy_accepts(manifest)))

        for executable in (EXECUTABLE, REBUILT):
            for path, should_accept in written:
                code = run_validator(executable, path)
                expected = 0 if should_accept else 1
                assert code == expected, (
                    f"{executable} returned {code} for a manifest that should "
                    f"{'be accepted' if should_accept else 'be rejected with exit code 1'}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
