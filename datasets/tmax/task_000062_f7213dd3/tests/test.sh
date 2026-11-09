#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tarfile
import tempfile
import threading
import time
import uuid


def test_archive_exists():
    archive_path = "/home/user/repo/firmware_packaged.tar.gz"
    assert os.path.isfile(archive_path), f"Archive not found at {archive_path}"


def test_archive_contents_and_sizes():
    archive_path = "/home/user/repo/firmware_packaged.tar.gz"
    assert os.path.isfile(archive_path), "Archive not found"

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        # Check that there are exactly 3 files and no directories
        assert len(members) == 3, f"Expected 3 files in archive, found {len(members)}"

        names = sorted([m.name for m in members])
        expected_names = ["part_00", "part_01", "part_02"]
        # Allow optional ./ prefix
        names_cleaned = [n.replace("./", "") for n in names]
        assert names_cleaned == expected_names, f"Expected files {expected_names}, found {names_cleaned}"

        sizes = {}
        for m in members:
            sizes[m.name.replace("./", "")] = m.size

        assert sizes["part_00"] == 1000, f"part_00 size incorrect: {sizes['part_00']} != 1000"
        assert sizes["part_01"] == 1000, f"part_01 size incorrect: {sizes['part_01']} != 1000"
        assert sizes["part_02"] == 500, f"part_02 size incorrect: {sizes['part_02']} != 500"


def test_reassembled_content():
    archive_path = "/home/user/repo/firmware_packaged.tar.gz"
    firmware_path = "/home/user/firmware.bin"

    assert os.path.isfile(archive_path), "Archive not found"
    assert os.path.isfile(firmware_path), "Original firmware file not found"

    with open(firmware_path, "rb") as f:
        original_data = f.read()

    reassembled_data = bytearray()
    with tarfile.open(archive_path, "r:gz") as tar:
        part00 = next(m for m in tar.getmembers() if m.name.endswith("part_00"))
        part01 = next(m for m in tar.getmembers() if m.name.endswith("part_01"))
        part02 = next(m for m in tar.getmembers() if m.name.endswith("part_02"))

        reassembled_data.extend(tar.extractfile(part00).read())
        reassembled_data.extend(tar.extractfile(part01).read())
        reassembled_data.extend(tar.extractfile(part02).read())

    assert original_data == reassembled_data, "Reassembled chunks do not match the original firmware file"


def test_atomic_rename_in_code():
    code_path = "/home/user/curate.go"
    assert os.path.isfile(code_path), f"Go source file not found at {code_path}"

    with open(code_path, "r") as f:
        code = f.read()

    has_os_rename = "os.Rename" in code
    has_mv = "mv " in code
    assert has_os_rename or has_mv, "No atomic rename logic (os.Rename or mv) found in the Go source code"


def _check_dynamic_archive(path, source_data, chunk_size, prefix):
    expected_chunks = [
        source_data[i:i + chunk_size]
        for i in range(0, len(source_data), chunk_size)
    ]
    expected_names = [f"{prefix}{i:02d}" for i in range(len(expected_chunks))]

    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        assert len(members) == len(expected_names)
        assert all(m.isfile() for m in members), "Archive contains a non-file entry"

        cleaned = {}
        for member in members:
            name = member.name[2:] if member.name.startswith("./") else member.name
            assert "/" not in name, f"Archive member is not at the root: {member.name}"
            assert name not in cleaned, f"Duplicate archive member: {name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            cleaned[name] = extracted.read()

    assert sorted(cleaned) == expected_names
    for name, expected in zip(expected_names, expected_chunks):
        assert cleaned[name] == expected, f"Incorrect data in {name}"


def test_program_executes_dynamic_config_and_replaces_atomically():
    code_path = "/home/user/curate.go"
    config_path = "/home/user/config.json"
    assert os.path.isfile(code_path), "Go source file not found"

    with open(config_path, "rb") as f:
        original_config = f.read()

    dynamic_root = tempfile.mkdtemp(prefix="curate-verifier-", dir="/home/user")
    source_path = os.path.join(dynamic_root, "input.bin")
    output_dir = os.path.join(dynamic_root, "out")
    destination = os.path.join(output_dir, "result.tar.gz")
    binary_path = f"/tmp/curate-under-test-{uuid.uuid4().hex}"
    os.mkdir(output_dir)

    # Large incompressible input makes a direct write to the destination observable.
    source_data = os.urandom(16 * 1024 * 1024 + 123)
    chunk_size = 1024 * 1024
    prefix = "dynamic_"
    with open(source_path, "wb") as f:
        f.write(source_data)

    sentinel = b"preexisting-client-visible-archive"
    with open(destination, "wb") as f:
        f.write(sentinel)
    initial_inode = os.stat(destination).st_ino

    dynamic_config = {
        "source_file": source_path,
        "chunk_size": chunk_size,
        "chunk_prefix": prefix,
        "dest_archive": destination,
    }

    observer_errors = []
    observed_replacement = threading.Event()
    stop_observer = threading.Event()
    observer_ready = threading.Event()

    def observe_destination():
        observer_ready.set()
        while not stop_observer.is_set():
            try:
                st = os.stat(destination)
                if st.st_ino == initial_inode:
                    with open(destination, "rb") as f:
                        current = f.read(len(sentinel) + 1)
                    if current != sentinel or st.st_size != len(sentinel):
                        observer_errors.append("destination was modified in place instead of atomically replaced")
                        return
                else:
                    try:
                        _check_dynamic_archive(destination, source_data, chunk_size, prefix)
                    except Exception as exc:
                        observer_errors.append(f"a client observed a partial or invalid replacement: {exc}")
                    observed_replacement.set()
                    return
            except FileNotFoundError:
                observer_errors.append("destination temporarily disappeared during replacement")
                return
            time.sleep(0.001)

    observer = None
    try:
        build = subprocess.run(
            ["go", "build", "-o", binary_path, code_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert build.returncode == 0, f"curate.go did not compile:\n{build.stderr}"

        with open(config_path, "w") as f:
            json.dump(dynamic_config, f)

        observer = threading.Thread(target=observe_destination, daemon=True)
        observer.start()
        assert observer_ready.wait(2)

        run = subprocess.run(
            [binary_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert run.returncode == 0, f"compiled program failed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"

        observed_replacement.wait(2)
        stop_observer.set()
        observer.join(timeout=2)

        assert not observer_errors, observer_errors[0] if observer_errors else "observer failed"
        assert observed_replacement.is_set(), "destination was not observed as an atomic inode replacement"
        assert os.path.isfile(destination), "dynamic destination archive was not created"
        assert os.stat(destination).st_ino != initial_inode, "destination was overwritten rather than atomically renamed"
        _check_dynamic_archive(destination, source_data, chunk_size, prefix)

        # Temporary chunk files/directories and archive files must have been cleaned up.
        assert set(os.listdir(dynamic_root)) == {"input.bin", "out"}, "temporary files or directories were not cleaned up"
        assert set(os.listdir(output_dir)) == {"result.tar.gz"}, "temporary archive files were not cleaned up"
    finally:
        stop_observer.set()
        if observer is not None:
            observer.join(timeout=2)
        with open(config_path, "wb") as f:
            f.write(original_config)
        try:
            os.remove(binary_path)
        except FileNotFoundError:
            pass
        import shutil
        shutil.rmtree(dynamic_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
