#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid


def run_validator(script_path, file_path):
    return subprocess.run(
        [script_path, file_path],
        capture_output=True,
        timeout=10,
    )


def expected_status(record):
    missing = object()
    speaker = record.get("speaker", missing)
    if speaker is missing or speaker is None or speaker == "":
        return 1

    duration = record.get("duration", missing)
    if (
        duration is missing
        or isinstance(duration, bool)
        or not isinstance(duration, (int, float))
        or duration < 1.0
        or duration > 100.0
    ):
        return 1

    transcript = record.get("transcript", "")
    if isinstance(transcript, str):
        lowered = transcript.lower()
        if "thank you for watching" in lowered or "subtitles by" in lowered:
            return 1

    return 0


def random_case(text, rng):
    return "".join(c.upper() if rng.choice((True, False)) else c.lower() for c in text)


def test_audio_duration_extracted():
    """Verify that the audio duration was correctly extracted and saved."""
    duration_file = "/home/user/audio_duration.txt"
    audio_file = "/app/interview.wav"

    assert os.path.isfile(duration_file), f"Duration file is missing at {duration_file}"

    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        audio_file,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    expected_duration = result.stdout.strip()

    with open(duration_file, "r") as f:
        actual_duration = f.read().strip()

    assert actual_duration == expected_duration, (
        f"Expected duration {expected_duration}, but got {actual_duration} in {duration_file}"
    )


def test_script_exists_and_executable():
    """Verify that the validate_record.sh script exists and is executable."""
    script_path = "/home/user/validate_record.sh"
    assert os.path.isfile(script_path), f"Script is missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_adversarial_corpus():
    """Retain the checks against the supplied clean and evil corpus."""
    script_path = "/home/user/validate_record.sh"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]

    clean_failures = []
    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        result = run_validator(script_path, file_path)
        if result.returncode != 0:
            clean_failures.append(f)

    evil_failures = []
    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        result = run_validator(script_path, file_path)
        if result.returncode == 0:
            evil_failures.append(f)

    errors = []
    if clean_failures:
        errors.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified "
            f"(failed to return 0): {', '.join(clean_failures)}"
        )
    if evil_failures:
        errors.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed "
            f"(failed to return non-zero): {', '.join(evil_failures)}"
        )

    assert not errors, " | ".join(errors)


def test_generated_records_against_independent_rules():
    """Exercise newly generated, neutrally named records and derive their answers."""
    script_path = "/home/user/validate_record.sh"
    rng = random.SystemRandom()

    records = [
        {"speaker": "Boundary One", "duration": 1.0, "transcript": "ordinary text"},
        {"speaker": "Boundary Hundred", "duration": 100.0, "transcript": "ordinary text"},
        {"speaker": "A", "duration": 0.999999, "transcript": "ordinary text"},
        {"speaker": "A", "duration": 100.000001, "transcript": "ordinary text"},
        {"duration": 50, "transcript": "ordinary text"},
        {"speaker": "", "duration": 50, "transcript": "ordinary text"},
        {"speaker": None, "duration": 50, "transcript": "ordinary text"},
        {"speaker": "A", "transcript": "ordinary text"},
        {"speaker": "A", "duration": "50", "transcript": "ordinary text"},
        {"speaker": "A", "duration": None, "transcript": "ordinary text"},
        {"speaker": "A", "duration": True, "transcript": "ordinary text"},
        {"speaker": "A", "duration": 50, "transcript": "prefix THANK YOU FOR WATCHING suffix"},
        {"speaker": "A", "duration": 50, "transcript": "prefix SubTitles By someone"},
        {"speaker": "A", "duration": 50, "transcript": "thank you for watchin"},
        {"speaker": "A", "duration": 50, "transcript": "subtitle by someone"},
    ]

    modes = [
        "clean", "clean", "clean", "missing_speaker", "empty_speaker",
        "null_speaker", "low_duration", "high_duration", "string_duration",
        "null_duration", "missing_duration", "spam_thanks", "spam_subtitles",
    ]

    for _ in range(120):
        token = uuid.uuid4().hex
        record = {
            "speaker": "speaker-" + token,
            "duration": rng.uniform(1.0, 100.0),
            "transcript": "record " + token + " contains normal conversation",
        }
        mode = rng.choice(modes)
        if mode == "missing_speaker":
            del record["speaker"]
        elif mode == "empty_speaker":
            record["speaker"] = ""
        elif mode == "null_speaker":
            record["speaker"] = None
        elif mode == "low_duration":
            record["duration"] = rng.uniform(-1000.0, 0.999999)
        elif mode == "high_duration":
            record["duration"] = rng.uniform(100.000001, 1000.0)
        elif mode == "string_duration":
            record["duration"] = str(rng.uniform(1.0, 100.0))
        elif mode == "null_duration":
            record["duration"] = None
        elif mode == "missing_duration":
            del record["duration"]
        elif mode == "spam_thanks":
            record["transcript"] = token + " " + random_case("Thank you for watching", rng) + " end"
        elif mode == "spam_subtitles":
            record["transcript"] = token + " " + random_case("Subtitles by", rng) + " person"
        records.append(record)

    test_dir = tempfile.mkdtemp(prefix=".records-", dir="/home/user")
    failures = []
    try:
        for record in records:
            file_path = os.path.join(test_dir, uuid.uuid4().hex + ".json")
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(record, f)

            expected = expected_status(record)
            result = run_validator(script_path, file_path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(file_path)} expected exit {expected}, got {result.returncode}"
                )
            if result.stdout or result.stderr:
                failures.append(
                    f"{os.path.basename(file_path)} produced output; stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
    finally:
        for name in os.listdir(test_dir):
            os.unlink(os.path.join(test_dir, name))
        os.rmdir(test_dir)

    assert not failures, " | ".join(failures[:20])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
