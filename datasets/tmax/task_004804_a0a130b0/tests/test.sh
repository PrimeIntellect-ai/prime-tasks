#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import html
import json
import os
import shutil
import subprocess
import uuid
import xml.etree.ElementTree as ET
import pytest

XML_PATH = "/home/user/network_configs.xml"
OUTPUT_DIR = "/home/user/diff_chunks"
HEADER = ["timestamp", "key", "old_value", "new_value"]
SELECTED_SCRIPT = None
ORIGINAL_XML = None


def compute_expected_diffs():
    xml_path = XML_PATH
    if not os.path.exists(xml_path):
        return []

    diffs = []
    prev_config = None

    # Simple parsing to extract just what we need to compute truth
    tree = ET.parse(xml_path)
    root = tree.getroot()
    for record in root.findall('record'):
        server_id = record.find('server_id').text
        if server_id != "core-router-01":
            continue

        timestamp = record.find('timestamp').text
        config_text = record.find('config').text
        current_config = json.loads(config_text)

        if prev_config is not None:
            current_diffs = []

            # Check for changed and removed keys
            for k, v in prev_config.items():
                if k not in current_config:
                    current_diffs.append((timestamp, k, str(v), "NONE"))
                elif current_config[k] != v:
                    current_diffs.append((timestamp, k, str(v), str(current_config[k])))

            # Check for added keys
            for k, v in current_config.items():
                if k not in prev_config:
                    current_diffs.append((timestamp, k, "NONE", str(v)))

            # Sort alphabetically by key name
            current_diffs.sort(key=lambda x: x[1])
            diffs.extend(current_diffs)

        prev_config = current_config

    return diffs


def find_streaming_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        if os.path.abspath(root).startswith(os.path.abspath(OUTPUT_DIR)):
            continue
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    source = f.read()
                tree = ast.parse(source, filename=path)
            except (OSError, UnicodeError, SyntaxError):
                continue

            etree_aliases = set()
            direct_full_tree = set()
            sax_imported = False
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        local = alias.asname or alias.name.split(".")[0]
                        if alias.name in ("xml.etree.ElementTree", "lxml.etree"):
                            etree_aliases.add(local)
                        if alias.name.startswith("xml.sax") or alias.name == "pyexpat":
                            sax_imported = True
                elif isinstance(node, ast.ImportFrom):
                    module = node.module or ""
                    if module in ("xml.etree.ElementTree", "lxml.etree"):
                        for alias in node.names:
                            if alias.name in ("parse", "fromstring", "fromstringlist"):
                                direct_full_tree.add(alias.asname or alias.name)
                    if module.startswith("xml.sax") or module == "pyexpat":
                        sax_imported = True

            uses_iterparse = False
            uses_pull_parser = False
            releases_elements = False
            uses_sax_parse = False
            forbidden_full_tree = False

            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                func = node.func
                if isinstance(func, ast.Name):
                    if func.id == "iterparse":
                        uses_iterparse = True
                    elif func.id == "XMLPullParser":
                        uses_pull_parser = True
                    elif func.id in direct_full_tree:
                        forbidden_full_tree = True
                    elif sax_imported and func.id in ("parse", "parseString", "create_parser"):
                        uses_sax_parse = True
                elif isinstance(func, ast.Attribute):
                    if func.attr == "iterparse":
                        uses_iterparse = True
                    elif func.attr == "XMLPullParser":
                        uses_pull_parser = True
                    elif func.attr in ("clear", "remove"):
                        releases_elements = True
                    elif sax_imported and func.attr in ("parse", "feed"):
                        uses_sax_parse = True
                    elif func.attr in ("fromstring", "fromstringlist"):
                        forbidden_full_tree = True
                    elif func.attr == "parse" and isinstance(func.value, ast.Name) and func.value.id in etree_aliases:
                        forbidden_full_tree = True

            streaming = uses_sax_parse or ((uses_iterparse or uses_pull_parser) and releases_elements)
            if streaming and not forbidden_full_tree:
                candidates.append(path)

    return sorted(candidates)


def clean_output():
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)


def run_script(path):
    return subprocess.run(
        ["python3", path],
        cwd=os.path.dirname(path) or "/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def outputs_match_current_input():
    expected = compute_expected_diffs()
    expected_chunks = [expected[i:i + 20] for i in range(0, len(expected), 20)]
    if not expected_chunks or not os.path.isdir(OUTPUT_DIR):
        return False
    expected_names = {f"core_router_diffs_part{i}.csv" for i in range(1, len(expected_chunks) + 1)}
    if set(os.listdir(OUTPUT_DIR)) != expected_names:
        return False
    for i, chunk in enumerate(expected_chunks, 1):
        path = os.path.join(OUTPUT_DIR, f"core_router_diffs_part{i}.csv")
        try:
            with open(path, "r", newline="") as f:
                rows = list(csv.reader(f))
        except OSError:
            return False
        if not rows or rows[0] != HEADER:
            return False
        if [tuple(row) for row in rows[1:]] != chunk:
            return False
    return True


def setup_module(module):
    global SELECTED_SCRIPT, ORIGINAL_XML
    assert os.path.isfile(XML_PATH), f"Missing input XML file {XML_PATH}"
    with open(XML_PATH, "rb") as f:
        ORIGINAL_XML = f.read()

    candidates = find_streaming_scripts()
    assert candidates, "No valid Python script using a memory-conscious streaming XML parser was found under /home/user."

    failures = []
    for candidate in candidates:
        with open(XML_PATH, "wb") as f:
            f.write(ORIGINAL_XML)
        clean_output()
        try:
            result = run_script(candidate)
        except (subprocess.SubprocessError, OSError) as exc:
            failures.append(f"{candidate}: {exc}")
            continue
        if result.returncode == 0 and outputs_match_current_input():
            SELECTED_SCRIPT = candidate
            break
        failures.append(f"{candidate}: exit={result.returncode}, stderr={result.stderr[-500:]}")

    assert SELECTED_SCRIPT is not None, "No streaming Python script generated the required output. " + " | ".join(failures)


def test_python_script_exists_runs_and_uses_streaming_parser():
    assert SELECTED_SCRIPT is not None
    assert os.path.isfile(SELECTED_SCRIPT)


def test_diff_chunks_directory_exists():
    """Test that the output directory was created."""
    assert os.path.isdir("/home/user/diff_chunks"), "Directory /home/user/diff_chunks/ was not created."


def test_chunked_files_content():
    """Test that the chunked CSV files exist and contain the correct diffs."""
    expected_diffs = compute_expected_diffs()
    assert len(expected_diffs) > 0, "No diffs computed from the input file."

    chunk_size = 20
    expected_chunks = [expected_diffs[i:i + chunk_size] for i in range(0, len(expected_diffs), chunk_size)]

    for i, chunk in enumerate(expected_chunks, start=1):
        file_path = f"/home/user/diff_chunks/core_router_diffs_part{i}.csv"
        assert os.path.exists(file_path), f"Expected chunk file {file_path} is missing."

        with open(file_path, "r", newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)

        assert len(rows) > 0, f"File {file_path} is empty."
        assert rows[0] == ["timestamp", "key", "old_value", "new_value"], f"Header in {file_path} is incorrect."

        data_rows = rows[1:]
        assert len(data_rows) == len(chunk), f"File {file_path} has {len(data_rows)} records, expected {len(chunk)}."

        for row_idx, (actual, expected) in enumerate(zip(data_rows, chunk)):
            assert tuple(actual) == expected, f"Mismatch in {file_path} at row {row_idx + 2}. Expected {expected}, got {tuple(actual)}."


def test_no_extra_files():
    """Test that there are no extra unexpected files in the chunks directory."""
    expected_diffs = compute_expected_diffs()
    num_chunks = (len(expected_diffs) + 19) // 20

    expected_files = {f"core_router_diffs_part{i}.csv" for i in range(1, num_chunks + 1)}

    if os.path.isdir("/home/user/diff_chunks"):
        actual_files = set(os.listdir("/home/user/diff_chunks"))
        extra_files = actual_files - expected_files
        assert not extra_files, f"Found unexpected files in /home/user/diff_chunks/: {extra_files}"


def test_script_handles_unseen_input_by_execution():
    token = uuid.uuid4().hex[:10]
    events = []
    config = {f"ALPHA_{token}": 1, f"BETA_{token}": "initial", f"REMOVE_{token}": "present"}
    events.append(("2041-01-01T00:00:00Z", "core-router-01", dict(config)))
    events.append(("2041-01-01T00:15:00Z", "noise-server", {"IGNORED": token}))

    for i in range(1, 13):
        next_config = {
            f"ALPHA_{token}": i + 1,
            f"BETA_{token}": f"value-{i}-{token}",
        }
        if i % 2 == 0:
            next_config[f"TEMP_{token}_{i:02d}"] = "active"
        events.append((f"2041-01-01T{i:02d}:00:00Z", "core-router-01", next_config))
        events.append((f"2041-01-01T{i:02d}:30:00Z", "noise-server", {"NOISE": i}))

    lines = ["<dumps>"]
    for timestamp, server, config_value in events:
        config_json = json.dumps(config_value, separators=(",", ":"))
        lines.extend([
            "  <record>",
            f"    <timestamp>{html.escape(timestamp)}</timestamp>",
            f"    <server_id>{html.escape(server)}</server_id>",
            f"    <config>{html.escape(config_json)}</config>",
            "  </record>",
        ])
    lines.append("</dumps>")

    try:
        with open(XML_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        expected = compute_expected_diffs()
        assert len(expected) > 20, "Generated verification input did not exercise chunking."
        clean_output()
        result = run_script(SELECTED_SCRIPT)
        assert result.returncode == 0, f"Script failed on unseen input: {result.stderr}"
        assert outputs_match_current_input(), "Script output was incorrect for an unseen XML input."
    finally:
        with open(XML_PATH, "wb") as f:
            f.write(ORIGINAL_XML)
        clean_output()
        run_script(SELECTED_SCRIPT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
