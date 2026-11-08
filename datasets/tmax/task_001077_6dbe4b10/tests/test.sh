#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import sys
import uuid
import pytest

SCRIPT = "/home/user/compile_notes.py"
RAW_ROOT = "/home/user/raw_notes"
PROCESSED_ROOT = "/home/user/processed_notes"
LOG_PATH = "/home/user/files_processed.log"


def clear_results():
    shutil.rmtree(PROCESSED_ROOT, ignore_errors=True)
    os.makedirs(PROCESSED_ROOT, exist_ok=True)
    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"compile_notes.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_for_markdown(path):
    with open(path, "r") as f:
        content = f.read()
    title = "Unknown"
    for line in content.splitlines():
        if line.startswith("# "):
            title = line[2:].strip()
            break
    return {"title": title, "content": content, "words": len(content.split())}


def markdown_output_map():
    result = {}
    for root, _, files in os.walk(RAW_ROOT):
        for name in files:
            if name.endswith(".md"):
                source = os.path.join(root, name)
                relative = os.path.relpath(source, RAW_ROOT)
                output = os.path.join(PROCESSED_ROOT, os.path.splitext(relative)[0] + ".json")
                result[output] = source
    return result


def test_script_exists_and_processes_runtime_fixtures_recursively():
    assert os.path.isfile(SCRIPT), f"Required Python script missing: {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"Expected a regular script, not a symlink: {SCRIPT}"

    token = uuid.uuid4().hex
    fixture_root = os.path.join(RAW_ROOT, ".verifier_" + token)
    deep_dir = os.path.join(fixture_root, "one", "two", "three")
    os.makedirs(deep_dir)

    fixtures = {
        os.path.join(deep_dir, "generated_" + token + ".md"):
            "Prelude line" + chr(10) + "## Not level one" + chr(10) +
            "#   Runtime Title   " + chr(10) + "alpha beta" + chr(10),
        os.path.join(fixture_root, "empty_" + token + ".md"): "",
        os.path.join(fixture_root, "no_header_" + token + ".md"):
            "ordinary words" + chr(10) + "#Not a level one header" + chr(10),
    }
    for path, content in fixtures.items():
        with open(path, "w") as f:
            f.write(content)

    ignored = os.path.join(deep_dir, "ignored_" + token + ".txt")
    with open(ignored, "w") as f:
        f.write("# This must not be processed" + chr(10))

    try:
        clear_results()
        run_script()

        expected_map = markdown_output_map()
        expected_outputs = sorted(expected_map)
        actual_outputs = sorted(
            os.path.join(root, name)
            for root, _, files in os.walk(PROCESSED_ROOT)
            for name in files
            if name.endswith(".json")
        )
        assert actual_outputs == expected_outputs, (
            f"Script did not process exactly the recursively discovered Markdown files. "
            f"Expected {expected_outputs}, got {actual_outputs}"
        )

        for output, source in expected_map.items():
            with open(output, "r") as f:
                data = json.load(f)
            expected = expected_for_markdown(source)
            assert data.get("title") == expected["title"], f"Incorrect title for runtime input {source}"
            assert data.get("content") == expected["content"], f"Incorrect content for runtime input {source}"
            assert data.get("words") == expected["words"], f"Incorrect word count for runtime input {source}"

        ignored_output = os.path.join(
            PROCESSED_ROOT,
            os.path.relpath(ignored, RAW_ROOT)[:-4] + ".json",
        )
        assert not os.path.exists(ignored_output), "A runtime non-Markdown fixture was processed"

        assert os.path.isfile(LOG_PATH), f"Log file missing after executing {SCRIPT}"
        with open(LOG_PATH, "r") as f:
            log_lines = [line.strip() for line in f if line.strip()]
        assert log_lines == expected_outputs, (
            f"Runtime log was not the sorted list of generated JSON files. "
            f"Expected {expected_outputs}, got {log_lines}"
        )
    finally:
        shutil.rmtree(fixture_root, ignore_errors=True)

    # Restore and independently regenerate the original requested final state.
    clear_results()
    run_script()
    assert os.path.isfile(SCRIPT), f"Script disappeared after execution: {SCRIPT}"


def test_json_files_created():
    expected_files = [
        "/home/user/processed_notes/meeting1.json",
        "/home/user/processed_notes/tech/backend/api.json",
        "/home/user/processed_notes/personal/todo.json"
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Expected JSON file missing: {f}"


def test_no_txt_processed():
    not_expected = "/home/user/processed_notes/tech/notes.json"
    assert not os.path.exists(not_expected), f"Text files should not be processed, found: {not_expected}"


def test_json_contents():
    # Map of json path to its corresponding md path
    file_map = {
        "/home/user/processed_notes/meeting1.json": "/home/user/raw_notes/meeting1.md",
        "/home/user/processed_notes/tech/backend/api.json": "/home/user/raw_notes/tech/backend/api.md",
        "/home/user/processed_notes/personal/todo.json": "/home/user/raw_notes/personal/todo.md"
    }

    for json_path, md_path in file_map.items():
        assert os.path.isfile(json_path), f"Missing JSON file: {json_path}"
        assert os.path.isfile(md_path), f"Missing original MD file: {md_path}"

        with open(md_path, "r") as f:
            md_content = f.read()

        # Calculate expected values
        expected_words = len(md_content.split())

        expected_title = "Unknown"
        for line in md_content.splitlines():
            if line.startswith("# "):
                expected_title = line[2:].strip()
                break

        with open(json_path, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON in {json_path}")

        assert "title" in data, f"Missing 'title' key in {json_path}"
        assert "content" in data, f"Missing 'content' key in {json_path}"
        assert "words" in data, f"Missing 'words' key in {json_path}"

        assert data["title"] == expected_title, f"Incorrect title in {json_path}. Expected {expected_title}, got {data['title']}"
        assert data["content"] == md_content, f"Incorrect content in {json_path}."
        assert data["words"] == expected_words, f"Incorrect word count in {json_path}. Expected {expected_words}, got {data['words']}"


def test_log_file():
    log_path = "/home/user/files_processed.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/processed_notes/meeting1.json",
        "/home/user/processed_notes/personal/todo.json",
        "/home/user/processed_notes/tech/backend/api.json"
    ]
    expected_lines.sort()

    assert lines == expected_lines, f"Log file content incorrect or not sorted properly. Expected {expected_lines}, got {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
