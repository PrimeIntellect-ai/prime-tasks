#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
from pathlib import Path


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_script_exists_and_executable():
    script_path = "/home/user/organize_docs.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_release_directories_created():
    assert os.path.isdir("/home/user/release/docs"), "Directory /home/user/release/docs does not exist"
    assert os.path.isdir("/home/user/release/models"), "Directory /home/user/release/models does not exist"


def test_markdown_files_processed_correctly():
    docs_dir = "/home/user/release/docs"
    expected_files = {
        "introduction_to_alpha_intro.md": "/home/user/doc_staging/project_alpha/v1/intro.md",
        "beta_notes_notes.md": "/home/user/doc_staging/project_beta/drafts/notes.md"
    }

    for expected_file, original_path in expected_files.items():
        target_path = os.path.join(docs_dir, expected_file)
        assert os.path.isfile(target_path), f"Expected file {expected_file} is missing in {docs_dir}"
        with open(target_path, "r") as tf, open(original_path, "r") as of:
            assert tf.read() == of.read(), f"Content of {expected_file} does not match the original file"

    all_docs = os.listdir(docs_dir)
    assert len(all_docs) == len(expected_files), f"Expected exactly {len(expected_files)} files in docs directory, found {len(all_docs)}"
    assert not any("spec" in f for f in all_docs), "Draft document (spec.md) should not be included in the release"


def test_gcode_files_processed_correctly():
    models_dir = "/home/user/release/models"
    expected_files = {
        "abs_housing.gcode": "/home/user/doc_staging/project_alpha/v1/housing.gcode",
        "pla_gear.gcode": "/home/user/doc_staging/shared_assets/printing/gear.gcode",
        "unknown_test_cube.gcode": "/home/user/doc_staging/shared_assets/printing/test_cube.gcode"
    }

    for expected_file, original_path in expected_files.items():
        target_path = os.path.join(models_dir, expected_file)
        assert os.path.isfile(target_path), f"Expected file {expected_file} is missing in {models_dir}"
        with open(target_path, "r") as tf, open(original_path, "r") as of:
            assert tf.read() == of.read(), f"Content of {expected_file} does not match the original file"

    all_models = os.listdir(models_dir)
    assert len(all_models) == len(expected_files), f"Expected exactly {len(expected_files)} files in models directory, found {len(all_models)}"


def test_manifest_generated_correctly():
    manifest_path = "/home/user/release/manifest.sha256"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    expected_entries = [
        "docs/beta_notes_notes.md",
        "docs/introduction_to_alpha_intro.md",
        "models/abs_housing.gcode",
        "models/pla_gear.gcode",
        "models/unknown_test_cube.gcode"
    ]

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_entries), f"Manifest should contain exactly {len(expected_entries)} entries, found {len(lines)}"
    actual_paths = []
    for line in lines:
        parts = line.split("  ")
        assert len(parts) == 2, f"Manifest line format incorrect: '{line}'. Expected '<hash>  <path>'"
        file_hash, rel_path = parts
        actual_paths.append(rel_path)
        full_path = os.path.join("/home/user/release", rel_path)
        assert os.path.isfile(full_path), f"File referenced in manifest does not exist: {full_path}"
        expected_hash = get_sha256(full_path)
        assert file_hash == expected_hash, f"Hash mismatch for {rel_path}. Expected {expected_hash}, got {file_hash}"

    assert actual_paths == expected_entries, "Manifest entries are not sorted alphabetically by relative path or contain wrong paths"


def test_script_processes_changed_recursive_inputs():
    token = secrets.token_hex(8)
    staging = Path("/home/user/doc_staging")
    release = Path("/home/user/release")
    backup = Path(f"/tmp/doc_staging_original_{token}")

    shutil.move(str(staging), str(backup))
    shutil.rmtree(release, ignore_errors=True)

    final_dir = staging / "new" / "deep" / token
    draft_dir = staging / "other" / "drafts"
    model_dir = staging / "assets" / "nested" / "models"
    final_dir.mkdir(parents=True)
    draft_dir.mkdir(parents=True)
    model_dir.mkdir(parents=True)

    final_name = f"guide_{token}.md"
    final_title = f"Runtime Probe {token}"
    final_content = f"---\ntitle: {final_title}\nstatus: final\n---\nDynamic content {token}.\n"
    (final_dir / final_name).write_text(final_content)

    draft_name = f"discard_{token}.md"
    draft_content = f"---\ntitle: Must Not Appear {token}\nstatus: draft\n---\nDiscard me.\n"
    (draft_dir / draft_name).write_text(draft_content)

    material_name = f"part_{token}.gcode"
    material = f"NYLON-{token.upper()}"
    material_content = f"; FLAVOR:Marlin\n; MATERIAL: {material}\nG28\nG1 X{len(token)} Y7\n"
    (model_dir / material_name).write_text(material_content)

    unknown_name = f"plain_{token}.gcode"
    unknown_content = f"; FLAVOR:Marlin\n; TEST-ID: {token}\nG28\n"
    (staging / unknown_name).write_text(unknown_content)

    try:
        proc = subprocess.run(
            ["/home/user/organize_docs.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise AssertionError(f"Failed to execute organize_docs.sh: {exc}")
    assert proc.returncode == 0, f"organize_docs.sh exited with {proc.returncode}:\n{proc.stdout}"

    docs = release / "docs"
    models = release / "models"
    assert docs.is_dir(), "Script did not create release/docs on a fresh run"
    assert models.is_dir(), "Script did not create release/models on a fresh run"

    expected_doc = f"{final_title.replace(' ', '_').lower()}_{final_name}"
    expected_material = f"{material.lower()}_{material_name}"
    expected_unknown = f"unknown_{unknown_name}"

    assert sorted(p.name for p in docs.iterdir()) == [expected_doc]
    assert sorted(p.name for p in models.iterdir()) == sorted([expected_material, expected_unknown])
    assert (docs / expected_doc).read_text() == final_content
    assert (models / expected_material).read_text() == material_content
    assert (models / expected_unknown).read_text() == unknown_content
    assert not any(draft_name in p.name for p in docs.iterdir()), "Draft document was copied"

    expected_paths = sorted([
        f"docs/{expected_doc}",
        f"models/{expected_material}",
        f"models/{expected_unknown}",
    ])
    manifest = release / "manifest.sha256"
    assert manifest.is_file(), "Script did not generate manifest.sha256"
    lines = [line.rstrip("\n") for line in manifest.read_text().splitlines() if line.strip()]
    assert len(lines) == len(expected_paths), "Dynamic manifest has an incorrect number of entries"

    actual_paths = []
    for line in lines:
        parts = line.split("  ")
        assert len(parts) == 2, f"Manifest line format incorrect: {line!r}"
        digest, rel_path = parts
        actual_paths.append(rel_path)
        target = release / rel_path
        assert target.is_file(), f"Manifest references missing file: {rel_path}"
        assert digest == get_sha256(target), f"Incorrect checksum for {rel_path}"

    assert actual_paths == expected_paths, "Dynamic manifest paths are incomplete or not alphabetically sorted"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
