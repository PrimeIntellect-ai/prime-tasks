#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import json
import os
import resource
import shutil
import subprocess
import tarfile
import tempfile

PROJECT = "/home/user/dataset_archiver"
TAR_PATH = "/home/user/processed_dataset.tar"
SENSOR_DIR = "/home/user/sensor_data"
BINARY = os.path.join(PROJECT, "target", "release", "dataset_archiver")


def test_00_rust_project_builds_release_binary():
    assert os.path.isdir(PROJECT), "/home/user/dataset_archiver/ does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."

    rust_sources = []
    for root, _, files in os.walk(os.path.join(PROJECT, "src")):
        rust_sources.extend(os.path.join(root, f) for f in files if f.endswith(".rs"))
    assert rust_sources, "The project contains no Rust source files."
    assert any(os.path.getsize(path) > 0 for path in rust_sources), "Rust source files are empty."

    metadata = subprocess.run(
        ["cargo", "metadata", "--offline", "--format-version", "1", "--no-deps"],
        cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=60,
    )
    assert metadata.returncode == 0, f"cargo metadata failed:\n{metadata.stderr}"
    packages = json.loads(metadata.stdout).get("packages", [])
    assert any(
        package.get("name") == "dataset_archiver" and
        any(target.get("name") == "dataset_archiver" and "bin" in target.get("kind", [])
            for target in package.get("targets", []))
        for package in packages
    ), "Cargo project does not define a dataset_archiver binary target."

    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    build = subprocess.run(
        ["cargo", "build", "--release", "--offline"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stderr}"
    assert os.path.isfile(BINARY), "Release binary was not produced."
    assert os.access(BINARY, os.X_OK), "Release binary is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not a native executable."


def test_10_processed_dataset_tar_exists():
    assert os.path.isfile(TAR_PATH), "/home/user/processed_dataset.tar does not exist."


def test_11_original_files_untouched():
    expected_files = ["alpha.csv.gz", "beta.csv.gz", "gamma.csv.gz"]
    for f in expected_files:
        path = os.path.join(SENSOR_DIR, f)
        assert os.path.isfile(path), f"Original file {path} is missing or was deleted."


def test_12_tar_contents_and_manifest():
    assert os.path.isfile(TAR_PATH), "Tar file missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(TAR_PATH, "r") as tar:
            tar.extractall(path=tmpdir)

        extracted_files = os.listdir(tmpdir)
        expected_csvs = ["alpha.csv", "beta.csv", "gamma.csv"]
        for f in expected_csvs:
            assert f in extracted_files, f"{f} is missing from the tar archive."

        assert "manifest.json" in extracted_files, "manifest.json is missing from the tar archive."

        manifest_path = os.path.join(tmpdir, "manifest.json")
        with open(manifest_path, "r") as f:
            try:
                manifest = json.load(f)
            except json.JSONDecodeError:
                assert False, "manifest.json is not valid JSON."

        assert isinstance(manifest, dict), "manifest.json must contain a JSON object."

        for csv_file in expected_csvs:
            assert csv_file in manifest, f"{csv_file} is missing from manifest.json."

            extracted_csv_path = os.path.join(tmpdir, csv_file)
            with open(extracted_csv_path, "rb") as f:
                extracted_data = f.read()

            actual_hash = hashlib.sha256(extracted_data).hexdigest()
            assert manifest[csv_file] == actual_hash, f"Hash mismatch in manifest for {csv_file}. Expected {actual_hash}, got {manifest[csv_file]}."

            gz_file = csv_file + ".gz"
            gz_path = os.path.join(SENSOR_DIR, gz_file)
            assert os.path.isfile(gz_path), f"Original {gz_path} missing."

            with gzip.open(gz_path, "rb") as f:
                original_uncompressed_data = f.read()

            assert extracted_data == original_uncompressed_data, f"Data in {csv_file} does not match the original uncompressed data."


def _limited_address_space():
    limit = 128 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def _hash_tar_member(tar, name):
    member = tar.getmember(name)
    stream = tar.extractfile(member)
    assert stream is not None
    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            break
        size += len(chunk)
        digest.update(chunk)
    return size, digest.hexdigest()


def test_20_execute_rust_binary_on_derived_streaming_inputs():
    sensor_backup = SENSOR_DIR + ".verifier_backup"
    tar_backup = TAR_PATH + ".verifier_backup"
    assert not os.path.exists(sensor_backup)
    assert not os.path.exists(tar_backup)

    os.rename(SENSOR_DIR, sensor_backup)
    os.mkdir(SENSOR_DIR)
    os.rename(TAR_PATH, tar_backup)

    expected = {}
    expected_sizes = {}
    try:
        small_name = "derived-17.csv"
        small_path = os.path.join(SENSOR_DIR, small_name + ".gz")
        small_hash = hashlib.sha256()
        small_size = 0
        with gzip.open(small_path, "wb", compresslevel=6) as out:
            for i in range(8192):
                chunk = f"{i},sensor_{i % 31},{(i * 7919) % 100003}\n".encode()
                out.write(chunk)
                small_hash.update(chunk)
                small_size += len(chunk)
        expected[small_name] = small_hash.hexdigest()
        expected_sizes[small_name] = small_size

        # This decompressed input is larger than the process memory limit. A
        # program that buffers the complete decompressed file cannot pass.
        large_name = "streaming-check.csv"
        large_path = os.path.join(SENSOR_DIR, large_name + ".gz")
        block = b"streaming,sensor,1234567890\n" * 4096
        target_size = 160 * 1024 * 1024
        large_hash = hashlib.sha256()
        large_size = 0
        with gzip.open(large_path, "wb", compresslevel=1) as out:
            while large_size < target_size:
                chunk = block[:min(len(block), target_size - large_size)]
                out.write(chunk)
                large_hash.update(chunk)
                large_size += len(chunk)
        expected[large_name] = large_hash.hexdigest()
        expected_sizes[large_name] = large_size

        run = subprocess.run(
            [BINARY], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            preexec_fn=_limited_address_space, timeout=120,
        )
        assert run.returncode == 0, (
            "The release Rust binary failed on valid derived inputs under a "
            f"streaming memory bound. stderr:\n{run.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(TAR_PATH), "Executing the release binary did not create the tar archive."

        with tarfile.open(TAR_PATH, "r") as tar:
            names = tar.getnames()
            for name in expected:
                assert names.count(name) == 1, f"Archive must contain exactly one {name}."
            assert names.count("manifest.json") == 1, "Archive must contain exactly one manifest.json."

            manifest_file = tar.extractfile(tar.getmember("manifest.json"))
            assert manifest_file is not None
            manifest = json.load(manifest_file)
            assert isinstance(manifest, dict), "Generated manifest is not a JSON object."

            for name, expected_hash in expected.items():
                size, actual_hash = _hash_tar_member(tar, name)
                assert size == expected_sizes[name], f"Wrong uncompressed size for {name}."
                assert actual_hash == expected_hash, f"Archived bytes for {name} are incorrect."
                assert manifest.get(name) == expected_hash, f"Manifest hash for {name} is incorrect."
    finally:
        if os.path.isdir(SENSOR_DIR):
            shutil.rmtree(SENSOR_DIR)
        os.rename(sensor_backup, SENSOR_DIR)
        if os.path.exists(TAR_PATH):
            os.remove(TAR_PATH)
        os.rename(tar_backup, TAR_PATH)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
