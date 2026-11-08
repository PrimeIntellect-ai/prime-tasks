#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid

BASE_DIR = "/home/user/legacy_docs"
REPORT_PATH = "/home/user/asset_report.csv"
SOURCE_PATH = "/home/user/process_docs.cpp"


def get_bdoc_data():
    bdoc_data = {}
    for root, _, files in os.walk(BASE_DIR):
        for file in files:
            if file.endswith(".bdoc"):
                full_path = os.path.join(root, file)
                with open(full_path, "rb") as f:
                    magic = f.read(4)
                    if magic == b"BDOC":
                        asset_id = struct.unpack("<I", f.read(4))[0]
                        ts = struct.unpack("<Q", f.read(8))[0]
                        bdoc_data[file] = {"asset_id": asset_id, "timestamp": ts}
    return bdoc_data


def test_csv_report():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    bdoc_data = get_bdoc_data()
    expected_rows = ["filename,AssetID,Timestamp"]
    for filename in sorted(bdoc_data.keys()):
        data = bdoc_data[filename]
        expected_rows.append(f"{filename},{data['asset_id']},{data['timestamp']}")

    expected_csv = "\n".join(expected_rows)

    with open(REPORT_PATH, "r") as f:
        actual_csv = f.read().strip()

    actual_lines = actual_csv.splitlines()
    expected_lines = expected_csv.splitlines()

    assert len(actual_lines) == len(expected_lines), f"CSV line count mismatch. Expected {len(expected_lines)}, got {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"CSV mismatch on line {i+1}. Expected '{expected}', got '{actual}'"


def test_markdown_files_updated():
    bdoc_data = get_bdoc_data()

    md1 = os.path.join(BASE_DIR, "section1/intro.md")
    assert os.path.isfile(md1), f"Markdown file {md1} is missing"

    with open(md1, "r") as f:
        content1 = f.read()

    assert "[[ASSET_REF" not in content1, f"Unreplaced macro found in {md1}"
    assert f"[Asset ID: {bdoc_data['diagram.bdoc']['asset_id']}](diagram.bdoc)" in content1, f"Correct replacement missing in {md1}"
    assert content1 == "Welcome to section 1.\nSee diagram: [Asset ID: 1042](diagram.bdoc)\nEnd of section.\n", f"Original content was not preserved in {md1}"

    md2 = os.path.join(BASE_DIR, "section2/deep/details.md")
    assert os.path.isfile(md2), f"Markdown file {md2} is missing"

    with open(md2, "r") as f:
        content2 = f.read()

    assert "[[ASSET_REF" not in content2, f"Unreplaced macro found in {md2}"
    assert f"[Asset ID: {bdoc_data['flow.bdoc']['asset_id']}](flow.bdoc)" in content2, f"Correct replacement for flow.bdoc missing in {md2}"
    assert f"[Asset ID: {bdoc_data['architecture.bdoc']['asset_id']}](architecture.bdoc)" in content2, f"Correct replacement for architecture.bdoc missing in {md2}"
    assert content2 == "Details here.\nFlowchart: [Asset ID: 9999](flow.bdoc)\nAlso reference: [Asset ID: 4242](architecture.bdoc)\n", f"Original content was not preserved in {md2}"


def test_no_unreplaced_macros():
    for root, _, files in os.walk(BASE_DIR):
        for file in files:
            if file.endswith(".md"):
                full_path = os.path.join(root, file)
                with open(full_path, "r") as f:
                    content = f.read()
                    assert "[[ASSET_REF:" not in content, f"Found unreplaced macro in {full_path}"


def test_cpp_program_on_fresh_random_fixture():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), f"{SOURCE_PATH} is not a regular file"
    assert os.path.getsize(SOURCE_PATH) > 0, f"{SOURCE_PATH} is empty"

    token = uuid.uuid4().hex
    executable = os.path.join("/tmp", f"process_docs_verify_{token}")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"C++17 compilation failed:\n{compile_result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compilation did not produce an executable"

    backup_root = tempfile.mkdtemp(prefix="process_docs_backup_")
    backup_docs = os.path.join(backup_root, "legacy_docs")
    backup_report = os.path.join(backup_root, "asset_report.csv")
    had_report = os.path.exists(REPORT_PATH)

    names = [f"zeta_{token[:8]}.bdoc", f"alpha_{token[8:16]}.bdoc", f"middle_{token[16:24]}.bdoc"]
    ids = [100000 + int(token[:6], 16) % 800000, 100000 + int(token[6:12], 16) % 800000, 100000 + int(token[12:18], 16) % 800000]
    timestamps = [1700000000 + int(token[18:24], 16), 1800000000 + int(token[24:30], 16), 1900000000 + int(token[2:8], 16)]
    assets = dict(zip(names, zip(ids, timestamps)))

    markdown_inputs = {
        os.path.join("one", "guide.md"): f"Opening text stays.\nFirst: [[ASSET_REF: {names[0]}]]\nClosing text stays.\n",
        os.path.join("two", "very", "deep", "notes.md"): f"Before\n[[ASSET_REF: {names[1]}]] and [[ASSET_REF: {names[2]}]]\nAgain: [[ASSET_REF: {names[1]}]]\nAfter\n",
        os.path.join("untouched", "plain.md"): "This markdown has no asset macro and must remain byte-for-byte unchanged.\n",
    }

    try:
        shutil.move(BASE_DIR, backup_docs)
        if had_report:
            shutil.move(REPORT_PATH, backup_report)

        os.makedirs(BASE_DIR)
        asset_dirs = [os.path.join(BASE_DIR, "assets"), os.path.join(BASE_DIR, "nested", "assets"), os.path.join(BASE_DIR, "nested", "more", "assets")]
        original_bdocs = {}
        for name, asset_dir in zip(names, asset_dirs):
            os.makedirs(asset_dir, exist_ok=True)
            asset_id, timestamp = assets[name]
            payload = b"BDOC" + struct.pack("<I", asset_id) + struct.pack("<Q", timestamp) + os.urandom(37)
            path = os.path.join(asset_dir, name)
            with open(path, "wb") as f:
                f.write(payload)
            original_bdocs[path] = payload

        for relative_path, content in markdown_inputs.items():
            path = os.path.join(BASE_DIR, relative_path)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert run_result.returncode == 0, f"Compiled program failed on a fresh fixture:\nstdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"

        assert os.path.isfile(REPORT_PATH), "Program did not generate /home/user/asset_report.csv"
        expected_report = ["filename,AssetID,Timestamp"]
        for name in sorted(names):
            asset_id, timestamp = assets[name]
            expected_report.append(f"{name},{asset_id},{timestamp}")
        with open(REPORT_PATH, "r") as f:
            actual_report = f.read().strip().splitlines()
        assert actual_report == expected_report, f"Fresh-fixture CSV mismatch: expected {expected_report}, got {actual_report}"

        for relative_path, original in markdown_inputs.items():
            expected = original
            for name, (asset_id, _) in assets.items():
                expected = expected.replace(f"[[ASSET_REF: {name}]]", f"[Asset ID: {asset_id}]({name})")
            with open(os.path.join(BASE_DIR, relative_path), "r") as f:
                actual = f.read()
            assert actual == expected, f"Markdown content or replacements are incorrect in {relative_path}"

        for path, payload in original_bdocs.items():
            with open(path, "rb") as f:
                assert f.read() == payload, f"Program modified binary asset {path}"
    finally:
        if os.path.exists(BASE_DIR):
            shutil.rmtree(BASE_DIR)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        if os.path.exists(backup_docs):
            shutil.move(backup_docs, BASE_DIR)
        if had_report and os.path.exists(backup_report):
            shutil.move(backup_report, REPORT_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
