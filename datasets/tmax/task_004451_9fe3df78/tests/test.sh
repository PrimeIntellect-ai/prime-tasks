#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile
import uuid
import wave
import zlib

import pytest

SCRIPT = "/home/user/backup_compressor.py"
LOG = "/home/user/filter.log"


def parse_archive(archive_path):
    archive_files = {}
    with open(archive_path, "rb") as f:
        header = f.read(8)
        assert header == b"MYBAK_v1", f"Invalid archive global header: {header}"

        while True:
            len_bytes = f.read(2)
            if not len_bytes:
                break

            assert len(len_bytes) == 2, "Unexpected EOF while reading path length"
            path_len = struct.unpack("<H", len_bytes)[0]

            rel_path_bytes = f.read(path_len)
            assert len(rel_path_bytes) == path_len, "Unexpected EOF while reading path"
            rel_path = rel_path_bytes.decode("utf-8")

            size_bytes = f.read(4)
            assert len(size_bytes) == 4, "Unexpected EOF while reading file size"
            file_size = struct.unpack("<I", size_bytes)[0]

            compressed_content = f.read(file_size)
            assert len(compressed_content) == file_size, "Unexpected EOF while reading compressed content"

            try:
                decompressed_content = zlib.decompress(compressed_content)
            except zlib.error as e:
                pytest.fail(f"Failed to decompress content for {rel_path}: {e}")

            archive_files[rel_path] = decompressed_content
    return archive_files


def test_archive_log_and_unseen_execution():
    archive_path = "/home/user/archive.mybak"
    log_path = LOG
    corpus_dir = "/app/corpus"
    clean_dir = os.path.join(corpus_dir, "clean")
    evil_dir = os.path.join(corpus_dir, "evil")

    assert os.path.isfile(archive_path), f"Archive file missing at {archive_path}"
    assert os.path.isfile(log_path), f"Log file missing at {log_path}"

    with open(log_path, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]

    log_dict = {}
    for line in log_lines:
        parts = line.split(",")
        if len(parts) >= 2:
            log_dict[parts[0]] = parts[1]

    archive_files = parse_archive(archive_path)

    clean_files = []
    for root, _, files in os.walk(clean_dir):
        for file in files:
            clean_files.append(os.path.relpath(os.path.join(root, file), corpus_dir))

    evil_files = []
    for root, _, files in os.walk(evil_dir):
        for file in files:
            evil_files.append(os.path.relpath(os.path.join(root, file), corpus_dir))

    evil_bypassed = []
    for evil in evil_files:
        if log_dict.get(evil) != "REJECTED":
            evil_bypassed.append(evil)
        elif evil in archive_files:
            evil_bypassed.append(evil)

    clean_failed = []
    for clean in clean_files:
        if log_dict.get(clean) != "ACCEPTED":
            clean_failed.append(clean)
        elif clean not in archive_files:
            clean_failed.append(clean)
        else:
            orig_path = os.path.join(corpus_dir, clean)
            with open(orig_path, "rb") as f:
                orig_content = f.read()
            if archive_files[clean] != orig_content:
                clean_failed.append(clean)

    if evil_bypassed or clean_failed:
        msg = []
        if evil_bypassed:
            msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(os.path.basename(f) for f in evil_bypassed)}")
        if clean_failed:
            msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(os.path.basename(f) for f in clean_failed)}")
        pytest.fail("; ".join(msg))

    # Exercise the required script on a fresh, mixed, recursively nested corpus.
    assert os.path.isfile(SCRIPT), f"Required script missing at {SCRIPT}"

    with wave.open("/app/reference_sample.wav", "rb") as ref:
        ref_channels = ref.getnchannels()
        ref_width = ref.getsampwidth()
        ref_rate = ref.getframerate()
        assert ref.getcomptype() == "NONE"

    def write_wav(path, channels, width, rate, frames=137):
        payload = os.urandom(frames * channels * width)
        with wave.open(path, "wb") as out:
            out.setnchannels(channels)
            out.setsampwidth(width)
            out.setframerate(rate)
            out.setcomptype("NONE", "not compressed")
            out.writeframes(payload)

    with tempfile.TemporaryDirectory(prefix="wav_unseen_") as td:
        input_dir = os.path.join(td, "input_" + uuid.uuid4().hex)
        nested = os.path.join(input_dir, "mixed_" + uuid.uuid4().hex, "deeper")
        os.makedirs(nested)

        names = {kind: uuid.uuid4().hex + ".wav" for kind in (
            "valid1", "valid2", "fake", "rate", "channels", "width", "truncated"
        )}
        paths = {
            "valid1": os.path.join(input_dir, names["valid1"]),
            "valid2": os.path.join(nested, names["valid2"]),
            "fake": os.path.join(nested, names["fake"]),
            "rate": os.path.join(input_dir, names["rate"]),
            "channels": os.path.join(nested, names["channels"]),
            "width": os.path.join(input_dir, names["width"]),
            "truncated": os.path.join(nested, names["truncated"]),
        }

        write_wav(paths["valid1"], ref_channels, ref_width, ref_rate)
        write_wav(paths["valid2"], ref_channels, ref_width, ref_rate)
        with open(paths["fake"], "wb") as f:
            f.write(b"not a RIFF/WAVE file")
        write_wav(paths["rate"], ref_channels, ref_width, ref_rate + 123)
        write_wav(paths["channels"], 2 if ref_channels != 2 else 1, ref_width, ref_rate)
        write_wav(paths["width"], ref_channels, 1 if ref_width != 1 else 2, ref_rate)
        write_wav(paths["truncated"], ref_channels, ref_width, ref_rate)
        with open(paths["truncated"], "rb+") as f:
            f.seek(0, os.SEEK_END)
            f.truncate(f.tell() - 7)

        output_path = os.path.join(td, "result_" + uuid.uuid4().hex + ".mybak")
        if os.path.exists(LOG):
            os.unlink(LOG)

        result = subprocess.run(
            ["python3", SCRIPT, input_dir, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed on unseen input: {result.stderr}"
        assert os.path.isfile(output_path), "Script did not create the requested unseen archive"
        assert os.path.isfile(LOG), "Script did not create /home/user/filter.log"

        expected_status = {}
        expected_content = {}
        for kind, path in paths.items():
            rel = os.path.relpath(path, input_dir)
            accepted = kind in ("valid1", "valid2")
            expected_status[rel] = "ACCEPTED" if accepted else "REJECTED"
            if accepted:
                with open(path, "rb") as f:
                    expected_content[rel] = f.read()

        actual_status = {}
        with open(LOG, "r", encoding="utf-8") as f:
            lines = [line.rstrip("\n") for line in f]
        assert len(lines) == len(expected_status), "Log must contain exactly one line per unseen input file"
        for line in lines:
            parts = line.split(",")
            assert len(parts) == 2, f"Malformed log line: {line!r}"
            rel, status = parts
            assert rel not in actual_status, f"Duplicate log entry for {rel}"
            assert status in ("ACCEPTED", "REJECTED"), f"Invalid log status for {rel}"
            actual_status[rel] = status
        assert actual_status == expected_status, "Incorrect validation decisions on unseen WAV files"

        unseen_archive = parse_archive(output_path)
        assert set(unseen_archive) == set(expected_content), "Unseen archive contains missing or rejected files"
        for rel, content in expected_content.items():
            assert unseen_archive[rel] == content, f"Archived content changed for {rel}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
