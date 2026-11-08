#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import subprocess
import tarfile
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/app/verify_config.py"


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=15,
    ).returncode


def find_allowed_keys(blob):
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                continue
            data = extracted.read()
            if os.path.basename(member.name) == "allowed_keys.csv":
                rows = list(csv.reader(io.StringIO(data.decode("utf-8"))))
                assert rows and rows[0], "The allowed-key CSV is empty."
                return set(rows[0])
            try:
                nested_result = find_allowed_keys(data)
            except (tarfile.TarError, EOFError, ValueError):
                nested_result = None
            if nested_result is not None:
                return nested_result
    return None


def derive_rules():
    with open("/app/config_templates.tar.gz", "rb") as archive_file:
        allowed_keys = find_allowed_keys(archive_file.read())
    assert allowed_keys is not None, "Could not find allowed_keys.csv in the nested archive."

    result = subprocess.run(
        ["tesseract", "/app/policy.png", "stdout"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    environment_id = result.stdout.strip()
    assert environment_id, "OCR produced an empty environment_id."
    assert "environment_id" in allowed_keys
    return allowed_keys, environment_id


def test_verify_config_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "The script /app/verify_config.py does not exist."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)]
    real_4 = os.path.join(evil_dir, "real_4.json")
    evil_files = [
        os.path.join(evil_dir, f)
        for f in os.listdir(evil_dir)
        if f != "real_4.json"
    ]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."
    assert os.path.isfile(real_4) and not os.path.islink(real_4)

    failed_clean = []
    for clean_file in clean_files + [real_4]:
        if run_validator(clean_file) != 0:
            failed_clean.append(os.path.basename(clean_file))

    failed_evil = []
    for evil_file in evil_files:
        if run_validator(evil_file) != 1:
            failed_evil.append(os.path.basename(evil_file))

    errors = []
    if failed_clean:
        errors.append(
            f"{len(failed_clean)} of {len(clean_files) + 1} clean modified/rejected: "
            + ", ".join(failed_clean)
        )
    if failed_evil:
        errors.append(
            f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: "
            + ", ".join(failed_evil)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_cases_at_one_unpredictable_path():
    allowed_keys, required_environment = derive_rules()

    with tempfile.TemporaryDirectory(prefix="config-check-") as directory:
        candidate = os.path.join(directory, uuid.uuid4().hex)
        target = os.path.join(directory, uuid.uuid4().hex)

        full_config = {key: {"generated": [1, True, None]} for key in allowed_keys}
        full_config["environment_id"] = required_environment
        other_allowed = next((key for key in allowed_keys if key != "environment_id"), None)
        missing_environment = {other_allowed: "value"} if other_allowed else {}
        extra_key = "not_allowed_" + uuid.uuid4().hex

        cases = [
            ("valid minimal object", {"environment_id": required_environment}, 0),
            ("valid object with every allowed key", full_config, 0),
            ("missing environment_id", missing_environment, 1),
            (
                "wrong environment_id",
                {"environment_id": required_environment + "-WRONG"},
                1,
            ),
            (
                "unlisted key",
                {"environment_id": required_environment, extra_key: "x"},
                1,
            ),
            ("non-object JSON", [required_environment], 1),
            ("malformed JSON", None, 1),
        ]
        secrets.SystemRandom().shuffle(cases)

        for description, payload, expected in cases:
            if os.path.lexists(candidate):
                os.unlink(candidate)
            with open(candidate, "w", encoding="utf-8") as config_file:
                if description == "malformed JSON":
                    config_file.write('{"environment_id":')
                else:
                    json.dump(payload, config_file)
            actual = run_validator(candidate)
            assert actual == expected, (
                f"Generated case {description!r} returned {actual}, expected {expected}."
            )

        with open(target, "w", encoding="utf-8") as target_file:
            json.dump({"environment_id": required_environment}, target_file)
        if os.path.lexists(candidate):
            os.unlink(candidate)
        os.symlink(target, candidate)
        assert run_validator(candidate) == 1, "A symbolic-link configuration was accepted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
