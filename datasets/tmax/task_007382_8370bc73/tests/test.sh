#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import stat
import pytest

DATASET = "/home/user/dataset"
PROCESSED = "/home/user/processed_dataset"
ARCHIVE = "/home/user/final_archive.tar.gz"


def custom_compress(text):
    result = []
    i = 0
    while i < len(text):
        j = i + 1
        while j < len(text) and text[j] == text[i]:
            j += 1
        count = j - i
        if count >= 3:
            result.append(text[i] + "*" + str(count))
        else:
            result.append(text[i:j])
        i = j
    return "".join(result)


def expected_outputs():
    outputs = {}
    summary = {}
    origins = {}
    for root, dirs, files in os.walk(DATASET):
        dirs.sort()
        files.sort()
        for filename in files:
            if not filename.endswith(".gcode"):
                continue
            path = os.path.join(root, filename)
            if not os.path.isfile(path):
                continue
            with open(path, "r", encoding="utf-8", newline="") as f:
                text = f.read()
            if "; Material: PETG" not in text:
                continue
            assert filename not in origins, (
                "The fixture contains matching .gcode files with duplicate basenames, "
                "which cannot be represented unambiguously by the requested flat output."
            )
            origins[filename] = path
            outputs[filename + ".cz"] = custom_compress(text)
            summary[filename] = os.path.getsize(path)
    return outputs, summary


def test_processed_dataset_directory():
    assert os.path.isdir("/home/user/processed_dataset"), "Directory /home/user/processed_dataset/ is missing."


def test_compressed_files_exist():
    assert os.path.isfile("/home/user/processed_dataset/item1.gcode.cz"), "File item1.gcode.cz is missing."
    assert os.path.isfile("/home/user/processed_dataset/item3.gcode.cz"), "File item3.gcode.cz is missing."
    # Ensure item2 and notes are not processed
    assert not os.path.isfile("/home/user/processed_dataset/item2.gcode.cz"), "item2.gcode.cz should not exist (wrong material)."
    assert not os.path.isfile("/home/user/processed_dataset/notes.txt.cz"), "notes.txt.cz should not exist (not a .gcode file)."


def test_compressed_file_contents():
    with open("/home/user/processed_dataset/item1.gcode.cz", "r") as f:
        content1 = f.read()
    expected1 = "; Material: PETG\nG1 X100.0*3 Y200.0*3 Z1.0*3\nM104 S230\n"
    assert content1 == expected1, "item1.gcode.cz content does not match the expected custom compression."

    with open("/home/user/processed_dataset/item3.gcode.cz", "r") as f:
        content3 = f.read()
    expected3 = "; Material: PETG\n;*4 Custom header\nG0 F30*3\n"
    assert content3 == expected3, "item3.gcode.cz content does not match the expected custom compression."


def test_summary_json():
    summary_path = "/home/user/processed_dataset/summary.json"
    assert os.path.isfile(summary_path), "summary.json is missing."
    with open(summary_path, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    assert "item1.gcode" in summary, "item1.gcode missing from summary.json"
    assert summary["item1.gcode"] == 55, "item1.gcode size is incorrect in summary.json"

    assert "item3.gcode" in summary, "item3.gcode missing from summary.json"
    assert summary["item3.gcode"] == 45, "item3.gcode size is incorrect in summary.json"


def test_all_recursive_outputs_and_exact_summary():
    outputs, expected_summary = expected_outputs()
    assert os.path.isdir(PROCESSED), "Processed directory is missing."

    actual_entries = set(os.listdir(PROCESSED))
    expected_entries = set(outputs) | {"summary.json"}
    assert actual_entries == expected_entries, (
        "processed_dataset must contain exactly the recursively selected compressed "
        "files and summary.json."
    )

    for filename, expected_text in outputs.items():
        path = os.path.join(PROCESSED, filename)
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode), f"{filename} must be a regular file."
        with open(path, "r", encoding="utf-8", newline="") as f:
            assert f.read() == expected_text, f"Incorrect custom compression for {filename}."

    summary_path = os.path.join(PROCESSED, "summary.json")
    assert stat.S_ISREG(os.lstat(summary_path).st_mode), "summary.json must be a regular file."
    with open(summary_path, "r", encoding="utf-8") as f:
        summary = json.load(f)
    assert isinstance(summary, dict), "summary.json must contain one JSON object."
    assert summary == expected_summary, (
        "summary.json must contain exactly every selected basename and its original byte size."
    )
    assert all(type(value) is int for value in summary.values()), "All summary sizes must be integers."


def test_final_archive():
    archive_path = "/home/user/final_archive.tar.gz"
    assert os.path.isfile(archive_path), "final_archive.tar.gz is missing."
    assert tarfile.is_tarfile(archive_path), "final_archive.tar.gz is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        basenames = [os.path.basename(n) for n in names]
        assert "item1.gcode.cz" in basenames, "item1.gcode.cz missing from archive."
        assert "item3.gcode.cz" in basenames, "item3.gcode.cz missing from archive."
        assert "summary.json" in basenames, "summary.json missing from archive."

        # Check that they are under a processed_dataset directory
        has_processed_dir = any("processed_dataset" in n for n in names)
        assert has_processed_dir, "Archive does not contain the processed_dataset directory structure."


def test_archive_contains_actual_processed_directory_contents():
    outputs, _ = expected_outputs()
    expected_files = set(outputs) | {"summary.json"}

    with tarfile.open(ARCHIVE, "r:gz") as tar:
        normalized = []
        for member in tar.getmembers():
            raw = member.name
            assert not raw.startswith("/"), "Archive must not contain absolute paths."
            parts = [part for part in raw.split("/") if part not in ("", ".")]
            assert ".." not in parts, "Archive must not contain parent-directory paths."
            name = "/".join(parts)
            normalized.append((name, member))

        assert any(name == "processed_dataset" and member.isdir()
                   for name, member in normalized), (
            "Archive must contain the processed_dataset directory itself."
        )

        archived_files = {}
        for name, member in normalized:
            if name == "processed_dataset":
                assert member.isdir(), "processed_dataset archive member must be a directory."
                continue
            assert name.startswith("processed_dataset/"), (
                "Every archived member must be inside the top-level processed_dataset folder."
            )
            relative = name[len("processed_dataset/"):]
            assert "/" not in relative and relative, (
                "processed_dataset must contain the requested flat set of files only."
            )
            assert member.isfile(), f"Archived member {name} must be a regular file."
            assert relative not in archived_files, f"Duplicate archive member: {name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_files[relative] = extracted.read()

        assert set(archived_files) == expected_files, (
            "Archive must contain exactly the processed compressed files and summary.json."
        )

        for filename, expected_text in outputs.items():
            assert archived_files[filename] == expected_text.encode("utf-8"), (
                f"Archived {filename} does not contain the correctly compressed source data."
            )

        with open(os.path.join(PROCESSED, "summary.json"), "rb") as f:
            assert archived_files["summary.json"] == f.read(), (
                "Archived summary.json must be the actual summary from processed_dataset."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
