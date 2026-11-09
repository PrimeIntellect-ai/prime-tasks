#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_artifact_parser.py
import hashlib
import json
import os
import secrets
import shutil
import subprocess

PROJECT = "/home/user/artifact_parser"
MANIFEST = "/home/user/final_manifest.json"
LOG = "/home/user/corrupt_manifest.log"


def get_sha256(path):
    """Compute SHA-256 checksum of a file."""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run(cmd, timeout=240):
    completed = subprocess.run(
        cmd,
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"Command failed with exit code {completed.returncode}: {' '.join(cmd)}\n"
            f"{completed.stdout}"
        )
    return completed.stdout


def validate_rust_project():
    assert os.path.isdir(PROJECT), f"Rust project {PROJECT} does not exist."
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Missing {cargo_toml}."

    output = run([
        "cargo", "metadata", "--no-deps", "--format-version", "1",
        "--manifest-path", cargo_toml,
    ])
    metadata = json.loads(output)
    bin_targets = [
        target
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
    ]
    assert bin_targets, "The Cargo project has no Rust binary target."
    for target in bin_targets:
        src_path = target.get("src_path", "")
        assert src_path.endswith(".rs") and os.path.isfile(src_path), (
            f"Binary target {target.get('name')} does not have a valid Rust source file."
        )

    # Force the submitted Rust utility to be compiled from the project sources.
    run(["cargo", "clean", "--manifest-path", cargo_toml])
    run(["cargo", "build", "--release", "--manifest-path", cargo_toml])


def run_utility():
    run([
        "cargo", "run", "--release", "--quiet",
        "--manifest-path", os.path.join(PROJECT, "Cargo.toml"),
    ])


def load_manifest():
    assert os.path.exists(MANIFEST), (
        f"Output file {MANIFEST} does not exist. Did your Rust program generate it?"
    )
    with open(MANIFEST, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"{MANIFEST} is not valid JSON."


def test_final_manifest_exists_and_valid():
    data = load_manifest()

    assert isinstance(data, list), "Manifest should be a JSON array."
    assert len(data) == 3, (
        f"Expected exactly 3 valid entries in the manifest, but found {len(data)}."
    )

    # Check that the list is sorted by ID ascending
    ids = [item.get("id") for item in data]
    assert all(isinstance(x, int) for x in ids), "All IDs should be integers."
    assert ids == sorted(ids), "The JSON array is not sorted by ID in ascending order."

    # Define the expected valid resolutions based on the corrupt manifest
    expected_entries = {
        8: "/home/user/artifacts/standard/beta.bin",
        45: "/home/user/artifacts/loop/alpha.bin",
        102: "/home/user/artifacts/standard/gamma.bin",
    }

    actual_entries = {item.get("id"): item for item in data}

    # Verify each expected entry
    for expected_id, expected_path in expected_entries.items():
        assert expected_id in actual_entries, (
            f"Missing ID {expected_id} in final manifest. It should have been resolved and kept."
        )
        item = actual_entries[expected_id]

        actual_path = item.get("canonical_path")
        assert actual_path == expected_path, (
            f"Incorrect canonical path for ID {expected_id}. "
            f"Expected {expected_path}, got {actual_path}."
        )

        expected_sha = get_sha256(expected_path)
        actual_sha = item.get("sha256")
        assert actual_sha == expected_sha, (
            f"Incorrect SHA256 for ID {expected_id}. Expected {expected_sha}, got {actual_sha}."
        )

    # Verify that no unexpected IDs are present
    unexpected_ids = set(actual_entries.keys()) - set(expected_entries.keys())
    assert not unexpected_ids, (
        f"Found unexpected IDs in the manifest: {unexpected_ids}. Ensure unverified or "
        "missing files are ignored, and duplicates are correctly overwritten by higher IDs."
    )


def test_dynamic_manifest(base_dir, base_id):
    data = load_manifest()
    assert isinstance(data, list), "Manifest should be a JSON array."

    expected_entries = {
        base_id + 5: os.path.realpath(os.path.join(base_dir, "third.bin")),
        base_id + 17: os.path.realpath(os.path.join(base_dir, "second.bin")),
        base_id + 41: os.path.realpath(os.path.join(base_dir, "duplicate.bin")),
    }

    assert len(data) == len(expected_entries), (
        f"Dynamic test expected {len(expected_entries)} entries, found {len(data)}."
    )
    ids = [item.get("id") for item in data]
    assert all(isinstance(x, int) for x in ids), "All dynamic IDs should be integers."
    assert ids == sorted(ids), "Dynamic manifest is not sorted by ascending ID."

    actual_entries = {item.get("id"): item for item in data}
    assert set(actual_entries) == set(expected_entries), (
        f"Dynamic manifest IDs were {set(actual_entries)}, expected {set(expected_entries)}."
    )
    for artifact_id, expected_path in expected_entries.items():
        item = actual_entries[artifact_id]
        assert item.get("canonical_path") == expected_path, (
            f"Incorrect dynamically canonicalized path for ID {artifact_id}."
        )
        assert item.get("sha256") == get_sha256(expected_path), (
            f"Incorrect dynamic SHA256 for ID {artifact_id}."
        )


def main():
    validate_rust_project()

    with open(LOG, "rb") as f:
        original_log = f.read()

    original_generated_manifest = None
    dynamic_dir = None
    try:
        # Run the submitted program on the original task input, then retain every
        # assertion from the original verifier.
        run_utility()
        test_final_manifest_exists_and_valid()
        with open(MANIFEST, "rb") as f:
            original_generated_manifest = f.read()

        # Exercise the same compiled utility on unpredictable records so a fixed
        # JSON writer cannot pass.
        token = secrets.token_hex(8)
        base_id = 20000 + secrets.randbelow(500000)
        dynamic_dir = f"/home/user/artifacts/verifier_{token}"
        os.makedirs(dynamic_dir)

        files = {
            "duplicate.bin": secrets.token_bytes(73),
            "second.bin": secrets.token_bytes(91),
            "third.bin": secrets.token_bytes(117),
        }
        for name, content in files.items():
            with open(os.path.join(dynamic_dir, name), "wb") as f:
                f.write(content)

        os.symlink(dynamic_dir, os.path.join(dynamic_dir, "link"))
        records = [
            (base_id + 2, os.path.join(dynamic_dir, "duplicate.bin"), "verified"),
            (base_id + 41, os.path.join(dynamic_dir, "link", "link", "duplicate.bin"), "verified"),
            (base_id + 17, os.path.join(dynamic_dir, "second.bin"), "verified"),
            (base_id + 60, os.path.join(dynamic_dir, "second.bin"), "unverified"),
            (base_id + 5, os.path.join(dynamic_dir, "link", "third.bin"), "verified"),
            (base_id + 70, os.path.join(dynamic_dir, "missing.bin"), "verified"),
        ]
        with open(LOG, "w") as f:
            for artifact_id, path, status in records:
                f.write(
                    f"[Artifact]\nID: {artifact_id}\nPath: {path}\n"
                    f"Status: {status}\n---\n"
                )

        run_utility()
        test_dynamic_manifest(dynamic_dir, base_id)
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        if original_generated_manifest is not None:
            with open(MANIFEST, "wb") as f:
                f.write(original_generated_manifest)
        if dynamic_dir and os.path.lexists(dynamic_dir):
            shutil.rmtree(dynamic_dir)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_artifact_parser.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
