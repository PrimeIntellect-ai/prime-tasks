#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest


def test_part1_extractor_retry_bug():
    """Verify retries return exactly one correct record for every input item."""
    vendored_path = "/app/loctool-1.0.0"
    if vendored_path not in sys.path:
        sys.path.insert(0, vendored_path)

    try:
        from loctool.extractor import Extractor
    except ImportError:
        pytest.fail("Could not import loctool.extractor. Ensure the package is still intact.")

    os.environ["SIMULATE_FLAKE"] = "1"

    input_data = {
        f"key_{secrets.token_hex(6)}": f"value_{secrets.token_hex(8)}"
        for _ in range(3)
    }
    expected = [{"key": key, "value": value} for key, value in input_data.items()]

    extractor = Extractor()
    try:
        output = extractor.extract(input_data)
    except Exception as e:
        pytest.fail(f"Extractor.extract() raised an exception: {e}")

    assert len(output) == len(input_data), (
        f"Expected output length {len(input_data)}, but got {len(output)}. "
        "The retry logic might still be appending to the records list without clearing previous attempts."
    )
    assert output == expected, (
        "Extractor output must contain exactly one correctly formed record for each input item, "
        "in input iteration order."
    )
    assert len({record["key"] for record in output}) == len(input_data), (
        "Extractor output contains duplicate record keys after retry."
    )


def run_validator(script_path, source_file, target_file):
    return subprocess.run(
        ["python3", str(script_path), "--source", str(source_file), "--target", str(target_file)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_part2_quality_gate_adversarial_corpus():
    """Retain the original corpus assertions."""
    script_path = Path("/home/user/validate.py")
    assert script_path.exists(), f"Quality gate script missing: {script_path}"
    assert script_path.is_file(), f"Quality gate path is not a regular file: {script_path}"

    source_file = Path("/app/corpora/source.json")
    clean_dir = Path("/app/corpora/clean")
    evil_dir = Path("/app/corpora/evil")

    assert clean_dir.exists() and clean_dir.is_dir(), "Clean corpus directory missing."
    assert evil_dir.exists() and evil_dir.is_dir(), "Evil corpus directory missing."

    clean_files = list(clean_dir.glob("*.json"))
    evil_files = list(evil_dir.glob("*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    evil_bypassed = []

    for target_file in clean_files:
        result = run_validator(script_path, source_file, target_file)
        if result.returncode != 0:
            clean_failures.append(target_file.name)

    for target_file in evil_files:
        result = run_validator(script_path, source_file, target_file)
        if result.returncode == 0:
            evil_bypassed.append(target_file.name)

    error_msgs = []
    if clean_failures:
        error_msgs.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            f"{', '.join(clean_failures)}"
        )
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            f"{', '.join(evil_bypassed)}"
        )

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_part2_quality_gate_generated_cases():
    """Exercise validation on neutral, randomized paths and verifier-derived data."""
    script_path = Path("/home/user/validate.py")
    assert script_path.exists(), f"Quality gate script missing: {script_path}"
    assert script_path.is_file(), f"Quality gate path is not a regular file: {script_path}"

    key1, key2, key3 = [f"k_{secrets.token_hex(6)}" for _ in range(3)]
    placeholder1, placeholder2, placeholder3 = [
        f"p_{secrets.token_hex(5)}" for _ in range(3)
    ]

    source = {
        key1: f"Welcome {{{placeholder1}}} to {{{placeholder2}}}!",
        key2: "A message without placeholders",
        key3: f"There are {{{placeholder3}}} items.",
    }

    valid_reordered = {
        key3: f"Artículos: {{{placeholder3}}}",
        key2: "Texto traducido",
        key1: f"Aplicación {{{placeholder2}}}; usuario {{{placeholder1}}}",
    }
    valid_different_text = {
        key1: f"{{{placeholder1}}} / {{{placeholder2}}}",
        key2: "",
        key3: f"{{{placeholder3}}}",
    }
    missing_key = {key1: source[key1], key2: source[key2]}
    extra_key = dict(source, **{f"extra_{secrets.token_hex(5)}": "extra"})
    renamed_placeholder = dict(valid_reordered)
    renamed_placeholder[key1] = (
        f"Aplicación {{{placeholder2}}}; usuario {{wrong_{secrets.token_hex(4)}}}"
    )
    missing_placeholder = dict(valid_reordered)
    missing_placeholder[key1] = f"Solo {{{placeholder2}}}"
    extra_placeholder = dict(valid_reordered)
    extra_placeholder[key2] = f"Texto {{unexpected_{secrets.token_hex(4)}}}"
    non_string_translation = dict(valid_reordered)
    non_string_translation[key2] = 12345

    cases = [
        ("valid reordered translation", valid_reordered, True, False),
        ("valid minimal translation text", valid_different_text, True, False),
        ("missing key", missing_key, False, False),
        ("extra key", extra_key, False, False),
        ("renamed placeholder", renamed_placeholder, False, False),
        ("missing placeholder", missing_placeholder, False, False),
        ("extra placeholder", extra_placeholder, False, False),
        ("non-string translation", non_string_translation, False, False),
        ("malformed JSON", None, False, True),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"quality_gate_{secrets.token_hex(6)}_") as tmp:
        tmp_path = Path(tmp)
        source_path = tmp_path / f"input_{secrets.token_hex(6)}.json"
        target_path = tmp_path / f"output_{secrets.token_hex(6)}.json"
        source_path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")

        failures = []
        for description, target, should_accept, malformed in cases:
            if malformed:
                target_path.write_text('{"broken": ', encoding="utf-8")
            else:
                target_path.write_text(json.dumps(target, ensure_ascii=False), encoding="utf-8")

            result = run_validator(script_path, source_path, target_path)
            accepted = result.returncode == 0
            if accepted != should_accept:
                expected = "accept" if should_accept else "reject"
                failures.append(
                    f"{description}: expected {expected}, got exit status {result.returncode}"
                )

        assert not failures, "Generated quality-gate failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
