#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest


def get_expected_vulnerabilities():
    known_hashes_path = "/home/user/known_hashes.txt"
    system_mock_dir = "/home/user/system_mock"

    if not os.path.isfile(known_hashes_path):
        return []

    known_hashes = {}
    with open(known_hashes_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                file_hash = parts[0]
                file_path = " ".join(parts[1:])
                known_hashes[file_path] = file_hash

    expected_results = []
    for root, _, files in os.walk(system_mock_dir):
        for filename in files:
            filepath = os.path.join(root, filename)
            sha256_hash = hashlib.sha256()
            try:
                with open(filepath, "rb") as f:
                    for byte_block in iter(lambda: f.read(4096), b""):
                        sha256_hash.update(byte_block)
                calculated_hash = sha256_hash.hexdigest()
            except Exception:
                continue

            if filepath not in known_hashes or known_hashes[filepath] != calculated_hash:
                continue

            try:
                mode = os.stat(filepath).st_mode
            except Exception:
                continue

            if mode & stat.S_ISUID:
                expected_results.append({"file": filepath, "vulnerability": "SUID"})
            elif mode & stat.S_IWOTH:
                expected_results.append({"file": filepath, "vulnerability": "World-Writable"})

    expected_results.sort(key=lambda x: x["file"])
    return expected_results


def load_and_validate_log(expected):
    log_path = "/home/user/evasion_log.json"
    assert os.path.isfile(log_path), f"The output file {log_path} does not exist."
    try:
        with open(log_path, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {log_path} does not contain valid JSON.")

    assert isinstance(actual, list), "The JSON output must be an array."
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} vulnerabilities, but found {len(actual)}."
    )
    for i, (item, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."
        assert set(item.keys()) == {"file", "vulnerability"}, (
            f"Item at index {i} must have exactly the keys 'file' and 'vulnerability'."
        )
        assert item["file"] == wanted["file"], (
            f"Expected file path '{wanted['file']}' at index {i}, got '{item['file']}'."
        )
        assert item["vulnerability"] == wanted["vulnerability"], (
            f"Expected vulnerability '{wanted['vulnerability']}' for file "
            f"'{item['file']}', got '{item['vulnerability']}'."
        )
    return actual


def cargo_bin_targets():
    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd="/home/user/payload",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Cargo metadata failed: {result.stderr}"
    metadata = json.loads(result.stdout)
    bins = []
    for package in metadata.get("packages", []):
        manifest = os.path.realpath(package["manifest_path"])
        if not manifest.startswith("/home/user/payload/") and manifest != "/home/user/payload/Cargo.toml":
            continue
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []):
                source = target.get("src_path")
                assert source and source.endswith(".rs") and os.path.isfile(source), (
                    f"Rust source for binary target {target.get('name')} is missing."
                )
                bins.append(target["name"])
    assert bins, "The Cargo project has no Rust binary target."
    return sorted(set(bins))


def test_evasion_log_exists():
    log_path = "/home/user/evasion_log.json"
    assert os.path.isfile(log_path), f"The output file {log_path} does not exist."


def test_evasion_log_contents():
    load_and_validate_log(get_expected_vulnerabilities())


def test_rust_project_exists():
    cargo_toml = "/home/user/payload/Cargo.toml"
    assert os.path.isfile(cargo_toml), (
        "Rust project was not created at /home/user/payload (Cargo.toml missing)."
    )


def test_release_rust_binary_and_dynamic_execution():
    bins = cargo_bin_targets()

    existing = []
    for name in bins:
        path = os.path.join("/home/user/payload/target/release", name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    existing.append(name)
    assert existing, (
        "No compiled release-mode ELF binary was found under "
        "/home/user/payload/target/release."
    )

    build_dir = tempfile.mkdtemp(prefix="payload_release_check_")
    dynamic_dir = os.path.join("/home/user/system_mock", ".verifier_" + uuid.uuid4().hex)
    known_path = "/home/user/known_hashes.txt"
    log_path = "/home/user/evasion_log.json"
    with open(known_path, "rb") as f:
        old_known = f.read()
    with open(log_path, "rb") as f:
        old_log = f.read()

    try:
        build = subprocess.run(
            ["cargo", "build", "--release", "--offline", "--target-dir", build_dir],
            cwd="/home/user/payload",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert build.returncode == 0, f"The Rust project does not build in release mode: {build.stderr}"

        rebuilt = []
        for name in bins:
            path = os.path.join(build_dir, "release", name)
            if os.path.isfile(path) and os.access(path, os.X_OK):
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        rebuilt.append(path)
        assert rebuilt, "Cargo did not produce an executable release binary."

        os.mkdir(dynamic_dir)
        cases = {
            "verified_suid": (os.urandom(31), 0o4755, True, None),
            "verified_world": (os.urandom(37), 0o0666, True, None),
            "verified_both": (os.urandom(41), 0o4777, True, None),
            "verified_normal": (os.urandom(43), 0o0755, True, None),
            "unlisted_vulnerable": (os.urandom(47), 0o4777, False, None),
            "mismatched_vulnerable": (os.urandom(53), 0o4777, True, "0" * 64),
        }

        hash_lines = []
        for filename, (content, mode, listed, forced_hash) in cases.items():
            path = os.path.join(dynamic_dir, filename)
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
            if listed:
                digest = forced_hash or hashlib.sha256(content).hexdigest()
                hash_lines.append(f"{digest}  {path}\n")

        with open(known_path, "w") as f:
            f.writelines(hash_lines)

        expected = get_expected_vulnerabilities()
        assert len(expected) == 3, "Verifier dynamic fixture was not created correctly."

        errors = []
        succeeded = False
        for binary in rebuilt:
            with open(log_path, "w") as f:
                f.write("not valid json\n")
            try:
                run = subprocess.run(
                    [binary],
                    cwd="/home/user/payload",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                if run.returncode != 0:
                    errors.append(f"{binary}: exited {run.returncode}: {run.stderr}")
                    continue
                load_and_validate_log(expected)
                succeeded = True
                break
            except (AssertionError, subprocess.TimeoutExpired) as exc:
                errors.append(f"{binary}: {exc}")

        assert succeeded, "No release Rust binary generated the required dynamic output: " + "; ".join(errors)
    finally:
        shutil.rmtree(dynamic_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
        with open(known_path, "wb") as f:
            f.write(old_known)
        with open(log_path, "wb") as f:
            f.write(old_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
