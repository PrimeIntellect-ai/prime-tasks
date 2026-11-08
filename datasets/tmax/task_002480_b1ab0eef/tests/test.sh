#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/config_updater.c"
BASE = f"{HOME}/base_config.json"
TRANSCRIPT = f"{HOME}/transcript.txt"
UPDATED = f"{HOME}/updated_config.json"
DRIFT = f"{HOME}/drift.txt"
BINARY = "/tmp/verifier_config_updater"

ORIGINAL = {
    "max_retries": 3,
    "db_password": "old_password_123",
    "cache_size": 256,
    "listen_port": 80,
}
EXPECTED = {
    "max_retries": 5,
    "db_password": "***",
    "cache_size": 1024,
    "listen_port": 80,
}


def compact(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def assert_exact_config(actual, expected):
    assert actual == expected, f"Configuration mismatch: {actual!r} != {expected!r}"
    assert list(actual.keys()) == list(expected.keys()), "Configuration keys/order differ from the base configuration"
    for key, value in expected.items():
        assert type(actual[key]) is type(value), f"Wrong JSON type for {key}: {type(actual[key]).__name__}"


def read_and_validate_outputs(original, expected):
    assert os.path.isfile(UPDATED), f"Updated config file missing: {UPDATED}"
    try:
        with open(UPDATED, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except Exception as exc:
        pytest.fail(f"Failed to load {UPDATED} as JSON: {exc}")
    assert_exact_config(actual, expected)

    assert os.path.isfile(DRIFT), f"Drift file missing: {DRIFT}"
    with open(DRIFT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content, "Drift file is empty."
    assert re.fullmatch(r"[+-]?\d+", content), f"Drift file does not contain a valid integer: {content!r}"
    expected_distance = levenshtein(compact(original), compact(expected))
    assert int(content) == expected_distance, (
        f"Incorrect drift: got {content}, expected {expected_distance} from the two unformatted JSON strings"
    )


def compile_program():
    assert os.path.isfile(SOURCE), f"C source file missing: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, "C source file is empty"

    candidates = [
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY, "-lm"],
    ]
    cjson = f"{HOME}/cJSON.c"
    if os.path.isfile(cjson):
        candidates.append(["gcc", "-std=c11", "-O2", SOURCE, cjson, "-o", BINARY, "-lm"])
    candidates.extend([
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY, "-lcjson", "-lm"],
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY, "-ljson-c", "-lm"],
    ])

    errors = []
    for command in candidates:
        result = subprocess.run(command, cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode == 0:
            assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
            return
        errors.append(" ".join(command) + "\n" + result.stdout)
    pytest.fail("config_updater.c did not compile:\n" + "\n---\n".join(errors))


def run_program():
    for path in (UPDATED, DRIFT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [BINARY], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20,
    )
    assert result.returncode == 0, f"Compiled updater failed with code {result.returncode}:\n{result.stdout}"


@pytest.fixture(scope="session")
def executed_program():
    compile_program()
    run_program()
    return True


def test_transcript_exists_and_contains_spoken_update():
    assert os.path.isfile(TRANSCRIPT), f"Transcript file missing: {TRANSCRIPT}"
    with open(TRANSCRIPT, "r", encoding="utf-8") as f:
        text = f.read().strip().lower()
    assert text, "Transcript is empty"
    normalized = re.sub(r"[^a-z0-9]+", " ", text)
    assert "max retries" in normalized
    assert "db password" in normalized
    assert "cache size" in normalized
    assert "alpha bravo charlie" in normalized
    assert re.search(r"\b(?:5|five)\b", normalized)
    assert (re.search(r"\b1024\b", normalized) or "one thousand twenty four" in normalized)


def test_updated_config_similarity(executed_program):
    with open(UPDATED, "r", encoding="utf-8") as f:
        agent_data = json.load(f)
    assert_exact_config(agent_data, EXPECTED)


def test_drift_file_exists_and_integer(executed_program):
    read_and_validate_outputs(ORIGINAL, EXPECTED)


def test_compiled_program_uses_configuration_and_transcript(executed_program):
    with open(BASE, "rb") as f:
        saved_base = f.read()
    with open(TRANSCRIPT, "rb") as f:
        saved_transcript = f.read()

    variant_original = {
        "max_retries": 2,
        "db_password": "prior_value",
        "cache_size": 64,
        "listen_port": 81,
    }
    variant_expected = {
        "max_retries": 7,
        "db_password": "***",
        "cache_size": 2048,
        "listen_port": 81,
    }
    variant_transcript = (
        "System configuration update. Change max_retries to 7. "
        "Set db_password to delta echo. Update cache_size to 2048.\n"
    )

    try:
        with open(BASE, "w", encoding="utf-8") as f:
            f.write(compact(variant_original))
        with open(TRANSCRIPT, "w", encoding="utf-8") as f:
            f.write(variant_transcript)
        run_program()
        read_and_validate_outputs(variant_original, variant_expected)
    finally:
        with open(BASE, "wb") as f:
            f.write(saved_base)
        with open(TRANSCRIPT, "wb") as f:
            f.write(saved_transcript)
        run_program()

    read_and_validate_outputs(ORIGINAL, EXPECTED)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
