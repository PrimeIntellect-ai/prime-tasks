#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import subprocess

SOURCE = "/app/audio/source.wav"
LOG = "/app/metadata/ingest.log"
CHUNKS = "/home/user/chunks"
CURATED = "/home/user/curated.wav"
MANIFEST = "/home/user/manifest.json"
TRANSCRIPT = "/home/user/transcript.txt"


def parse_log(log_path):
    valid_records = []
    with open(log_path, "r") as f:
        content = f.read()

    for record in content.split("---"):
        record = record.strip()
        if not record:
            continue
        fields = {}
        for line in record.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        if fields.get("Status") == "Valid" and fields.get("Record ID"):
            valid_records.append({
                "id": fields["Record ID"],
                "start": float(fields["Start Time"]),
                "end": float(fields["End Time"]),
            })
    return valid_records


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def probe_wav(path):
    assert os.path.isfile(path), f"Missing audio file: {path}"
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "format=format_name:stream=codec_type,sample_rate,channels",
         "-of", "json", path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"Unreadable audio file {path}: {result.stderr}"
    info = json.loads(result.stdout)
    formats = info.get("format", {}).get("format_name", "").split(",")
    assert "wav" in formats, f"{path} is not a WAV file"
    streams = [s for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    assert len(streams) == 1, f"{path} must contain exactly one audio stream"
    return int(streams[0]["sample_rate"]), int(streams[0]["channels"])


def decode_pcm(path, rate, channels):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-map", "0:a:0", "-vn",
         "-ar", str(rate), "-ac", str(channels), "-acodec", "pcm_s16le",
         "-f", "s16le", "pipe:1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"Could not decode {path}: {result.stderr.decode(errors='replace')}"
    frame_size = channels * 2
    assert len(result.stdout) % frame_size == 0, f"Invalid decoded audio length for {path}"
    return result.stdout


def frames(pcm, channels):
    return len(pcm) // (channels * 2)


def frame_slice(pcm, first, last, channels):
    size = channels * 2
    return pcm[first * size:last * size]


def test_chunks_and_manifest():
    assert os.path.exists(LOG), "Ingest log missing."
    valid_records = parse_log(LOG)

    assert os.path.exists(MANIFEST), "Manifest file missing."
    with open(MANIFEST, "r") as f:
        manifest = json.load(f)
    assert isinstance(manifest, dict), "Manifest must be a JSON dictionary."

    expected_names = {f"chunk_{record['id']}.wav" for record in valid_records}
    assert set(manifest) == expected_names, "Manifest must contain exactly the valid chunk filenames."

    for record in valid_records:
        chunk_filename = f"chunk_{record['id']}.wav"
        chunk_path = os.path.join(CHUNKS, chunk_filename)
        assert os.path.exists(chunk_path), f"Missing chunk file: {chunk_filename}"
        expected_hash = get_sha256(chunk_path)
        assert chunk_filename in manifest, f"{chunk_filename} missing from manifest."
        assert manifest[chunk_filename] == expected_hash, f"Hash mismatch for {chunk_filename}"


def test_chunk_audio_matches_source_intervals():
    valid_records = parse_log(LOG)
    source_rate, source_channels = probe_wav(SOURCE)
    source_pcm = decode_pcm(SOURCE, source_rate, source_channels)
    source_frames = frames(source_pcm, source_channels)

    # This covers normal floor/round differences and the millisecond precision of the log.
    tolerance = max(2, int(math.ceil(source_rate * 0.002)))

    for record in valid_records:
        path = os.path.join(CHUNKS, f"chunk_{record['id']}.wav")
        rate, channels = probe_wav(path)
        assert rate == source_rate, f"Wrong sample rate for chunk_{record['id']}.wav"
        assert channels == source_channels, f"Wrong channel count for chunk_{record['id']}.wav"

        actual = decode_pcm(path, source_rate, source_channels)
        actual_frames = frames(actual, source_channels)
        expected_start = round(record["start"] * source_rate)
        expected_end = round(record["end"] * source_rate)
        expected_frames = expected_end - expected_start
        assert abs(actual_frames - expected_frames) <= tolerance, \
            f"Wrong duration for chunk_{record['id']}.wav"

        margin = min(tolerance, max(0, actual_frames // 4))
        compare_count = actual_frames - 2 * margin
        assert compare_count > 0, f"chunk_{record['id']}.wav has no usable audio"
        actual_core = frame_slice(actual, margin, margin + compare_count, source_channels)

        matched = False
        for candidate_start in range(expected_start - tolerance, expected_start + tolerance + 1):
            source_core_start = candidate_start + margin
            source_core_end = source_core_start + compare_count
            if source_core_start < 0 or source_core_end > source_frames:
                continue
            if actual_core == frame_slice(source_pcm, source_core_start, source_core_end, source_channels):
                matched = True
                break
        assert matched, f"chunk_{record['id']}.wav does not contain its specified source interval"


def test_curated_audio():
    assert os.path.exists(CURATED), "Merged audio file /home/user/curated.wav is missing."
    assert os.path.getsize(CURATED) > 0, "Merged audio file is empty."

    source_rate, source_channels = probe_wav(SOURCE)
    curated_rate, curated_channels = probe_wav(CURATED)
    assert curated_rate == source_rate, "Curated audio has the wrong sample rate."
    assert curated_channels == source_channels, "Curated audio has the wrong channel count."

    ordered_chunk_audio = []
    for record in parse_log(LOG):
        path = os.path.join(CHUNKS, f"chunk_{record['id']}.wav")
        ordered_chunk_audio.append(decode_pcm(path, source_rate, source_channels))
    expected_curated = b"".join(ordered_chunk_audio)
    actual_curated = decode_pcm(CURATED, source_rate, source_channels)
    assert actual_curated == expected_curated, \
        "Curated audio is not the valid chunks merged in exact log order."


def word_error_rate(reference, hypothesis):
    ref = re.findall(r"[a-z0-9']+", reference.lower())
    hyp = re.findall(r"[a-z0-9']+", hypothesis.lower())
    previous = list(range(len(hyp) + 1))
    for i, ref_word in enumerate(ref, 1):
        current = [i]
        for j, hyp_word in enumerate(hyp, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ref_word != hyp_word),
            ))
        previous = current
    return previous[-1] / len(ref)


def test_transcript():
    assert os.path.exists(TRANSCRIPT), "Transcript file missing."
    with open(TRANSCRIPT, "r") as f:
        content = f.read()

    assert len(content.strip()) > 0, "Transcript is empty."
    assert "\n" not in content.strip("\n"), "Transcript should be a single line with no line breaks."

    reference = "The quick brown fox jumps over the lazy dog and then it rained"
    assert word_error_rate(reference, content) <= 0.30, \
        "Transcript word error rate exceeds the allowed threshold."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
