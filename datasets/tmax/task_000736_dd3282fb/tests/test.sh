#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import shutil
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def decode_header(path):
    with open(path, "rb") as f:
        header = f.read(16)
    assert len(header) == 16, f"File has a truncated header: {path}"
    magic, xor_key, encoded_pid, encoded_ts = struct.unpack(">IIII", header)
    assert magic == 0xDEADBEEF, f"Invalid magic in organized file: {path}"
    project_id = encoded_pid ^ xor_key
    timestamp = encoded_ts ^ xor_key
    file_type = ["log", "media", "document"][project_id % 3]
    return {
        "project_id": project_id,
        "file_type": file_type,
        "timestamp": timestamp,
    }


def dat_files(root):
    if not os.path.isdir(root):
        return []
    return [
        os.path.join(base, name)
        for base, _, files in os.walk(root)
        for name in files
        if name.endswith(".dat")
    ]


def test_parser_accuracy():
    parser_path = "/home/user/parser.py"
    assert os.path.exists(parser_path), f"Parser script not found at {parser_path}"

    num_files = 10000
    expected_ground_truth = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_files):
            filename = f"test_file_{i}.dat"
            filepath = os.path.join(tmpdir, filename)

            xor_key = random.randint(0, 0xFFFFFFFF)
            project_id = random.randint(0, 10000)
            timestamp = random.randint(1600000000, 1700000000)

            encoded_pid = project_id ^ xor_key
            encoded_ts = timestamp ^ xor_key
            file_type = ["log", "media", "document"][project_id % 3]

            with open(filepath, "wb") as f:
                f.write(struct.pack(">IIII", 0xDEADBEEF, xor_key, encoded_pid, encoded_ts))
                f.write(os.urandom(random.randint(10, 50)))

            expected_ground_truth[filename] = {
                "project_id": project_id,
                "file_type": file_type,
                "timestamp": timestamp,
            }

        try:
            subprocess.run(
                ["python3", parser_path, tmpdir],
                check=True,
                cwd=tmpdir,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"parser.py failed to execute: {e.stderr}")

        report_path = os.path.join(tmpdir, "metadata_report.json")
        assert os.path.exists(report_path), f"metadata_report.json not found in {tmpdir}"

        with open(report_path) as f:
            try:
                agent_output = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("metadata_report.json is not valid JSON")

        correct = 0
        for filename, expected_meta in expected_ground_truth.items():
            if filename in agent_output:
                agent_meta = agent_output[filename]
                if (
                    agent_meta.get("project_id") == expected_meta["project_id"]
                    and agent_meta.get("file_type") == expected_meta["file_type"]
                    and agent_meta.get("timestamp") == expected_meta["timestamp"]
                ):
                    correct += 1

        accuracy = correct / num_files
        assert accuracy >= 1.0, (
            f"Accuracy {accuracy} below threshold 1.0. "
            f"Correctly parsed {correct} out of {num_files} files."
        )


def test_initial_organization_is_complete_and_correct():
    organized_dir = "/home/user/organized_data"
    legacy_dir = "/home/user/legacy_data"
    rules_path = "/home/user/organization_rules.json"

    assert os.path.exists(organized_dir), f"Organized data directory not found at {organized_dir}"
    assert os.path.isdir(organized_dir), f"{organized_dir} is not a directory"

    organized_files = dat_files(organized_dir)
    assert len(organized_files) > 0, "No .dat files found in the organized_data directory."
    assert len(organized_files) == 20, (
        f"Expected all 20 initial files to be organized, found {len(organized_files)}"
    )
    assert not dat_files(legacy_dir), "Some initial .dat files were not moved from legacy_data"

    with open(rules_path) as f:
        rules = json.load(f)

    original_names = {f"data_{i}.dat" for i in range(20)}
    for path in organized_files:
        metadata = decode_header(path)
        rule_key = str(metadata["project_id"] % 3)
        assert rule_key in rules, f"No organization rule for key {rule_key}"
        relative_parts = Path(os.path.relpath(path, organized_dir)).parts[:-1]
        expected_parts = Path(rules[rule_key]).parts
        assert all(part in relative_parts for part in expected_parts), (
            f"{path} is not under its configured folder {rules[rule_key]}"
        )
        assert os.path.basename(path) not in original_names, f"File was not renamed: {path}"


def test_organize_script_on_fresh_inputs():
    organize_path = "/home/user/organize.py"
    legacy_dir = "/home/user/legacy_data"
    organized_dir = "/home/user/organized_data"
    rules_path = "/home/user/organization_rules.json"

    assert os.path.isfile(organize_path), f"Organizer script not found at {organize_path}"

    with tempfile.TemporaryDirectory(prefix="organizer_verify_") as backup_root:
        legacy_backup = os.path.join(backup_root, "legacy_data")
        organized_backup = os.path.join(backup_root, "organized_data")
        rules_backup = os.path.join(backup_root, "organization_rules.json")

        legacy_existed = os.path.exists(legacy_dir)
        organized_existed = os.path.exists(organized_dir)
        if legacy_existed:
            shutil.move(legacy_dir, legacy_backup)
        if organized_existed:
            shutil.move(organized_dir, organized_backup)
        shutil.copy2(rules_path, rules_backup)

        token = uuid.uuid4().hex[:12]
        test_rules = {
            "0": f"verify_logs_{token}",
            "1": f"verify_media_{token}",
            "2": f"verify_documents_{token}",
        }
        expected_by_hash = {}

        try:
            os.makedirs(legacy_dir)
            with open(rules_path, "w") as f:
                json.dump(test_rules, f)

            for i in range(15):
                project_id = random.randint(1, 1000000)
                timestamp = random.randint(1500000000, 1900000000)
                xor_key = random.randint(0, 0xFFFFFFFF)
                original_name = f"unorganized_{token}_{i}.dat"
                content = struct.pack(
                    ">IIII",
                    0xDEADBEEF,
                    xor_key,
                    project_id ^ xor_key,
                    timestamp ^ xor_key,
                ) + f"unique-payload-{token}-{i}".encode() + os.urandom(24)
                source_path = os.path.join(legacy_dir, original_name)
                with open(source_path, "wb") as f:
                    f.write(content)
                digest = hashlib.sha256(content).hexdigest()
                expected_by_hash[digest] = {
                    "original_name": original_name,
                    "folder": test_rules[str(project_id % 3)],
                }

            try:
                subprocess.run(
                    ["python3", organize_path],
                    check=True,
                    cwd="/home/user",
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(f"organize.py failed to execute: {e.stderr}")
            except subprocess.TimeoutExpired:
                pytest.fail("organize.py did not finish within 60 seconds")

            assert os.path.isdir(organized_dir), "organize.py did not create organized_data"
            assert not dat_files(legacy_dir), "organize.py did not move all input .dat files"

            outputs = dat_files(organized_dir)
            assert len(outputs) == len(expected_by_hash), (
                f"Expected {len(expected_by_hash)} organized files, found {len(outputs)}"
            )

            seen = set()
            for output_path in outputs:
                with open(output_path, "rb") as f:
                    digest = hashlib.sha256(f.read()).hexdigest()
                assert digest in expected_by_hash, f"Unexpected or modified output file: {output_path}"
                assert digest not in seen, f"Input file was duplicated: {output_path}"
                seen.add(digest)

                expected = expected_by_hash[digest]
                relative_parts = Path(os.path.relpath(output_path, organized_dir)).parts
                assert expected["folder"] in relative_parts[:-1], (
                    f"{output_path} was placed in the wrong configured folder"
                )
                assert os.path.basename(output_path) != expected["original_name"], (
                    f"organize.py moved but did not rename {expected['original_name']}"
                )

            assert seen == set(expected_by_hash), "Not every fresh input was organized"
        finally:
            if os.path.exists(legacy_dir):
                shutil.rmtree(legacy_dir)
            if os.path.exists(organized_dir):
                shutil.rmtree(organized_dir)
            shutil.copy2(rules_backup, rules_path)
            if legacy_existed:
                shutil.move(legacy_backup, legacy_dir)
            if organized_existed:
                shutil.move(organized_backup, organized_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
