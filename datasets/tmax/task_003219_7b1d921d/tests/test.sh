#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

CLASSIFIER_PATH = "/home/user/classifier.py"
PROPERTY_TEST_PATH = "/home/user/test_classifier.py"
RUST_PROJECT_DIR = "/home/user/project/fast_path"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"


def run_classifier(filepath):
    return subprocess.run(
        ["python3", CLASSIFIER_PATH, str(filepath)],
        capture_output=True,
        timeout=10,
    )


def architect_accepts(path):
    return (
        not path.startswith("/")
        and ".." not in path
        and ".git" not in path.split("/")
    )


def test_classifier_exists():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script not found at {CLASSIFIER_PATH}"


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_CORPUS_DIR}"

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = run_classifier(filepath)
        if result.returncode != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil payloads bypassed validation (expected exit code 1): {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_CORPUS_DIR}"

    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = run_classifier(filepath)
        if result.returncode != 0:
            modified_files.append(filename)

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean payloads were rejected (expected exit code 0): {', '.join(modified_files)}")


def test_classifier_on_unpredictable_payloads():
    rng = random.SystemRandom()

    def token():
        return secrets.token_hex(rng.randint(4, 12))

    clean_paths = [
        f"{token()}/{token()}.txt",
        f"{token()}/.github/{token()}",
        f"{token()}/{token()}.git",
        f"{token()}/.gitignore",
        token(),
    ]
    assert all(architect_accepts(p) for p in clean_paths)

    evil_paths = [
        f"{token()}/../{token()}",
        f"{token()}..{token()}",
        f"/{token()}/{token()}",
        f"{token()}/.git/{token()}",
        ".git",
    ]
    assert all(not architect_accepts(p) for p in evil_paths)

    payloads = [clean_paths]
    for index, evil in enumerate(evil_paths):
        mixed = [f"{token()}/{token()}" for _ in range(len(evil_paths))]
        mixed[index] = evil
        payloads.append(mixed)

    # Additional randomized combinations prevent solutions tied to a fixed corpus,
    # fixed filename, path position, or payload length.
    candidates = clean_paths + evil_paths
    for _ in range(12):
        payloads.append([rng.choice(candidates) for _ in range(rng.randint(1, 9))])

    with tempfile.TemporaryDirectory(prefix=f"classifier-{secrets.token_hex(8)}-") as tmp:
        for paths in payloads:
            payload_file = Path(tmp) / f"{secrets.token_hex(12)}.json"
            payload_file.write_text(json.dumps({"paths": paths}), encoding="utf-8")
            expected = 0 if all(architect_accepts(path) for path in paths) else 1
            result = run_classifier(payload_file)
            assert result.returncode == expected, (
                f"Classifier returned {result.returncode}, expected {expected}, "
                f"for generated payload {paths!r}. stderr={result.stderr!r}"
            )


def test_rust_utility_compiles():
    manifest = os.path.join(RUST_PROJECT_DIR, "Cargo.toml")
    source = os.path.join(RUST_PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(manifest), f"Rust manifest missing: {manifest}"
    assert os.path.isfile(source), f"Rust source missing: {source}"
    result = subprocess.run(
        ["cargo", "build"],
        cwd=RUST_PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}\n{result.stderr}"


def test_property_based_test_exists_and_runs():
    assert os.path.isfile(PROPERTY_TEST_PATH), f"Property-based test file not found at {PROPERTY_TEST_PATH}"
    source = Path(PROPERTY_TEST_PATH).read_text(encoding="utf-8")
    tree = ast.parse(source, filename=PROPERTY_TEST_PATH)

    has_given = False
    has_text_strategy = False
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            for decorator in node.decorator_list:
                target = decorator.func if isinstance(decorator, ast.Call) else decorator
                if (
                    isinstance(target, ast.Name) and target.id == "given"
                ) or (
                    isinstance(target, ast.Attribute) and target.attr == "given"
                ):
                    has_given = True
        if isinstance(node, ast.Call):
            if (
                isinstance(node.func, ast.Name) and node.func.id == "text"
            ) or (
                isinstance(node.func, ast.Attribute) and node.func.attr == "text"
            ):
                has_text_strategy = True

    assert has_given, "test_classifier.py must contain a Hypothesis @given property test"
    assert has_text_strategy, "test_classifier.py must generate arbitrary strings with a Hypothesis text strategy"

    result = subprocess.run(
        ["python3", "-m", "pytest", PROPERTY_TEST_PATH, "-q", "--tb=short"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Property-based tests failed:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
