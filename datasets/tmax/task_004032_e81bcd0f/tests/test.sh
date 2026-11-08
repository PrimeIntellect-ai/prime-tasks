#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import shutil
import struct
import subprocess
import uuid
import wave

import pytest


def run_pcm(program, samples, maa_threshold, zcr_threshold):
    payload = struct.pack("<" + "h" * len(samples), *samples)
    return subprocess.run(
        [program, str(maa_threshold), str(zcr_threshold)],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def features(samples):
    maa = sum(abs(x) for x in samples) / len(samples)
    crossings = sum(
        1 for a, b in zip(samples, samples[1:])
        if (a < 0 < b) or (b < 0 < a)
    )
    zcr = crossings / (len(samples) - 1) if len(samples) > 1 else 0.0
    return maa, zcr


def test_00_required_artifacts_and_tuning_script():
    required_files = [
        "/home/user/classifier.c",
        "/home/user/classifier",
        "/home/user/tune.sh",
        "/home/user/filter.sh",
        "/home/user/process_source.sh",
    ]
    for path in required_files:
        assert os.path.isfile(path), f"Missing required artifact: {path}"

    assert os.access("/home/user/classifier", os.X_OK), "classifier is not executable"
    with open("/home/user/classifier", "rb") as f:
        assert f.read(4) == b"\x7fELF", "classifier is not a compiled ELF executable"

    for script in ["/home/user/tune.sh", "/home/user/filter.sh", "/home/user/process_source.sh"]:
        subprocess.run(["bash", "-n", script], check=True, timeout=10)

    rebuilt = f"/tmp/classifier_rebuilt_{uuid.uuid4().hex}"
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/classifier.c", "-lm", "-o", rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    tune = subprocess.run(
        ["bash", "/home/user/tune.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert tune.returncode == 0, (
        "tune.sh did not complete successfully:\n"
        + tune.stdout.decode(errors="replace")
        + tune.stderr.decode(errors="replace")
    )


def test_01_classifier_feature_semantics_for_binary_and_source():
    rebuilt = f"/tmp/classifier_semantics_{uuid.uuid4().hex}"
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/classifier.c", "-lm", "-o", rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    cases = [
        [1000, -1000, 0, 1000, -1000, 0, 1000, 1000] * 100,
        [-32768, -200, 0, 200, 32767, 0, -300, 300] * 100,
        [1200] * 400 + [-1200] * 400,
    ]
    for program in ["/home/user/classifier", rebuilt]:
        for samples in cases:
            maa, zcr = features(samples)
            accepted = run_pcm(program, samples, maa - 1.0, zcr + 0.01)
            assert accepted.returncode == 0, (
                f"{program} rejected data satisfying both strict threshold conditions; "
                f"stderr={accepted.stderr!r}"
            )

            high_maa_threshold = run_pcm(program, samples, maa + 1.0, zcr + 0.01)
            assert high_maa_threshold.returncode == 1, (
                f"{program} did not reject when MAA was below the threshold"
            )

            low_zcr_threshold = run_pcm(program, samples, maa - 1.0, max(0.0, zcr - 0.01))
            assert low_zcr_threshold.returncode == 1, (
                f"{program} did not reject when ZCR was not below the threshold"
            )


def test_02_filter_uses_audio_content_not_corpus_pathnames():
    root = f"/tmp/audio_inputs_{uuid.uuid4().hex}"
    os.makedirs(root)
    rng = random.Random(918273)
    cases = []

    for i in range(8):
        amplitude = 3000 + 40 * i
        phase = i * 0.17
        samples = [
            int(amplitude * math.sin(2 * math.pi * 400 * n / 8000 + phase))
            for n in range(8000)
        ]
        cases.append((samples, 0))

    for i in range(8):
        local = random.Random(10000 + i)
        samples = [local.randint(-1000, 1000) for _ in range(8000)]
        cases.append((samples, 1))

    rng.shuffle(cases)
    for samples, expected in cases:
        path = os.path.join(root, uuid.uuid4().hex + ".pcm")
        with open(path, "wb") as f:
            f.write(struct.pack("<" + "h" * len(samples), *samples))
        result = subprocess.run(
            ["bash", "/home/user/filter.sh", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == expected, (
            f"filter returned {result.returncode}, expected {expected}, for a randomized "
            "pathname; classification must be based on audio features"
        )

    clean_probe = os.path.join(root, uuid.uuid4().hex + ".pcm")
    samples = [int(3141.5 * math.sin(2 * math.pi * 400 * n / 8000)) for n in range(8000)]
    with open(clean_probe, "wb") as f:
        f.write(struct.pack("<" + "h" * len(samples), *samples))

    moved = f"/home/user/.classifier_verifier_{uuid.uuid4().hex}"
    os.rename("/home/user/classifier", moved)
    try:
        result = subprocess.run(
            ["bash", "/home/user/filter.sh", clean_probe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode != 0, "filter.sh accepted input even when its required classifier was unavailable"
    finally:
        os.rename(moved, "/home/user/classifier")


def test_filter_clean_corpus():
    clean_dir = "/app/hidden_corpus/clean"
    files = glob.glob(os.path.join(clean_dir, "*"))
    assert files, f"No files found in {clean_dir}"

    failures = []
    for f in files:
        res = subprocess.run(["bash", "/home/user/filter.sh", f], capture_output=True)
        if res.returncode != 0:
            failures.append(os.path.basename(f))

    assert not failures, f"{len(failures)} of {len(files)} clean modified/rejected: {failures}"


def test_filter_evil_corpus():
    evil_dir = "/app/hidden_corpus/evil"
    files = glob.glob(os.path.join(evil_dir, "*"))
    assert files, f"No files found in {evil_dir}"

    failures = []
    for f in files:
        res = subprocess.run(["bash", "/home/user/filter.sh", f], capture_output=True)
        if res.returncode != 1:
            failures.append(os.path.basename(f))

    assert not failures, f"{len(failures)} of {len(files)} evil bypassed: {failures}"


def test_03_process_source_runs_filter_and_produces_exact_clean_audio():
    token = uuid.uuid4().hex
    backup = f"/home/user/.filter_verifier_{token}"
    log = f"/tmp/filter_calls_{token}"
    shutil.copy2("/home/user/filter.sh", backup)
    with open("/home/user/filter.sh", "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"printf '%s\\n' \"$1\" >> {log!r}\n")
        f.write(f"exec bash {backup!r} \"$@\"\n")
    os.chmod("/home/user/filter.sh", 0o755)

    output = "/home/user/processed_output.wav"
    if os.path.exists(output):
        os.remove(output)
    try:
        result = subprocess.run(
            ["bash", "/home/user/process_source.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, (
            "process_source.sh failed:\n"
            + result.stdout.decode(errors="replace")
            + result.stderr.decode(errors="replace")
        )
    finally:
        os.replace(backup, "/home/user/filter.sh")

    assert os.path.isfile(log), "process_source.sh never invoked /home/user/filter.sh"
    with open(log) as f:
        calls = [line.strip() for line in f if line.strip()]
    assert len(calls) == 10, f"Expected one filter invocation for each of 10 chunks, got {len(calls)}"

    with wave.open("/app/source.wav", "rb") as source:
        assert source.getnchannels() == 1
        assert source.getsampwidth() == 2
        assert source.getframerate() == 8000
        source_frames = source.readframes(source.getnframes())

    chunk_bytes = 8000 * 2
    chunks = [source_frames[i:i + chunk_bytes] for i in range(0, len(source_frames), chunk_bytes)]
    assert len(chunks) == 10 and all(len(c) == chunk_bytes for c in chunks)
    expected_frames = b"".join(chunks[::2])

    assert os.path.isfile(output), f"{output} does not exist"
    with wave.open(output, "rb") as produced:
        assert produced.getnchannels() == 1, "Output must be mono"
        assert produced.getsampwidth() == 2, "Output must use 16-bit samples"
        assert produced.getframerate() == 8000, "Output must use an 8000 Hz sample rate"
        actual_frames = produced.readframes(produced.getnframes())
    assert actual_frames == expected_frames, "processed_output.wav is not the ordered concatenation of clean source chunks"


def test_processed_output_exists():
    out_file = "/home/user/processed_output.wav"
    assert os.path.isfile(out_file), f"{out_file} does not exist. The integration script may not have run or failed."
    # Basic check for WAV header
    with open(out_file, "rb") as f:
        header = f.read(12)
        assert header.startswith(b"RIFF") and header.endswith(b"WAVE"), f"{out_file} is not a valid WAV file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
