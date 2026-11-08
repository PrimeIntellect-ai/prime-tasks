#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile
import uuid
import wave

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.c"
CLEAN_CORPUS_PATH = "/app/corpus/clean"
EVIL_CORPUS_PATH = "/app/corpus/evil"
WHISPER_ROOT = "/app/whisper.cpp"
INVOCATION_LOG = "/tmp/fake_whisper_invocations.log"

FAKE_WHISPER = r'''#!/usr/bin/env python3
import os
import sys
import wave

LOG = "/tmp/fake_whisper_invocations.log"
with open(LOG, "a") as log:
    log.write("invoked\n")

wav_path = None
for arg in sys.argv[1:]:
    candidate = arg.split("=", 1)[-1]
    if candidate.lower().endswith(".wav") and os.path.isfile(candidate):
        wav_path = candidate

if wav_path is None:
    sys.exit(2)

is_evil = False
try:
    with wave.open(wav_path, "rb") as w:
        frames = w.readframes(min(32, w.getnframes()))
        if w.getsampwidth() == 2 and len(frames) >= 2:
            first = int.from_bytes(frames[:2], "little", signed=True)
            is_evil = first > 0
except Exception:
    pass

# Preserve the original corpus assertions despite the originally supplied WAVs
# all being silence. Hidden tests below use content markers and neutral paths.
normalized = os.path.abspath(wav_path)
if normalized.startswith("/app/corpus/evil/"):
    is_evil = True
elif normalized.startswith("/app/corpus/clean/"):
    is_evil = False

# ASCII sum of aaaa1 is 437, which has positive weight in model_weights.csv.
transcript = "aaaa1" if is_evil else "hello"
print(transcript)

outputs = set()
args = sys.argv[1:]
for i, arg in enumerate(args):
    if arg in ("-of", "--output-file") and i + 1 < len(args):
        outputs.add(args[i + 1] + ".txt")
    elif arg.startswith("--output-file="):
        outputs.add(arg.split("=", 1)[1] + ".txt")
outputs.add(wav_path + ".txt")
outputs.add(os.path.splitext(wav_path)[0] + ".txt")
for output in outputs:
    try:
        with open(output, "w") as f:
            f.write(transcript + "\n")
    except OSError:
        pass
'''


def invocation_count():
    try:
        with open(INVOCATION_LOG) as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0


def run_detector(path):
    before = invocation_count()
    result = subprocess.run(
        [DETECTOR_PATH, os.path.abspath(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    after = invocation_count()
    assert after > before, "Detector did not invoke the supplied whisper.cpp command-line tool"
    return result


def write_marked_wav(path, evil):
    marker = 12000 if evil else -12000
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        samples = [marker]
        samples.extend((300 if i % 2 else -300) for i in range(1599))
        payload = b"".join(int(x).to_bytes(2, "little", signed=True) for x in samples)
        w.writeframes(payload)


@pytest.fixture(scope="module", autouse=True)
def controlled_whisper():
    os.makedirs(WHISPER_ROOT, exist_ok=True)
    candidates = {
        os.path.join(WHISPER_ROOT, "main"),
        os.path.join(WHISPER_ROOT, "build", "bin", "main"),
        os.path.join(WHISPER_ROOT, "build", "bin", "whisper-cli"),
    }
    for root, dirs, files in os.walk(WHISPER_ROOT):
        for name in files:
            if name in {"main", "whisper", "whisper-cli"}:
                path = os.path.join(root, name)
                if os.access(path, os.X_OK):
                    candidates.add(path)

    saved = {}
    created = []
    for path in candidates:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            created.append(path)
        with open(path, "w") as f:
            f.write(FAKE_WHISPER)
        os.chmod(path, 0o755)

    try:
        if os.path.exists(INVOCATION_LOG):
            os.remove(INVOCATION_LOG)
        yield
    finally:
        for path, (data, mode) in saved.items():
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)
        for path in created:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_detector_executable_exists():
    assert os.path.isfile(SOURCE_PATH), f"C source missing at {SOURCE_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"Detector executable missing at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled native executable"


def test_adversarial_corpus():
    if not os.path.isfile(DETECTOR_PATH) or not os.access(DETECTOR_PATH, os.X_OK):
        pytest.fail(f"Detector executable not found or not executable at {DETECTOR_PATH}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_PATH) if f.endswith(".wav")]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_PATH) if f.endswith(".wav")]

    assert len(clean_files) > 0, f"No WAV files found in {CLEAN_CORPUS_PATH}"
    assert len(evil_files) > 0, f"No WAV files found in {EVIL_CORPUS_PATH}"

    clean_modified = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_PATH, f)
        if run_detector(filepath).returncode != 0:
            clean_modified.append(f)

    evil_bypassed = []
    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS_PATH, f)
        if run_detector(filepath).returncode != 1:
            evil_bypassed.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_neutral_randomized_paths_use_transcription_and_model():
    with tempfile.TemporaryDirectory(prefix="audio_inputs_") as directory:
        cases = [False, True] * 6
        random.SystemRandom().shuffle(cases)
        files = []
        for evil in cases:
            # Names and directory contain no class label; the fake whisper tool
            # derives its transcript from WAV content.
            path = os.path.join(directory, uuid.uuid4().hex + ".wav")
            write_marked_wav(path, evil)
            files.append((path, evil))

        random.SystemRandom().shuffle(files)
        for path, evil in files:
            result = run_detector(path)
            expected = 1 if evil else 0
            assert result.returncode == expected, (
                f"Wrong classification for neutral-path input {os.path.basename(path)}: "
                f"expected exit {expected}, got {result.returncode}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
