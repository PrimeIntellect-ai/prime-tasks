#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import string
import subprocess
import tempfile

import pytest

VENDORED_MANIFEST = "/app/vendored/log-parser-1.0.0/Cargo.toml"
VENDORED_LIB = "/app/vendored/log-parser-1.0.0/src/lib.rs"
DETECTOR_MANIFEST = "/home/user/detector/Cargo.toml"
BINARY = "/home/user/detector/target/release/detector"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=180, **kwargs)


def build_detector(clean=True):
    if clean:
        cleaned = run(["cargo", "clean", "--manifest-path", DETECTOR_MANIFEST])
        assert cleaned.returncode == 0, cleaned.stdout + cleaned.stderr
    built = run(["cargo", "build", "--release", "--manifest-path", DETECTOR_MANIFEST])
    assert built.returncode == 0, built.stdout + built.stderr


def classify(contents):
    with tempfile.TemporaryDirectory(prefix="detector-hidden-") as directory:
        path = os.path.join(directory, secrets.token_hex(12) + ".log")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(contents)
        return subprocess.run([BINARY, path], capture_output=True, timeout=10).returncode


def test_vendored_package_fixed():
    cargo_toml = VENDORED_MANIFEST
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found at {cargo_toml}."

    with open(cargo_toml, "r") as f:
        content = f.read()
        assert "[dependencies]" in content, "Cargo.toml does not contain the fixed '[dependencies]' section."
        assert "[dependecies]" not in content, "Cargo.toml still contains the typo '[dependecies]'."

    built = run(["cargo", "build", "--release", "--manifest-path", cargo_toml])
    assert built.returncode == 0, "The fixed vendored crate does not build:\n" + built.stdout + built.stderr


def test_detector_binary_exists():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Detector binary not found at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"Detector binary at {binary_path} is not executable."


def test_detector_builds_and_uses_local_dependency():
    assert os.path.isfile(DETECTOR_MANIFEST), f"Detector manifest not found at {DETECTOR_MANIFEST}."
    build_detector(clean=True)

    assert os.path.isfile(BINARY)
    assert os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Cargo did not produce an ELF detector binary."

    result = run(["cargo", "metadata", "--format-version", "1", "--manifest-path", DETECTOR_MANIFEST])
    assert result.returncode == 0, result.stdout + result.stderr
    metadata = json.loads(result.stdout)
    expected_manifest = os.path.realpath(VENDORED_MANIFEST)
    package_by_id = {package["id"]: package for package in metadata["packages"]}
    root = metadata.get("resolve", {}).get("root")
    assert root, "Detector Cargo metadata has no root package."
    root_node = next(node for node in metadata["resolve"]["nodes"] if node["id"] == root)
    dependency_packages = [package_by_id[dep["pkg"]] for dep in root_node["deps"]]
    assert any(
        package["name"] == "log-parser"
        and os.path.realpath(package["manifest_path"]) == expected_manifest
        for package in dependency_packages
    ), "Detector does not resolve log-parser from the required local vendored path."


def test_adversarial_corpus():
    binary_path = BINARY
    evil_dir = "/app/data/evil"
    clean_dir = "/app/data/clean"

    assert os.path.isdir(evil_dir), f"Evil data directory {evil_dir} does not exist."
    assert os.path.isdir(clean_dir), f"Clean data directory {clean_dir} does not exist."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        result = subprocess.run([binary_path, file_path], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(f)

    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        result = subprocess.run([binary_path, file_path], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(f)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_messages, " | ".join(error_messages)


def test_randomized_hidden_inputs():
    alphabet = string.ascii_letters + string.digits + "_-"
    value = "".join(secrets.choice(alphabet) for _ in range(random.randint(8, 30)))

    def mixed_case(text):
        return "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in text)

    evil_inputs = [
        f"unrelated-{secrets.token_hex(5)} password={value}",
        f"run --mode=test --password={value}",
        f"GET /?q={mixed_case('<script>')}alert({random.randint(10, 9999)})</ScRiPt>",
        f"redirect={mixed_case('javascript:')}alert('{secrets.token_hex(4)}')",
        f"image=<img src=x {mixed_case('onerror=')}alert({random.randint(10, 9999)})>",
    ]
    clean_inputs = [
        f"ordinary message {secrets.token_hex(16)}",
        "password= --password=",
        f"password_hash={value} --password_hash={value}",
        f"xpassword={value} --xpassword={value}",
        f"PASSWORD={value} password word only",
        "GET /index.html?search=script javascript and onerror",
    ]

    for contents in evil_inputs:
        assert classify(contents) == 1, f"Hidden evil input was not flagged: {contents!r}"
    for contents in clean_inputs:
        assert classify(contents) == 0, f"Hidden clean input was incorrectly flagged: {contents!r}"


def test_detector_consumes_tokens_from_log_parser():
    assert os.path.isfile(VENDORED_LIB), f"Vendored library source not found at {VENDORED_LIB}."
    with open(VENDORED_LIB, "rb") as handle:
        original = handle.read()

    instrumented = b'''pub fn parse_log(_input: &str) -> Vec<String> {\n    vec!["<script>".to_string()]\n}\n'''
    observed_returncode = None
    try:
        with open(VENDORED_LIB, "wb") as handle:
            handle.write(instrumented)
        build_detector(clean=True)
        observed_returncode = classify("entirely benign randomized text " + secrets.token_hex(16))
    finally:
        with open(VENDORED_LIB, "wb") as handle:
            handle.write(original)
        build_detector(clean=True)

    assert observed_returncode == 1, "Detector output is unaffected by tokens returned from log_parser::parse_log."


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
