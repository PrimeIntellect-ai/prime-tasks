#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/home/user/.cargo/bin:$PATH"
export HOME=/home/user

cat <<'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import io
import json
import os
import shutil
import subprocess
import tarfile
import threading
import time
import zipfile

import pytest

ROOT = "/home/user/artifact_manager"
BINARIES = os.path.join(ROOT, "binaries")
CURATED = os.path.join(ROOT, "curated")
INVENTORY = os.path.join(ROOT, "inventory.txt")
FINAL_INVENTORY = os.path.join(ROOT, "final_inventory.txt")
SCRIPT = os.path.join(ROOT, "run_all.sh")
CURATOR = os.path.join(ROOT, "curator")


def test_final_inventory_contents():
    """Test that final_inventory.txt contains the exact expected sorted output."""
    final_inventory_path = "/home/user/artifact_manager/final_inventory.txt"
    assert os.path.isfile(final_inventory_path), f"File {final_inventory_path} is missing."
    with open(final_inventory_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()
    expected_content = [
        "[bundle_1.tar.gz] fileA.bin",
        "[bundle_1.tar.gz] fileB.bin",
        "[bundle_3.tar.gz] fileD.bin",
    ]
    assert content == expected_content, f"Contents of {final_inventory_path} do not match the expected output. Got: {content}"


def test_curated_files_extracted():
    """Test that the inner files were properly extracted to the curated directory."""
    curated_dir = "/home/user/artifact_manager/curated"
    expected_files = ["fileA.bin", "fileB.bin", "fileD.bin"]
    for file in expected_files:
        file_path = os.path.join(curated_dir, file)
        assert os.path.isfile(file_path), f"Extracted file {file_path} is missing."


def test_rust_source_locking_mechanism():
    """Test that the Rust source code uses a file locking mechanism."""
    main_rs_path = "/home/user/artifact_manager/curator/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Rust source file {main_rs_path} is missing."
    with open(main_rs_path, "r", encoding="utf-8") as f:
        source_code = f.read()
    locking_keywords = ["lock_exclusive", "flock", "lock", "fs4", "fd-lock", "try_lock_exclusive"]
    has_lock = any(keyword in source_code for keyword in locking_keywords)
    assert has_lock, f"Rust source code in {main_rs_path} does not appear to use a file locking mechanism."


def test_run_all_script_exists():
    """Test that the bash script run_all.sh exists."""
    assert os.path.isfile(SCRIPT), f"Bash script {SCRIPT} is missing."


def make_nested_archive(path, files):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    zip_bytes = io.BytesIO()
    with zipfile.ZipFile(zip_bytes, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in files.items():
            zf.writestr(name, data)
    zip_bytes.seek(0)
    inner_name = os.path.basename(path).replace(".tar.gz", "_inner.zip")
    info = tarfile.TarInfo(inner_name)
    info.size = len(zip_bytes.getbuffer())
    with tarfile.open(path, "w:gz") as tf:
        tf.addfile(info, zip_bytes)


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def running_archive_processes(marker):
    count = 0
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "ignore")
            if marker in cmd and ".tar.gz" in cmd:
                count += 1
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return count


def test_real_execution_parsing_extraction_concurrency_and_locking():
    assert os.path.isfile(os.path.join(CURATOR, "Cargo.toml")), "Rust Cargo.toml is missing"

    shutil.rmtree(CURATED, ignore_errors=True)
    os.makedirs(CURATED)
    for path in (INVENTORY, FINAL_INVENTORY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    marker = "verifier_batch_"
    records = []
    expected_data = {}
    successful_archives = []

    # Put one successful archive below a Latin-1-only path component. A parser
    # that treats uploads.log as UTF-8 without conversion cannot recover it.
    latin_dir = os.path.join(BINARIES, "caf\u00e9")
    for i in range(8):
        directory = latin_dir if i == 0 else BINARIES
        archive = os.path.join(directory, f"{marker}{i}.tar.gz")
        files = {}
        for j in range(500):
            name = f"v{i:02d}_{j:04d}.bin"
            data = f"payload-{i}-{j}-\u00e9\n".encode("utf-8")
            files[name] = data
            expected_data[name] = data
        make_nested_archive(archive, files)
        successful_archives.append(archive)
        records.append((archive, "SUCCESS"))

    failed_archive = os.path.join(BINARIES, f"{marker}failed.tar.gz")
    make_nested_archive(failed_archive, {"forbidden.bin": b"must not be extracted\n"})
    records.insert(3, (failed_archive, "FAILED"))

    log_text = "".join(
        f"START_RECORD\nFile: {path}\nStatus: {status}\nEND_RECORD\n"
        for path, status in records
    )
    with open(os.path.join(ROOT, "uploads.log"), "wb") as f:
        f.write(log_text.encode("iso-8859-1"))

    proc = subprocess.Popen(
        ["bash", SCRIPT], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env=os.environ.copy()
    )
    max_parallel = 0
    while proc.poll() is None:
        max_parallel = max(max_parallel, running_archive_processes(marker))
        time.sleep(0.002)
    output = proc.stdout.read() if proc.stdout else ""
    assert proc.returncode == 0, f"run_all.sh failed with exit {proc.returncode}:\n{output}"
    assert max_parallel >= 2, "run_all.sh did not invoke the Rust curator concurrently"

    expected_lines = []
    for archive in successful_archives:
        outer = os.path.basename(archive)
        for name in sorted(n for n in expected_data if n.startswith(f"v{successful_archives.index(archive):02d}_")):
            expected_lines.append(f"[{outer}] {name}")
    expected_lines = sorted(expected_lines)

    assert os.path.isfile(FINAL_INVENTORY), "run_all.sh did not create final_inventory.txt"
    assert read_lines(FINAL_INVENTORY) == expected_lines
    assert read_lines(FINAL_INVENTORY) == sorted(read_lines(FINAL_INVENTORY))
    assert os.path.isfile(INVENTORY), "run_all.sh did not create inventory.txt"
    assert sorted(read_lines(INVENTORY)) == expected_lines
    assert len(read_lines(INVENTORY)) == len(set(read_lines(INVENTORY))), "inventory contains duplicate/corrupt entries"

    actual_files = set(os.listdir(CURATED))
    assert actual_files == set(expected_data), f"Unexpected or missing curated files: {actual_files ^ set(expected_data)}"
    assert "forbidden.bin" not in actual_files, "A FAILED upload was extracted"
    for name, data in expected_data.items():
        with open(os.path.join(CURATED, name), "rb") as f:
            assert f.read() == data, f"Extracted contents are wrong for {name}"

    # Build and execute the submitted Rust artifact directly. Hold both common
    # Unix advisory lock types on inventory.txt: a compliant curator must block
    # before appending and then finish after the lock is released.
    subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", os.path.join(CURATOR, "Cargo.toml")],
        check=True, timeout=180, env=os.environ.copy()
    )
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--no-deps", "--format-version", "1",
        "--manifest-path", os.path.join(CURATOR, "Cargo.toml")
    ], text=True, env=os.environ.copy()))
    bins = [t["name"] for p in metadata["packages"] for t in p["targets"] if "bin" in t["kind"]]
    assert bins, "The Rust project has no binary target"
    executable = os.path.join(metadata["target_directory"], "debug", bins[0])
    assert os.path.isfile(executable), "The Rust binary was not produced"

    shutil.rmtree(CURATED)
    os.makedirs(CURATED)
    with open(INVENTORY, "w+b") as lock_file:
        fcntl.lockf(lock_file, fcntl.LOCK_EX)
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        child = subprocess.Popen(
            [executable, successful_archives[0]], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, env=os.environ.copy()
        )
        try:
            deadline = time.time() + 10
            extracted = os.path.join(CURATED, "v00_0000.bin")
            while time.time() < deadline and child.poll() is None and not os.path.isfile(extracted):
                time.sleep(0.02)
            assert os.path.isfile(extracted), "Direct Rust execution did not extract the archive"
            time.sleep(0.4)
            lock_file.seek(0)
            assert child.poll() is None, "Rust curator did not wait for the filesystem lock"
            assert lock_file.read() == b"", "Rust curator wrote inventory data while another process held the lock"
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)
            fcntl.lockf(lock_file, fcntl.LOCK_UN)
        child_output, _ = child.communicate(timeout=30)
        assert child.returncode == 0, f"Direct Rust execution failed:\n{child_output}"

    direct_expected = sorted(
        f"[{os.path.basename(successful_archives[0])}] v00_{j:04d}.bin" for j in range(500)
    )
    assert sorted(read_lines(INVENTORY)) == direct_expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
