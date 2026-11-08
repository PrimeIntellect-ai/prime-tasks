#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import gzip
import hashlib
import json
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/archiver")
ARCHIVE_DIR = "/home/user/dataset/archive"
RAW_FILE = "/home/user/dataset/raw_sensor.log"
CHUNK_SIZE = 1048576


def build_executable():
    assert (PROJECT_DIR / "Cargo.toml").is_file(), "Missing Rust Cargo.toml"
    assert (PROJECT_DIR / "src").is_dir(), "Missing Rust src directory"

    subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT_DIR,
        check=True,
        timeout=180,
    )
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT_DIR,
        text=True,
        timeout=30,
    ))
    root_id = metadata.get("resolve", {}).get("root")
    packages = metadata.get("packages", [])
    package = next((p for p in packages if p.get("id") == root_id), None)
    if package is None:
        package = next(
            (p for p in packages if Path(p["manifest_path"]).resolve() == (PROJECT_DIR / "Cargo.toml").resolve()),
            None,
        )
    assert package is not None, "Cargo project has no root package"
    bins = [t for t in package.get("targets", []) if "bin" in t.get("kind", [])]
    assert bins, "Cargo project does not define an executable target"
    default_run = package.get("default_run")
    target = next((t for t in bins if t["name"] == default_run), bins[0])
    executable = Path(metadata["target_directory"]) / "debug" / target["name"]
    assert executable.is_file(), f"Built executable is missing: {executable}"
    assert os.access(executable, os.X_OK), f"Built artifact is not executable: {executable}"
    return executable


def expected_parts(data):
    return [data[i:i + CHUNK_SIZE] for i in range(0, len(data), CHUNK_SIZE)]


def validate_archive(output_dir, original):
    output_dir = Path(output_dir)
    parts = expected_parts(original)
    names = [f"chunk_{i:04d}.gz" for i in range(len(parts))]
    expected_files = set(names) | {"manifest.json"}
    actual_files = {p.name for p in output_dir.iterdir()}
    assert actual_files == expected_files, f"Archive has unexpected or missing files: {actual_files}"

    reconstructed = bytearray()
    for name, expected in zip(names, parts):
        path = output_dir / name
        assert path.is_file(), f"Missing chunk {name}"
        with gzip.open(path, "rb") as f:
            contents = f.read()
        assert contents == expected, f"{name} does not contain exactly its 1 MiB input slice"
        reconstructed.extend(contents)
    assert bytes(reconstructed) == original

    manifest_path = output_dir / "manifest.json"
    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)
    assert isinstance(manifest, list)
    assert len(manifest) == len(parts)
    for i, (entry, part) in enumerate(zip(manifest, parts)):
        assert isinstance(entry, dict)
        assert set(entry.keys()) == {"chunk", "original_sha256"}, "Manifest objects must have exactly two keys"
        assert entry["chunk"] == names[i]
        assert entry["original_sha256"] == hashlib.sha256(part).hexdigest()


def run_tool(executable, input_path, output_dir):
    subprocess.run(
        [str(executable), str(input_path), str(output_dir)],
        check=True,
        timeout=120,
    )


def run_with_atomic_monitor(executable, input_path, output_dir):
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    try:
        wd = libc.inotify_add_watch(fd, os.fsencode(output_dir), IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE)
        assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
        run_tool(executable, input_path, output_dir)

        raw_events = bytearray()
        while True:
            try:
                block = os.read(fd, 65536)
                if not block:
                    break
                raw_events.extend(block)
            except BlockingIOError:
                break

        events = []
        offset = 0
        while offset < len(raw_events):
            wd_value, mask, cookie, name_len = struct.unpack_from("iIII", raw_events, offset)
            offset += struct.calcsize("iIII")
            name_bytes = bytes(raw_events[offset:offset + name_len]).split(b"\0", 1)[0]
            offset += name_len
            events.append((mask, cookie, os.fsdecode(name_bytes)))

        final_names = sorted(p.name for p in Path(output_dir).iterdir())
        moved_to = [(idx, cookie, name) for idx, (mask, cookie, name) in enumerate(events) if mask & IN_MOVED_TO]
        moved_from = [(idx, cookie, name) for idx, (mask, cookie, name) in enumerate(events) if mask & IN_MOVED_FROM]

        final_move_indices = {}
        for final_name in final_names:
            destinations = [(idx, cookie) for idx, cookie, name in moved_to if name == final_name and cookie != 0]
            assert destinations, f"{final_name} was not atomically renamed into place"
            destination_index, cookie = destinations[-1]
            sources = [(idx, name) for idx, source_cookie, name in moved_from if source_cookie == cookie]
            assert sources, f"No temporary-file rename source observed for {final_name}"
            source_index, source_name = sources[-1]
            assert source_index < destination_index
            assert source_name != final_name and source_name.startswith(".tmp"), f"{final_name} was not renamed from a temporary file"
            if final_name == "manifest.json":
                assert source_name == ".tmp_manifest.json", "Manifest must be written via .tmp_manifest.json"
            source_created = any(
                idx < source_index and name == source_name and (mask & IN_CREATE)
                for idx, (mask, _, name) in enumerate(events)
            )
            source_closed = any(
                idx < source_index and name == source_name and (mask & IN_CLOSE_WRITE)
                for idx, (mask, _, name) in enumerate(events)
            )
            assert source_created and source_closed, f"Temporary file {source_name} was not written before rename"
            final_move_indices[final_name] = destination_index

        chunk_moves = [idx for name, idx in final_move_indices.items() if name.startswith("chunk_")]
        assert chunk_moves
        assert final_move_indices["manifest.json"] > max(chunk_moves), "Manifest was published before all chunks"
    finally:
        os.close(fd)


EXECUTABLE = build_executable()

# Exercise the utility on verifier-generated inputs rather than trusting only the fixed artifacts.
with tempfile.TemporaryDirectory(prefix="archiver-tests-") as temp_root:
    temp_root = Path(temp_root)
    cases = [
        os.urandom(32768 + secrets.randbelow(32768)),
        os.urandom(2 * CHUNK_SIZE + 1 + secrets.randbelow(CHUNK_SIZE - 1)),
    ]
    for index, data in enumerate(cases):
        input_path = temp_root / f"input-{index}.bin"
        output_path = temp_root / f"output-{index}"
        input_path.write_bytes(data)
        run_tool(EXECUTABLE, input_path, output_path)
        assert output_path.is_dir(), "Tool did not create the requested output directory"
        validate_archive(output_path, data)

# Re-run on the required dataset, observe atomic publication, and leave these artifacts in place.
archive_path = Path(ARCHIVE_DIR)
if archive_path.exists():
    shutil.rmtree(archive_path)
archive_path.mkdir(parents=True)
assert Path(RAW_FILE).is_file(), f"Original file {RAW_FILE} is missing"
run_with_atomic_monitor(EXECUTABLE, RAW_FILE, ARCHIVE_DIR)
validate_archive(ARCHIVE_DIR, Path(RAW_FILE).read_bytes())


def test_chunk_files_exist():
    """Test that exactly the expected chunk files exist."""
    expected_chunks = ["chunk_0000.gz", "chunk_0001.gz", "chunk_0002.gz"]
    for chunk in expected_chunks:
        chunk_path = os.path.join(ARCHIVE_DIR, chunk)
        assert os.path.isfile(chunk_path), f"Expected chunk file {chunk} is missing in {ARCHIVE_DIR}"


def test_no_tmp_files():
    """Test that no temporary files remain in the archive directory."""
    files = os.listdir(ARCHIVE_DIR)
    tmp_files = [f for f in files if f.startswith(".tmp")]
    assert len(tmp_files) == 0, f"Found temporary files in {ARCHIVE_DIR}: {tmp_files}"


def test_reconstructed_data():
    """Test that uncompressing and concatenating the chunks matches the original file."""
    expected_chunks = ["chunk_0000.gz", "chunk_0001.gz", "chunk_0002.gz"]
    reconstructed = b""

    for chunk in expected_chunks:
        chunk_path = os.path.join(ARCHIVE_DIR, chunk)
        assert os.path.isfile(chunk_path), f"Missing {chunk_path}"
        with gzip.open(chunk_path, "rb") as f:
            reconstructed += f.read()

    assert os.path.isfile(RAW_FILE), f"Original file {RAW_FILE} is missing"
    with open(RAW_FILE, "rb") as f:
        original_data = f.read()

    assert reconstructed == original_data, "Reconstructed data from chunks does not match the original raw_sensor.log"


def test_manifest_json():
    """Test that manifest.json exists, is valid, and contains the correct hashes."""
    manifest_path = os.path.join(ARCHIVE_DIR, "manifest.json")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing"

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON")

    assert isinstance(manifest, list), "Manifest should be a JSON array"

    expected_chunks = ["chunk_0000.gz", "chunk_0001.gz", "chunk_0002.gz"]
    assert len(manifest) == len(expected_chunks), f"Manifest should contain {len(expected_chunks)} entries"

    actual_hashes = []
    with open(RAW_FILE, "rb") as f:
        while True:
            data = f.read(CHUNK_SIZE)
            if not data:
                break
            actual_hashes.append(hashlib.sha256(data).hexdigest())

    assert len(actual_hashes) == len(expected_chunks), "Unexpected number of chunks in original file"

    manifest_dict = {}
    for entry in manifest:
        assert isinstance(entry, dict), "Manifest entry should be a JSON object"
        assert "chunk" in entry, "Manifest entry missing 'chunk' key"
        assert "original_sha256" in entry, "Manifest entry missing 'original_sha256' key"
        manifest_dict[entry["chunk"]] = entry["original_sha256"]

    for i, chunk_name in enumerate(expected_chunks):
        assert chunk_name in manifest_dict, f"{chunk_name} missing from manifest"
        assert manifest_dict[chunk_name] == actual_hashes[i], f"Hash mismatch for {chunk_name}: expected {actual_hashes[i]}, got {manifest_dict[chunk_name]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
