#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

import pytest

SCRIPT_PATH = "/home/user/dataset_filter.py"
AUDIO_PATH = "/app/audio/lecture.wav"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Target script {SCRIPT_PATH} does not exist."


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, f"No files found in clean corpus {CLEAN_CORPUS_DIR}."

    failed_files = []
    for file_path in clean_files:
        if not os.path.isfile(file_path):
            continue

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, file_path],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if result.returncode != 0 or output != "ACCEPT":
            failed_files.append((os.path.basename(file_path), result.returncode, output))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out '{o}')" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {details}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(evil_files) > 0, f"No files found in evil corpus {EVIL_CORPUS_DIR}."

    failed_files = []
    for file_path in evil_files:
        if not os.path.isfile(file_path):
            continue

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, file_path],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if result.returncode != 1 or output != "REJECT":
            failed_files.append((os.path.basename(file_path), result.returncode, output))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out '{o}')" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed/accepted. Offending files: {details}")


def test_hidden_audio_and_random_paths_use_model_threshold():
    # Replace the recording temporarily with an unpredictable lecture so that a
    # filename lookup or hard-coded transcription cannot satisfy this test.
    speeches = [
        "Photosynthesis converts light energy into chemical energy inside plant chloroplasts. Chlorophyll absorbs light, and the reactions produce sugars from carbon dioxide and water.",
        "Plate tectonics describes the motion of rigid plates across the surface of Earth. Their collisions create mountain ranges, earthquakes, ocean trenches, and volcanic activity.",
        "In computer networks, packets are routed between machines using numerical addresses. Routers inspect destination addresses and forward each packet toward the appropriate next hop.",
        "The immune system recognizes pathogens using specialized cells and antibodies. Memory cells allow a faster response when the same pathogen is encountered again."
    ]
    unrelated = [
        "A pastry recipe combines flour, butter, sugar, and eggs before the dough is baked until golden brown.",
        "Ancient trade routes connected distant kingdoms and carried spices, textiles, metals, and cultural traditions.",
        "A jazz ensemble may improvise over changing chords while the drummer and bass player maintain the rhythm.",
        "Gardeners prune rose bushes, remove weeds, and improve the soil with compost before the spring growing season.",
        "The goalkeeper blocked a penalty kick during the final minutes of the championship football match."
    ]

    speech = secrets.choice(speeches)
    work_dir = tempfile.mkdtemp(prefix="semantic_inputs_")
    replacement_audio = os.path.join(work_dir, "reference.wav")
    backup_audio = os.path.join(work_dir, "original.wav")
    shutil.copy2(AUDIO_PATH, backup_audio)

    try:
        subprocess.run(
            ["espeak", "-w", replacement_audio, speech],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        shutil.copyfile(replacement_audio, AUDIO_PATH)

        try:
            import whisper
            from sentence_transformers import SentenceTransformer
        except Exception as exc:
            pytest.fail(f"Required semantic models are not installed and importable: {exc}")

        whisper_model = whisper.load_model("base")
        transcript = whisper_model.transcribe(AUDIO_PATH)["text"].strip()
        assert transcript, "Whisper produced an empty transcription for the hidden recording."

        embedding_model = SentenceTransformer("all-MiniLM-L6-v2")

        # Build previously unseen documents, including mixtures near the required
        # decision boundary. Expected answers are computed from the specified model.
        candidates = [transcript] + unrelated[:]
        for noise in unrelated:
            candidates.extend([
                transcript + " " + noise,
                transcript + " " + noise + " " + noise,
                speech + " " + noise,
                noise + " " + transcript,
                noise + " " + noise + " " + transcript,
            ])

        vectors = embedding_model.encode(
            [transcript] + candidates,
            normalize_embeddings=True
        )
        reference_vector = vectors[0]
        scored = []
        for text, vector in zip(candidates, vectors[1:]):
            similarity = float(reference_vector @ vector)
            scored.append((abs(similarity - 0.40), similarity, text))

        accepted = [item for item in scored if item[1] >= 0.40]
        rejected = [item for item in scored if item[1] < 0.40]
        assert accepted and rejected, "Hidden candidate generation did not cover both sides of the threshold."

        # Exercise the closest generated example on each side of 0.40.
        selected = [min(accepted), min(rejected)]
        failures = []
        for _, similarity, text in selected:
            path = os.path.join(work_dir, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

            expected_output = "ACCEPT" if similarity >= 0.40 else "REJECT"
            expected_code = 0 if similarity >= 0.40 else 1
            result = subprocess.run(
                [sys.executable, SCRIPT_PATH, path],
                capture_output=True,
                text=True,
                timeout=600
            )
            output = result.stdout.strip()
            if result.returncode != expected_code or output != expected_output:
                failures.append(
                    f"similarity {similarity:.6f}: expected {expected_output}/"
                    f"{expected_code}, got {output!r}/{result.returncode}"
                )

        if failures:
            pytest.fail("Hidden semantic checks failed: " + "; ".join(failures))
    finally:
        shutil.copyfile(backup_audio, AUDIO_PATH)
        shutil.rmtree(work_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
