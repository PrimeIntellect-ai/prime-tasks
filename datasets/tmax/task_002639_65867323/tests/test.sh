#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def test_script_exists():
    """Test that the required Python script exists."""
    script_path = "/home/user/process_artifacts.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_curated_binaries_directory():
    """Test that the curated_binaries directory exists and contains only the expected .bin files."""
    curated_dir = "/home/user/curated_binaries"
    assert os.path.exists(curated_dir), f"Directory {curated_dir} does not exist."
    assert os.path.isdir(curated_dir), f"{curated_dir} is not a directory."

    files = sorted(os.listdir(curated_dir))
    expected_files = ["alpha.bin", "beta.bin", "delta.bin", "gamma.bin"]
    assert files == expected_files, f"Expected files in {curated_dir} to be {expected_files}, but found {files}."


def test_manifest_exists_and_correct():
    """Test that the manifest file exists, is sorted, and contains correct checksums."""
    manifest_path = "/home/user/manifest.sha256"
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} does not exist."
    assert os.path.isfile(manifest_path), f"{manifest_path} is not a file."

    expected_content = (
        "e8243ea5ee904128540c5bdece9eaf3c224217112ea1bc84ed9a572a6e9a7e6b  alpha.bin\n"
        "03f56360098dfc0fcf9c0bfdff310ee9cfb0068ba02ce7614e5b98bc28f41180  beta.bin\n"
        "1476db7806f71d53dc20bf9eb4ff02cd909e7c5dfa9a62ce7d7164b3dae3ebba  delta.bin\n"
        "fb8f2c300c3b84db53044b7d446eb2db865d4b55bebfb799988ee09bbca11c06  gamma.bin\n"
    )

    with open(manifest_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Manifest content does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )


def test_binaries_content():
    """Test that the extracted binaries have the correct content/checksums."""
    curated_dir = "/home/user/curated_binaries"
    expected_hashes = {
        "alpha.bin": "e8243ea5ee904128540c5bdece9eaf3c224217112ea1bc84ed9a572a6e9a7e6b",
        "beta.bin": "03f56360098dfc0fcf9c0bfdff310ee9cfb0068ba02ce7614e5b98bc28f41180",
        "delta.bin": "1476db7806f71d53dc20bf9eb4ff02cd909e7c5dfa9a62ce7d7164b3dae3ebba",
        "gamma.bin": "fb8f2c300c3b84db53044b7d446eb2db865d4b55bebfb799988ee09bbca11c06"
    }

    for filename, expected_hash in expected_hashes.items():
        filepath = os.path.join(curated_dir, filename)
        assert os.path.exists(filepath), f"File {filepath} is missing."

        with open(filepath, "rb") as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()

        assert actual_hash == expected_hash, f"Hash mismatch for {filename}. Expected {expected_hash}, got {actual_hash}."


def test_script_programmatically_processes_nested_archives():
    """Execute the submitted script against a fresh, unpredictable payload."""
    script_path = "/home/user/process_artifacts.py"
    payload_path = "/home/user/incoming/payload.tar"
    curated_dir = "/home/user/curated_binaries"
    manifest_path = "/home/user/manifest.sha256"
    backup_dir = tempfile.mkdtemp(prefix="artifact-verifier-")

    saved_payload = os.path.join(backup_dir, "payload.tar")
    saved_curated = os.path.join(backup_dir, "curated_binaries")
    saved_manifest = os.path.join(backup_dir, "manifest.sha256")

    try:
        shutil.move(payload_path, saved_payload)
        if os.path.lexists(curated_dir):
            shutil.move(curated_dir, saved_curated)
        if os.path.lexists(manifest_path):
            shutil.move(manifest_path, saved_manifest)

        token = secrets.token_hex(8)
        expected = {
            f"a-{token}.bin": secrets.token_bytes(41),
            f"m-{token}.bin": secrets.token_bytes(73),
            f"z-{token}.bin": secrets.token_bytes(109),
        }

        zip_one = os.path.join(backup_dir, "first.zip")
        zip_two = os.path.join(backup_dir, "second.zip")
        with zipfile.ZipFile(zip_one, "w") as archive:
            archive.writestr(f"deep/tree/{sorted(expected)[2]}", expected[sorted(expected)[2]])
            archive.writestr("deep/tree/ignore.txt", b"not a binary")
        with zipfile.ZipFile(zip_two, "w") as archive:
            archive.writestr(f"other/{sorted(expected)[0]}", expected[sorted(expected)[0]])
            archive.writestr(sorted(expected)[1], expected[sorted(expected)[1]])
            archive.writestr("ignore.dat", secrets.token_bytes(20))

        with tarfile.open(payload_path, "w") as archive:
            archive.add(zip_one, arcname="nested/first.zip")
            archive.add(zip_two, arcname="second.zip")

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Script failed on a fresh payload with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isdir(curated_dir), "Script did not create curated_binaries."
        assert sorted(os.listdir(curated_dir)) == sorted(expected), (
            "Script did not extract exactly the .bin files from the fresh nested archives."
        )
        for filename, content in expected.items():
            with open(os.path.join(curated_dir, filename), "rb") as f:
                assert f.read() == content, f"Extracted content is wrong for {filename}."

        assert os.path.isfile(manifest_path), "Script did not create manifest.sha256."
        expected_manifest = "\n".join(
            f"{hashlib.sha256(expected[name]).hexdigest()}  {name}"
            for name in sorted(expected)
        )
        with open(manifest_path, "r") as f:
            actual_manifest = f.read()
        assert actual_manifest.strip() == expected_manifest, (
            "Manifest for the fresh payload has incorrect hashes, formatting, or filename order."
        )
    finally:
        if os.path.lexists(payload_path):
            os.remove(payload_path)
        if os.path.lexists(curated_dir):
            if os.path.isdir(curated_dir) and not os.path.islink(curated_dir):
                shutil.rmtree(curated_dir)
            else:
                os.remove(curated_dir)
        if os.path.lexists(manifest_path):
            os.remove(manifest_path)
        if os.path.exists(saved_payload):
            shutil.move(saved_payload, payload_path)
        if os.path.exists(saved_curated):
            shutil.move(saved_curated, curated_dir)
        if os.path.exists(saved_manifest):
            shutil.move(saved_manifest, manifest_path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
