#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import json
import os
import stat
import struct
import subprocess
import time

VIDEO_PATH = "/app/experiment_record.mp4"
SCRIPT_PATH = "/home/user/archive_video.py"
ARCHIVE_PATH = "/home/user/dataset.archive"
MANIFEST_PATH = "/home/user/manifest.json"


def get_raw_frames():
    """Extract 50 frames (5 seconds at 10 fps) as raw grayscale bytes."""
    cmd = [
        "ffmpeg", "-y", "-i", VIDEO_PATH,
        "-t", "5", "-r", "10",
        "-pix_fmt", "gray", "-f", "image2pipe",
        "-vcodec", "rawvideo", "-"
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    if process.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {stderr.decode('utf-8', errors='replace')}")
    return stdout


def descendants(root_pid):
    result = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            if pid in result:
                continue
            try:
                with open(f"/proc/{pid}/status", "r") as f:
                    ppid = None
                    for line in f:
                        if line.startswith("PPid:"):
                            ppid = int(line.split()[1])
                            break
                if ppid in result:
                    result.add(pid)
                    changed = True
            except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
                pass
    return result


def has_waiting_lock(root_pid, inode):
    pids = descendants(root_pid)
    try:
        with open("/proc/locks", "r") as f:
            lines = f.readlines()
    except OSError:
        return False

    for line in lines:
        fields = line.split()
        if "->" not in fields or "WRITE" not in fields:
            continue
        try:
            write_index = fields.index("WRITE")
            pid = int(fields[write_index + 1])
            lock_inode = int(fields[write_index + 2].rsplit(":", 1)[1])
        except (ValueError, IndexError):
            continue
        if pid in pids and lock_inode == inode:
            return True
    return False


def run_script_and_verify_locking():
    for path in (ARCHIVE_PATH, MANIFEST_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Hold both common fcntl lock types on the archive. A compliant writer must
    # block before writing until this lock is released.
    lock_file = open(ARCHIVE_PATH, "w+b")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)

    process = subprocess.Popen(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    saw_waiter = False
    deadline = time.time() + 30
    try:
        while time.time() < deadline:
            if has_waiting_lock(process.pid, os.fstat(lock_file.fileno()).st_ino):
                saw_waiter = True
                break
            if process.poll() is not None:
                break
            time.sleep(0.05)
    finally:
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    if not saw_waiter:
        if process.poll() is None:
            process.terminate()
        stdout, stderr = process.communicate(timeout=10)
        raise AssertionError(
            "archive_video.py did not acquire a blocking fcntl lock on dataset.archive"
            f"\nstdout: {stdout.decode(errors='replace')}"
            f"\nstderr: {stderr.decode(errors='replace')}"
        )

    try:
        stdout, stderr = process.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
        raise AssertionError("archive_video.py timed out after the archive lock was released")

    assert process.returncode == 0, (
        f"archive_video.py exited with status {process.returncode}"
        f"\nstdout: {stdout.decode(errors='replace')}"
        f"\nstderr: {stderr.decode(errors='replace')}"
    )


def rle_matches(encoded, expected_mod, expected_signed):
    """Accept common packed binary (value,count) and (count,value) RLE layouts."""
    value_codes = ("B", "b", "h", "i")
    count_codes = ("B", "H", "I", "Q")
    prefixes = ("<", ">", "=", "@", "!")

    for prefix in prefixes:
        for value_code in value_codes:
            for count_code in count_codes:
                for value_first in (True, False):
                    body = value_code + count_code if value_first else count_code + value_code
                    fmt = prefix + body
                    record_size = struct.calcsize(fmt)
                    if record_size == 0 or len(encoded) % record_size != 0:
                        continue

                    # A byte-sized value represents modulo-256 byte differences;
                    # wider signed values may represent arithmetic differences.
                    modes = ("mod",) if value_code in ("B", "b") else ("signed", "mod")
                    for mode in modes:
                        pos = 0
                        valid = True
                        try:
                            records = struct.iter_unpack(fmt, encoded)
                            for record in records:
                                value, count = record if value_first else (record[1], record[0])
                                count = int(count)
                                if count <= 0 or pos + count > len(expected_mod):
                                    valid = False
                                    break

                                if mode == "mod":
                                    value = int(value) & 0xff
                                    if expected_mod[pos:pos + count] != bytes((value,)) * count:
                                        valid = False
                                        break
                                else:
                                    value = int(value)
                                    for j in range(pos, pos + count):
                                        if expected_signed[j] != value:
                                            valid = False
                                            break
                                    if not valid:
                                        break
                                pos += count
                        except struct.error:
                            valid = False

                        if valid and pos == len(expected_mod):
                            return True
    return False


def validate_compressed_chunk(compressed, expected_chunk, frame_size):
    assert len(compressed) >= frame_size, "Compressed chunk does not contain its first raw frame"
    assert compressed[:frame_size] == expected_chunk[:frame_size], (
        "Compressed chunk's first frame is not stored losslessly as raw bytes"
    )

    expected_mod = bytearray()
    expected_signed = []
    for frame_index in range(1, 10):
        previous = expected_chunk[(frame_index - 1) * frame_size:frame_index * frame_size]
        current = expected_chunk[frame_index * frame_size:(frame_index + 1) * frame_size]
        expected_mod.extend((cur - prev) & 0xff for cur, prev in zip(current, previous))
        expected_signed.extend(cur - prev for cur, prev in zip(current, previous))

    assert rle_matches(compressed[frame_size:], expected_mod, expected_signed), (
        "Chunk payload is not a valid lossless delta-plus-RLE encoding"
    )


def test_archive_and_manifest():
    assert os.path.exists(SCRIPT_PATH), f"Archiving script missing: {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), "archive_video.py must be a regular file"

    run_script_and_verify_locking()

    assert os.path.exists(ARCHIVE_PATH), f"Archive file missing: {ARCHIVE_PATH}"
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"
    assert stat.S_ISREG(os.stat(ARCHIVE_PATH).st_mode), "dataset.archive must be a regular file"

    with open(MANIFEST_PATH, "r") as f:
        manifest = json.load(f)

    assert len(manifest) == 5, "Manifest should contain exactly 5 chunks"

    raw_bytes = get_raw_frames()
    total_size = len(raw_bytes)
    assert total_size > 0, "Failed to extract raw frames"
    assert total_size % 50 == 0, "Extracted raw stream does not contain 50 equal-sized frames"

    frame_size = total_size // 50
    chunk_size = total_size // 5
    archive_size = os.path.getsize(ARCHIVE_PATH)

    expected_next_offset = 0
    with open(ARCHIVE_PATH, "rb") as archive:
        for i in range(5):
            chunk_key = str(i)
            assert chunk_key in manifest, f"Chunk {i} missing from manifest"
            entry = manifest[chunk_key]

            expected_chunk_bytes = raw_bytes[i * chunk_size:(i + 1) * chunk_size]
            expected_hash = hashlib.sha256(expected_chunk_bytes).hexdigest()

            assert entry["checksum"] == expected_hash, f"Checksum mismatch for chunk {i}"
            assert "offset" in entry, f"Offset missing for chunk {i}"
            assert "size" in entry, f"Size missing for chunk {i}"

            offset = entry["offset"]
            size = entry["size"]
            assert isinstance(offset, int) and not isinstance(offset, bool), f"Invalid offset for chunk {i}"
            assert isinstance(size, int) and not isinstance(size, bool), f"Invalid size for chunk {i}"
            assert offset == expected_next_offset, f"Chunk {i} is not appended at the expected offset"
            assert size > 0, f"Compressed size for chunk {i} must be positive"
            assert offset + size <= archive_size, f"Chunk {i} points outside dataset.archive"

            archive.seek(offset)
            compressed = archive.read(size)
            assert len(compressed) == size, f"Could not read the full compressed payload for chunk {i}"
            validate_compressed_chunk(compressed, expected_chunk_bytes, frame_size)
            expected_next_offset = offset + size

    assert expected_next_offset == archive_size, "Manifest does not describe the complete archive"

    max_allowed_size = total_size * 0.65
    assert archive_size <= max_allowed_size, (
        f"Archive size {archive_size} exceeds allowed limit {max_allowed_size}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
