#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

BINARY_PATH = "/home/user/audio-detector"
TRANSCRIPT_PATH = "/home/user/transcript.txt"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EXPECTED_TRANSCRIPT = "PROJECT OVERSEER HAS BEEN COMPROMISED WE NEED IMMEDIATE EVACUATION"


def test_binary_exists_and_executable():
    """Test that the compiled binary exists and is executable."""
    assert os.path.isfile(BINARY_PATH), f"Expected binary {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audio-detector must be a compiled executable, not a script."


def test_transcript_content():
    """Test that the transcript file exists and contains the correct text."""
    assert os.path.isfile(TRANSCRIPT_PATH), f"Expected transcript file {TRANSCRIPT_PATH} does not exist."

    with open(TRANSCRIPT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    clean_content = re.sub(r'[^A-Z0-9]', '', content.upper())
    clean_expected = re.sub(r'[^A-Z0-9]', '', EXPECTED_TRANSCRIPT.upper())

    assert clean_expected in clean_content, f"Transcript does not contain the expected text. Found: {content.strip()}"


def _wav_files(directory):
    return [os.path.join(directory, f) for f in os.listdir(directory) if f.endswith('.wav')]


def test_randomized_neutral_path_corpus():
    """Classify signal-preserving randomized variants without label-bearing paths."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus dir {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus dir {CLEAN_CORPUS_DIR} missing."
    evil_sources = _wav_files(EVIL_CORPUS_DIR)
    clean_sources = _wav_files(CLEAN_CORPUS_DIR)
    assert evil_sources, f"No evil files found in {EVIL_CORPUS_DIR}."
    assert clean_sources, f"No clean files found in {CLEAN_CORPUS_DIR}."

    rng = secrets.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="wav-check-")
    cases = []
    try:
        # Produce several independently transformed copies. Gain, resampling, and
        # leading silence preserve the underlying classification while defeating
        # pathname, byte-hash, and exact-waveform lookup implementations.
        for expected, sources in ((0, clean_sources), (1, evil_sources)):
            for _ in range(6):
                source = rng.choice(sources)
                output = os.path.join(workdir, secrets.token_hex(16) + ".wav")
                gain = rng.uniform(0.62, 1.28)
                rate = rng.choice((16000, 22050, 24000, 32000, 44100))
                delay = rng.randint(17, 173)
                filt = f"volume={gain:.6f},aresample={rate},adelay={delay}:all=1"
                made = subprocess.run(
                    ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", source,
                     "-af", filt, "-c:a", "pcm_s16le", output],
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=20)
                assert made.returncode == 0 and os.path.isfile(output), made.stderr.decode(errors="replace")
                cases.append((output, expected))

        rng.shuffle(cases)

        # Repeated parallel executions also expose nondeterministic/racy results.
        invocations = cases * 3
        rng.shuffle(invocations)

        def invoke(case):
            path, expected = case
            result = subprocess.run(
                [BINARY_PATH, path], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=20)
            return path, expected, result.returncode

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(invoke, invocations))

        failures = [(os.path.basename(p), expected, actual)
                    for p, expected, actual in results if actual != expected]
        assert not failures, f"Randomized neutral-path classifications failed: {failures}"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def test_adversarial_corpus():
    """Test that the binary correctly classifies clean and evil audio files."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus dir {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus dir {CLEAN_CORPUS_DIR} missing."

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.wav')]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.wav')]

    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}."
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}."

    evil_bypassed = []
    for f in evil_files:
        path = os.path.join(EVIL_CORPUS_DIR, f)
        result = subprocess.run([BINARY_PATH, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 1:
            evil_bypassed.append(f)

    clean_modified = []
    for f in clean_files:
        path = os.path.join(CLEAN_CORPUS_DIR, f)
        result = subprocess.run([BINARY_PATH, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
