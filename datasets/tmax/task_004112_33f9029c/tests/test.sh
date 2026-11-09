#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest
from collections import defaultdict

def test_f1_score_and_extraction():
    expected_safe_files = {
        "log1.txt": "data1",
        "log1-copy.txt": "data1",
        "config/settings.ini": "data2",
        "users.db": "data3"
    }

    extracted_dir = "/home/user/recovered_files"
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist. The archive was not extracted to the correct location."

    true_positives = 0
    false_positives = 0

    for root, _, files in os.walk(extracted_dir):
        for file in files:
            rel_path = os.path.relpath(os.path.join(root, file), extracted_dir)
            if rel_path in expected_safe_files:
                try:
                    with open(os.path.join(root, file), "r") as f:
                        if f.read() == expected_safe_files[rel_path]:
                            true_positives += 1
                        else:
                            false_positives += 1
                except Exception:
                    false_positives += 1
            else:
                false_positives += 1

    false_negatives = len(expected_safe_files) - true_positives

    if (true_positives + false_positives) == 0:
        precision = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)

    if (true_positives + false_negatives) == 0:
        recall = 0.0
    else:
        recall = true_positives / (true_positives + false_negatives)

    if (precision + recall) == 0:
        f1 = 0.0
    else:
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.99, f"F1 Score: {f1:.4f} is below the threshold of 0.99 (TP: {true_positives}, FP: {false_positives}, FN: {false_negatives}). Zip-slip mitigation or extraction failed."

def test_hard_links_for_duplicates():
    extracted_dir = "/home/user/recovered_files"
    if not os.path.isdir(extracted_dir):
        pytest.fail(f"Directory {extracted_dir} does not exist.")

    content_to_inodes = defaultdict(set)

    for root, _, files in os.walk(extracted_dir):
        for file in files:
            filepath = os.path.join(root, file)
            if os.path.isfile(filepath) and not os.path.islink(filepath):
                try:
                    with open(filepath, "rb") as f:
                        content = f.read()
                    stat = os.stat(filepath)
                    content_to_inodes[content].add((stat.st_dev, stat.st_ino))
                except Exception:
                    pass

    for content, inodes in content_to_inodes.items():
        assert len(inodes) == 1, f"Found multiple inodes {inodes} for identical file content. Duplicates were not properly replaced with hard links."

def test_fixed_traversal_targets_were_not_written():
    targets = {
        "/home/user/etc/passwd": b"malicious1",
        "/shadow": b"malicious2",
        "/root/.bashrc": b"malicious3",
    }
    for path, payload in targets.items():
        if os.path.isfile(path):
            with open(path, "rb") as f:
                assert f.read() != payload, f"Traversal entry was extracted outside recovered_files: {path}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_extractor.py
import json
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

WAL = "/home/user/corrupt_backup.wal"
OUT = "/home/user/recovered_files"
VIDEO = "/app/incident.mp4"


def recover_video_key():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", VIDEO],
        check=True, stdout=subprocess.PIPE, text=True
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO, "-vsync", "0",
         "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        check=True, stdout=subprocess.PIPE
    ).stdout
    frame_size = width * height
    assert frame_size and len(raw) % frame_size == 0
    bits = []
    for offset in range(0, len(raw), frame_size):
        frame = raw[offset:offset + frame_size]
        bits.append(1 if sum(frame) / len(frame) > 100 else 0)
    assert bits and len(bits) % 8 == 0
    return bytes(sum(bits[i + j] << (7 - j) for j in range(8))
                 for i in range(0, len(bits), 8))


def make_archive(entries, key):
    plain = bytearray()
    for path, data in entries:
        encoded = path.encode("ascii")
        plain += struct.pack("<H", len(encoded))
        plain += encoded
        plain += struct.pack("<I", len(data))
        plain += data
    return bytes(value ^ key[i % len(key)] for i, value in enumerate(plain))


def source_candidates():
    found = []
    for base in ("/home/user", "/app", "/root", "/workspace"):
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            if os.path.abspath(root).startswith(os.path.abspath(OUT) + os.sep):
                dirs[:] = []
                continue
            for name in files:
                if name.endswith(".c"):
                    found.append(os.path.join(root, name))
    found = sorted(set(found))
    assert found, "No C source file was left for the required archive extractor."

    builds = [(path,) for path in found]
    by_dir = {}
    for path in found:
        by_dir.setdefault(os.path.dirname(path), []).append(path)
    for paths in by_dir.values():
        if len(paths) > 1:
            builds.append(tuple(sorted(paths)))
    return builds[:24]


def output_is_correct(expected, expected_dirs):
    if not os.path.isdir(OUT):
        return False
    actual_files = {}
    actual_dirs = set()
    for root, dirs, files in os.walk(OUT, followlinks=False):
        for name in dirs:
            path = os.path.join(root, name)
            if os.path.islink(path):
                return False
            actual_dirs.add(os.path.relpath(path, OUT))
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, OUT)
            if os.path.islink(path) or not os.path.isfile(path):
                return False
            with open(path, "rb") as f:
                actual_files[rel] = f.read()
    return actual_files == expected and actual_dirs == expected_dirs


key = recover_video_key()
assert key, "The video did not yield a key."
nonce = secrets.token_hex(8)
expected = {
    f"safe-{nonce}.bin": os.urandom(37),
    f"nested-{nonce}/first.dat": os.urandom(23),
    f"nested-{nonce}/second.dat": b"binary-data\\x00\\xff" + os.urandom(11),
}
expected_dirs = {f"nested-{nonce}"}
probes = [
    f"/home/user/escape-{nonce}",
    f"/root-escape-{nonce}",
    f"/tmp/absolute-escape-{nonce}",
]
entries = list(expected.items()) + [
    (f"../escape-{nonce}", b"TRAVERSAL-ONE-" + nonce.encode()),
    (f"../../../root-escape-{nonce}", b"TRAVERSAL-TWO-" + nonce.encode()),
    (f"/tmp/absolute-escape-{nonce}", b"TRAVERSAL-THREE-" + nonce.encode()),
    (f"dir/../sneaky-{nonce}", b"TRAVERSAL-FOUR-" + nonce.encode()),
]
encrypted = make_archive(entries, key)

backup_root = tempfile.mkdtemp(prefix="verifier-backup-")
backup_out = os.path.join(backup_root, "recovered_files")
original_wal = open(WAL, "rb").read()
if os.path.lexists(OUT):
    shutil.copytree(OUT, backup_out, symlinks=True)

success = False
errors = []
try:
    for build_no, sources in enumerate(source_candidates()):
        binary = os.path.join(backup_root, f"extractor-{build_no}")
        compiled = subprocess.run(
            ["gcc", "-O2", "-std=c11", *sources, "-o", binary],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if compiled.returncode != 0:
            errors.append(f"compile failed for {sources}: {compiled.stderr[-300:]}")
            continue

        invocations = [
            [binary],
            [binary, key.decode("ascii")],
            [binary, WAL, OUT, key.decode("ascii")],
            [binary, WAL, key.decode("ascii"), OUT],
        ]
        for command in invocations:
            if os.path.lexists(OUT):
                shutil.rmtree(OUT)
            for probe in probes:
                if os.path.lexists(probe):
                    if os.path.isdir(probe) and not os.path.islink(probe):
                        shutil.rmtree(probe)
                    else:
                        os.unlink(probe)
            with open(WAL, "wb") as f:
                f.write(encrypted)

            env = os.environ.copy()
            env.update({
                "RECOVERY_KEY": key.decode("ascii"),
                "WAL_KEY": key.decode("ascii"),
                "WAL_FILE": WAL,
                "OUTPUT_DIR": OUT,
            })
            try:
                subprocess.run(command, cwd=os.path.dirname(sources[0]), env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=8)
            except subprocess.TimeoutExpired:
                errors.append(f"timed out: {command}")
                continue

            escaped = [path for path in probes if os.path.lexists(path)]
            sneaky = os.path.join(OUT, f"sneaky-{nonce}")
            if not escaped and not os.path.lexists(sneaky) and output_is_correct(expected, expected_dirs):
                success = True
                break
        if success:
            break

    assert success, "No submitted C extractor safely handled a fresh derived fixture. " + " | ".join(errors[-3:])
finally:
    with open(WAL, "wb") as f:
        f.write(original_wal)
    if os.path.lexists(OUT):
        shutil.rmtree(OUT)
    if os.path.isdir(backup_out):
        shutil.copytree(backup_out, OUT, symlinks=True)
    for probe in probes:
        if os.path.lexists(probe):
            if os.path.isdir(probe) and not os.path.islink(probe):
                shutil.rmtree(probe)
            else:
                os.unlink(probe)
    shutil.rmtree(backup_root, ignore_errors=True)
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_dynamic_extractor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
