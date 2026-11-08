#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest
import yaml

SCRIPT = Path("/home/user/run_backup.sh")
MANIFEST = Path("/home/user/backup_manifest.csv")
ARCHIVE = Path("/home/user/incremental.tar.gz")
RULES_IMAGE = Path("/app/rules.png")


def read_rules():
    assert RULES_IMAGE.is_file(), f"Rules image is missing: {RULES_IMAGE}"
    result = subprocess.run(
        ["tesseract", str(RULES_IMAGE), "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Unable to OCR rules image: {result.stderr}"
    text = result.stdout

    target_match = re.search(r"TARGET_DIR\s*=\s*(\S+)", text, re.IGNORECASE)
    min_match = re.search(r"MIN_SIZE\s*=\s*(\d+)\s*bytes?", text, re.IGNORECASE)
    max_match = re.search(r"MAX_SIZE\s*=\s*(\d+)\s*bytes?", text, re.IGNORECASE)
    ext_match = re.search(r"EXTENSION\s*=\s*(\.[A-Za-z0-9]+)", text, re.IGNORECASE)
    key_match = re.search(
        r"MUST\s+CONTAIN\s+KEY\s*:\s*[\"'“”]?([A-Za-z0-9_]+)[\"'“”]?\s*:\s*true",
        text,
        re.IGNORECASE,
    )

    assert target_match, f"TARGET_DIR was not readable from rules image. OCR output: {text!r}"
    assert min_match, f"MIN_SIZE was not readable from rules image. OCR output: {text!r}"
    assert max_match, f"MAX_SIZE was not readable from rules image. OCR output: {text!r}"
    assert ext_match, f"EXTENSION was not readable from rules image. OCR output: {text!r}"
    assert key_match, f"Required key/value was not readable from rules image. OCR output: {text!r}"

    return {
        "target": Path(target_match.group(1).rstrip(".,;")),
        "min_size": int(min_match.group(1)),
        "max_size": int(max_match.group(1)),
        "extension": ext_match.group(1).lower(),
        "key": key_match.group(1),
    }


def matching_sources(rules):
    matches = {}
    for path in rules["target"].rglob("*"):
        if not path.is_file() or path.suffix.lower() != rules["extension"]:
            continue
        size = path.stat().st_size
        if not (rules["min_size"] <= size <= rules["max_size"]):
            continue
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(value, dict) or value.get(rules["key"]) is not True:
            continue
        output_name = path.stem + ".yaml"
        assert output_name not in matches, f"Source basename collision for {output_name}"
        matches[output_name] = value
    return matches


def test_bash_script_exists():
    assert SCRIPT.is_file(), f"Bash script {SCRIPT} is missing."
    assert SCRIPT.stat().st_size > 0, f"Bash script {SCRIPT} is empty."
    syntax = subprocess.run(
        ["bash", "-n", str(SCRIPT)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert syntax.returncode == 0, f"Bash script has invalid syntax: {syntax.stderr}"


def test_backup_workflow_and_outputs():
    rules = read_rules()
    target = rules["target"]
    assert target.is_dir(), f"Configured target directory is missing: {target}"

    token = secrets.token_hex(8)
    created = []

    matching_probe = target / f"verifier_probe_{token}{rules['extension']}"
    false_probe = target / f"verifier_false_{token}{rules['extension']}"
    small_probe = target / f"verifier_small_{token}{rules['extension']}"
    large_probe = target / f"verifier_large_{token}{rules['extension']}"
    wrong_ext_probe = target / f"verifier_wrong_{token}{rules['extension']}.bak"

    matching_obj = {
        "id": f"probe-{token}",
        rules["key"]: True,
        "data": "independently generated verifier input",
    }
    false_obj = {
        "id": f"false-{token}",
        rules["key"]: False,
        "data": "this file has a valid size but must be excluded",
    }

    try:
        matching_probe.write_text(json.dumps(matching_obj) + "\n", encoding="utf-8")
        false_probe.write_text(json.dumps(false_obj) + "\n", encoding="utf-8")
        small_probe.write_text(json.dumps({rules["key"]: True}), encoding="utf-8")
        large_probe.write_text(
            json.dumps({rules["key"]: True, "pad": "x" * (rules["max_size"] + 100)}),
            encoding="utf-8",
        )
        wrong_ext_probe.write_text(json.dumps(matching_obj) + "\n", encoding="utf-8")
        created.extend([matching_probe, false_probe, small_probe, large_probe, wrong_ext_probe])

        assert rules["min_size"] <= matching_probe.stat().st_size <= rules["max_size"]
        assert rules["min_size"] <= false_probe.stat().st_size <= rules["max_size"]
        assert small_probe.stat().st_size < rules["min_size"]
        assert large_probe.stat().st_size > rules["max_size"]

        expected = matching_sources(rules)
        expected_probe_name = matching_probe.stem + ".yaml"
        assert expected_probe_name in expected, "Generated matching probe was not classified correctly"

        # Remove stale products so the submitted script must reproduce everything.
        for yaml_path in target.rglob("*.yaml"):
            if yaml_path.is_file() or yaml_path.is_symlink():
                yaml_path.unlink()
        for output in (MANIFEST, ARCHIVE):
            if output.exists() or output.is_symlink():
                if output.is_dir() and not output.is_symlink():
                    shutil.rmtree(output)
                else:
                    output.unlink()

        run = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert run.returncode == 0, (
            f"Backup script failed with exit code {run.returncode}.\n"
            f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        )

        assert MANIFEST.is_file(), f"Manifest file {MANIFEST} is missing."
        assert ARCHIVE.is_file(), f"Archive not found: {ARCHIVE}"

        archived_payloads = {}
        actual_files = set()
        try:
            with tarfile.open(ARCHIVE, "r:gz") as tar:
                for member in tar.getmembers():
                    assert member.isdir() or member.isfile(), (
                        f"Archive contains a non-regular entry: {member.name}"
                    )
                    if member.isdir():
                        continue
                    assert member.name.endswith(".yaml"), (
                        f"Archive contains a non-YAML file: {member.name}"
                    )
                    name = os.path.basename(member.name)
                    assert name and name not in archived_payloads, (
                        f"Archive contains a duplicate YAML basename: {name}"
                    )
                    extracted = tar.extractfile(member)
                    assert extracted is not None
                    payload = extracted.read()
                    archived_payloads[name] = payload
                    actual_files.add(name)
        except (tarfile.TarError, OSError) as exc:
            pytest.fail(f"Error reading archive {ARCHIVE}: {exc}")

        expected_files = set(expected)
        true_positives = len(expected_files & actual_files)
        false_positives = len(actual_files - expected_files)
        false_negatives = len(expected_files - actual_files)
        precision = true_positives / (true_positives + false_positives) if actual_files else 0.0
        recall = true_positives / (true_positives + false_negatives) if expected_files else 0.0
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
        assert f1 >= 0.95, (
            f"Metric F1 Score: {f1:.4f} is below threshold 0.95. "
            f"Expected: {expected_files}, Actual: {actual_files}"
        )
        assert actual_files == expected_files, (
            f"Archive membership is not exact. Expected: {expected_files}, Actual: {actual_files}"
        )

        for name, source_value in expected.items():
            try:
                converted = yaml.safe_load(archived_payloads[name].decode("utf-8"))
            except Exception as exc:
                pytest.fail(f"Archived file {name} is not valid UTF-8 YAML: {exc}")
            assert converted == source_value, (
                f"YAML content for {name} does not preserve its source JSON value"
            )

        with MANIFEST.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))
        assert len(rows) == len(expected_files), (
            f"Manifest must contain exactly one row per archived YAML file; got {rows}"
        )

        manifest_entries = {}
        for row in rows:
            assert len(row) == 2, f"Manifest row must have exactly two columns: {row}"
            filename, digest = row
            assert filename in expected_files, f"Unexpected manifest filename: {filename}"
            assert filename not in manifest_entries, f"Duplicate manifest row for {filename}"
            assert re.fullmatch(r"[0-9a-f]{64}", digest), (
                f"Invalid SHA-256 digest for {filename}: {digest}"
            )
            manifest_entries[filename] = digest

        assert set(manifest_entries) == expected_files, "Manifest filenames do not match archive"
        for filename, payload in archived_payloads.items():
            actual_digest = hashlib.sha256(payload).hexdigest()
            assert manifest_entries[filename] == actual_digest, (
                f"Manifest hash for {filename} does not match the archived YAML content"
            )
    finally:
        for path in created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
