#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import zlib
import base64
import glob
import time
import shutil
import signal
import subprocess
from collections import Counter
import pytest

ARCHIVE_DIR = "/home/user/archive"
MANIFEST_PATH = os.path.join(ARCHIVE_DIR, "manifest.txt")
PROCESS_SCRIPT = "/home/user/process.sh"

EXPECTED_FILES = {
    "intro.md": {
        "original": "/home/user/drafts/networking/intro.md",
        "archived": "intro.z64"
    },
    "endpoints.md": {
        "original": "/home/user/drafts/api/v1/endpoints.md",
        "archived": "endpoints.z64"
    },
    "summary.md": {
        "original": "/home/user/drafts/summary.md",
        "archived": "summary.z64"
    }
}

EXPECTED_ENTRIES = {
    f"{paths['archived']}:{paths['original']}"
    for paths in EXPECTED_FILES.values()
}


def clear_outputs():
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    if os.path.lexists(MANIFEST_PATH):
        os.unlink(MANIFEST_PATH)
    for path in glob.glob(os.path.join(ARCHIVE_DIR, "*.z64")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)


def run_script(timeout=20):
    return subprocess.run(
        ["bash", PROCESS_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_process_script_actually_locks_manifest_writes_and_is_concurrent_safe():
    assert os.path.isfile(PROCESS_SCRIPT), f"Processing script {PROCESS_SCRIPT} is missing."

    flock_cmd = shutil.which("flock")
    assert flock_cmd is not None, "The system flock command is unavailable."
    flock_path = os.path.realpath(flock_cmd)
    real_flock = flock_path + ".verifier-real"
    marker = "/tmp/verifier-flock-called"
    proc = None

    if os.path.exists(real_flock):
        os.unlink(real_flock)
    if os.path.exists(marker):
        os.unlink(marker)

    clear_outputs()
    os.rename(flock_path, real_flock)
    try:
        with open(flock_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\n' \"$$\" >> {marker!r}\n")
            f.write("while :; do sleep 0.05; done\n")
        os.chmod(flock_path, 0o755)

        proc = subprocess.Popen(
            ["bash", PROCESS_SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(marker):
            if proc.poll() is not None:
                break
            time.sleep(0.05)

        assert os.path.exists(marker), (
            "Executing process.sh did not invoke the system flock command."
        )
        assert proc.poll() is None, "process.sh did not wait for flock to acquire its lock."

        # The flock replacement never acquires a lock or returns. A correctly
        # protected manifest write therefore cannot have happened yet.
        time.sleep(0.4)
        manifest_size = os.path.getsize(MANIFEST_PATH) if os.path.exists(MANIFEST_PATH) else 0
        assert manifest_size == 0, (
            "process.sh wrote manifest data while its flock operation was blocked; "
            "the manifest write is not protected by flock."
        )
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
        if os.path.exists(flock_path):
            os.unlink(flock_path)
        if os.path.exists(real_flock):
            os.rename(real_flock, flock_path)

    # Exercise multiple real instances simultaneously and require every append
    # to survive as one complete, valid manifest record.
    clear_outputs()
    instance_count = 8
    processes = [
        subprocess.Popen(
            ["bash", PROCESS_SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for _ in range(instance_count)
    ]
    failures = []
    for p in processes:
        try:
            stdout, stderr = p.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            p.kill()
            stdout, stderr = p.communicate()
            failures.append(f"timed out: {stderr}")
            continue
        if p.returncode != 0:
            failures.append(f"exit {p.returncode}: {stderr}")
    assert not failures, f"Concurrent process.sh instances failed: {failures}"
    assert os.path.isfile(MANIFEST_PATH), "Concurrent runs did not create manifest.txt."

    with open(MANIFEST_PATH, "r") as f:
        concurrent_lines = [line.rstrip("\n") for line in f]

    assert all(concurrent_lines), "Concurrent writes produced an empty/corrupt manifest line."
    expected_counts = Counter({entry: instance_count for entry in EXPECTED_ENTRIES})
    assert Counter(concurrent_lines) == expected_counts, (
        "Concurrent runs lost, duplicated, or corrupted manifest records. "
        f"Expected {expected_counts}, found {Counter(concurrent_lines)}"
    )

    # Re-establish the requested final state with one actual execution so the
    # original final-state assertions remain applicable.
    clear_outputs()
    result = run_script()
    assert result.returncode == 0, (
        f"process.sh failed when executed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_process_script_exists_and_uses_flock():
    assert os.path.isfile(PROCESS_SCRIPT), f"Processing script {PROCESS_SCRIPT} is missing."
    with open(PROCESS_SCRIPT, 'r') as f:
        content = f.read()
    assert "flock" in content, f"The script {PROCESS_SCRIPT} does not seem to use 'flock' as required."


def test_archive_directory_exists():
    assert os.path.isdir(ARCHIVE_DIR), f"Destination directory {ARCHIVE_DIR} does not exist."


def test_archived_files_exist_and_content_matches():
    for md_file, paths in EXPECTED_FILES.items():
        archived_path = os.path.join(ARCHIVE_DIR, paths["archived"])
        original_path = paths["original"]

        assert os.path.isfile(archived_path), f"Archived file {archived_path} is missing."
        assert os.path.isfile(original_path), f"Original file {original_path} is missing."

        with open(original_path, 'r') as f:
            original_content = f.read()

        with open(archived_path, 'r') as f:
            encoded_content = f.read()

        try:
            compressed_data = base64.b64decode(encoded_content)
            decompressed_content = zlib.decompress(compressed_data).decode('utf-8')
        except Exception as e:
            pytest.fail(f"Failed to decode/decompress {archived_path}: {e}")

        assert decompressed_content == original_content, f"Decompressed content of {archived_path} does not match original {original_path}."


def test_manifest_file_correct():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Manifest file should contain exactly 3 lines, found {len(lines)}."

    expected_entries = set()
    for paths in EXPECTED_FILES.values():
        expected_entries.add(f"{paths['archived']}:{paths['original']}")

    actual_entries = set(lines)

    assert actual_entries == expected_entries, f"Manifest entries do not match expected format and content. Expected: {expected_entries}, Found: {actual_entries}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
