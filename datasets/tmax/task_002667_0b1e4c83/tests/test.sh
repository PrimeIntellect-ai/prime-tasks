#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import os
import secrets
import subprocess
import tempfile
import wave
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/sanitize_loc.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
AUDIO_PATH = "/app/localization/reference_sync.wav"
LANGUAGES = ("en", "es", "fr", "de")


def run_script(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def audio_timestamps():
    with wave.open(AUDIO_PATH, "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        rate = wav.getframerate()
        frames = wav.readframes(wav.getnframes())

    samples = [int.from_bytes(frames[i:i + 2], "little", signed=True)
               for i in range(0, len(frames), 2)]
    starts = []
    for nominal in (1.0, 3.0, 5.0):
        lo = int((nominal - 0.5) * rate)
        hi = min(len(samples), int((nominal + 0.5) * rate))
        onset = next((i for i in range(lo, hi) if abs(samples[i]) > 200), None)
        assert onset is not None, f"No spoken marker found near {nominal}s"
        starts.append(onset / rate)
    return starts


def expected_rows(input_rows):
    timestamps = audio_timestamps()
    output = []
    for row in input_rows:
        normalized_key = row["key"].lower().replace(" ", "_")
        aligned = timestamps[int(row["timestamp"])]
        for language in LANGUAGES:
            output.append((normalized_key, aligned, language, row[language]))
    return output


def assert_valid_output(result, input_rows):
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    text = result.stdout.decode("utf-8")
    reader = csv.DictReader(io.StringIO(text))
    assert reader.fieldnames == ["key", "timestamp", "language", "translation"]
    actual = list(reader)
    assert len(actual) == len(input_rows) * 4

    normalized_actual = []
    for row in actual:
        assert set(row) == {"key", "timestamp", "language", "translation"}
        assert row["language"] in LANGUAGES
        try:
            timestamp = float(row["timestamp"])
        except ValueError:
            pytest.fail(f"Non-numeric aligned timestamp: {row['timestamp']!r}")
        normalized_actual.append((row["key"], round(timestamp, 4), row["language"], row["translation"]))

    normalized_expected = [
        (key, round(timestamp, 4), language, translation)
        for key, timestamp, language, translation in expected_rows(input_rows)
    ]
    assert Counter(normalized_actual) == Counter(normalized_expected)


def read_input(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    assert clean_files, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = run_script(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert evil_files, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    bypassed_files = []
    for filepath in evil_files:
        result = run_script(filepath)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_files)}")


def test_clean_corpus_is_reshaped_and_aligned():
    for filepath in glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv")):
        assert_valid_output(run_script(filepath), read_input(filepath))


def test_randomized_valid_input_at_unclassified_path():
    token = secrets.token_hex(8)
    rows = [
        {
            "key": f"Menu Title {token}",
            "timestamp": "2",
            "en": f"English,{token}",
            "es": f"Español {token}",
            "fr": f"Français {token}",
            "de": f"Deutsch {token}",
        },
        {
            "key": f"SECOND Key {token}",
            "timestamp": "0",
            "en": f"E-{token}",
            "es": f"S-{token}",
            "fr": f"F-{token}",
            "de": f"D-{token}",
        },
    ]
    with tempfile.TemporaryDirectory(prefix="loc_hidden_") as directory:
        path = os.path.join(directory, f"submission_{secrets.token_hex(5)}.csv")
        write_csv(path, ["key", "timestamp", *LANGUAGES], rows)
        assert_valid_output(run_script(path), rows)


def test_randomized_invalid_inputs_at_same_unclassified_path_type():
    token = secrets.token_hex(8)
    base = {
        "key": f"Key {token}", "timestamp": "1",
        "en": f"en-{token}", "es": f"es-{token}",
        "fr": f"fr-{token}", "de": f"de-{token}",
    }
    cases = []

    xss = dict(base)
    xss["fr"] = f"<ScRiPt>alert('{token}')</sCrIpT>"
    cases.append((["key", "timestamp", *LANGUAGES], [xss]))

    handler = dict(base)
    handler["de"] = f'<img src=x OnLoAd="{token}">'
    cases.append((["key", "timestamp", *LANGUAGES], [handler]))

    blank = dict(base)
    blank["es"] = ""
    cases.append((["key", "timestamp", *LANGUAGES], [blank]))

    invalid_time = dict(base)
    invalid_time["timestamp"] = "1.5"
    cases.append((["key", "timestamp", *LANGUAGES], [invalid_time]))

    missing_column = {key: value for key, value in base.items() if key != "de"}
    cases.append((["key", "timestamp", "en", "es", "fr"], [missing_column]))

    with tempfile.TemporaryDirectory(prefix="loc_hidden_") as directory:
        for index, (fields, rows) in enumerate(cases):
            path = os.path.join(directory, f"case_{index}_{secrets.token_hex(4)}.csv")
            write_csv(path, fields, rows)
            result = run_script(path)
            assert result.returncode == 1, (
                f"Invalid randomized case {index} was accepted. stdout="
                f"{result.stdout.decode('utf-8', 'replace')!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
