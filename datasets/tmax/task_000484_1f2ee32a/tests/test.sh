#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import textwrap
import pytest

CONFIG_ROOT = "/home/user/config_root"
BACKUP_FILE = "/home/user/backup.ccf"
MANIFEST_FILE = "/home/user/manifest.log"
SCRIPT_FILE = "/home/user/backup_manager.py"


def compute_rle(text: str) -> str:
    if not text:
        return ""
    result = []
    current_char = text[0]
    count = 1
    for char in text[1:]:
        if char == current_char:
            count += 1
            if count == 10:
                result.append(f"9{current_char}")
                count = 1
        else:
            result.append(f"{count}{current_char}")
            current_char = char
            count = 1
    result.append(f"{count}{current_char}")
    return "".join(result)


def test_output_files_exist():
    """Test that the expected output files were created."""
    assert os.path.isfile(BACKUP_FILE), f"Backup file not found at {BACKUP_FILE}"
    assert os.path.isfile(MANIFEST_FILE), f"Manifest file not found at {MANIFEST_FILE}"


def test_manifest_content():
    """Test that the manifest contains the correct files and sizes."""
    expected_files = {
        "app.conf": 19,
        "db.conf": 25,
        "sub_dir/pad.conf": 24,
        "sub_dir/service.conf": 20
    }

    with open(MANIFEST_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    actual_files = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        rel_path = parts[0].strip()
        size = int(parts[1].strip())
        actual_files[rel_path] = size

    # Allow app_link.conf to be either skipped or resolved to app.conf
    # The requirement is deduplication of uniquely discovered files.
    if "app_link.conf" in actual_files and "app.conf" not in actual_files:
        actual_files["app.conf"] = actual_files.pop("app_link.conf")

    assert actual_files == expected_files, f"Manifest content mismatch. Expected {expected_files}, got {actual_files}"


def test_backup_content():
    """Test that the backup file contains the correct headers and RLE compressed data."""
    files_expected = {
        "app.conf": "server_name=app;   ",
        "db.conf": "host=127.0.0.1;port=5432;",
        "sub_dir/pad.conf": "padding=xxxxxxxxxxxxxxx;",
        "sub_dir/service.conf": "mode=active;retry=3;"
    }

    expected_blocks = {}
    for rel_path, content in files_expected.items():
        expected_blocks[rel_path] = compute_rle(content)

    with open(BACKUP_FILE, "r") as f:
        backup_content = f.read()

    for rel_path, expected_rle in expected_blocks.items():
        header1 = f"---FILE: {rel_path}---"
        header2 = f"---FILE: app_link.conf---" if rel_path == "app.conf" else header1

        if header1 in backup_content:
            header = header1
        elif header2 in backup_content:
            header = header2
        else:
            pytest.fail(f"Missing header for {rel_path} in backup.ccf")

        lines = backup_content.splitlines()
        header_idx = lines.index(header)
        assert header_idx + 1 < len(lines), f"Missing data line after header {header}"

        actual_rle = lines[header_idx + 1]
        assert actual_rle == expected_rle, f"RLE mismatch for {rel_path}. Expected '{expected_rle}', got '{actual_rle}'"


def test_script_source_requirements():
    """Test that the script uses mmap and atomic writes (rename/replace)."""
    assert os.path.isfile(SCRIPT_FILE), f"Script missing at {SCRIPT_FILE}"

    with open(SCRIPT_FILE, "r") as f:
        source = f.read()

    assert "mmap" in source, "The script does not appear to use the 'mmap' module as required."

    atomic_write_pattern = re.compile(r'os\.(rename|replace)|shutil\.move')
    assert atomic_write_pattern.search(source), "The script does not appear to use atomic writes (os.rename, os.replace, or shutil.move)."


def test_behavioral_execution_on_fresh_inputs():
    """Execute the submitted artifact and verify traversal, exact output, mmap, and atomic replacement."""
    assert os.path.isfile(SCRIPT_FILE), f"Script missing at {SCRIPT_FILE}"

    shutil.rmtree(CONFIG_ROOT)
    os.makedirs(os.path.join(CONFIG_ROOT, "nested"))
    os.makedirs(os.path.join(CONFIG_ROOT, "loop_dir"))

    token = secrets.token_hex(8)
    target_rel = f"target_{token}.conf"
    alias_rel = f"alias_{token}.conf"
    plain_rel = f"plain_{token}.conf"
    nested_a_rel = f"nested/alpha_{token}.conf"
    nested_run_rel = f"nested/run_{token}.conf"

    contents = {
        target_rel: f"target={token};" + "Z" * 12 + ";",
        plain_rel: f"plain={token};" + "  " + "Q" * 10,
        nested_a_rel: f"alpha={token[::-1]};",
        nested_run_rel: "R" * 19 + f";{token};",
    }

    for rel_path, content in contents.items():
        path = os.path.join(CONFIG_ROOT, rel_path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(content.encode("utf-8"))

    os.symlink(os.path.join(CONFIG_ROOT, target_rel), os.path.join(CONFIG_ROOT, alias_rel))
    os.symlink(os.path.join(CONFIG_ROOT, "loop_dir"), os.path.join(CONFIG_ROOT, "loop_dir", "symlink_loop"))

    for output in (BACKUP_FILE, MANIFEST_FILE):
        try:
            os.unlink(output)
        except FileNotFoundError:
            pass

    trace_file = "/tmp/backup_manager_trace.json"
    wrapper_file = "/tmp/run_instrumented_backup.py"
    try:
        os.unlink(trace_file)
    except FileNotFoundError:
        pass

    wrapper = textwrap.dedent(r'''
        import json
        import mmap as real_mmap
        import os
        import runpy
        import shutil
        import sys
        import types

        trace_path = sys.argv[1]
        script_path = sys.argv[2]
        trace = {"mmap_calls": 0, "atomic_calls": []}

        fake_mmap = types.ModuleType("mmap")
        for name in dir(real_mmap):
            setattr(fake_mmap, name, getattr(real_mmap, name))

        def tracked_mmap(*args, **kwargs):
            trace["mmap_calls"] += 1
            return real_mmap.mmap(*args, **kwargs)

        fake_mmap.mmap = tracked_mmap
        sys.modules["mmap"] = fake_mmap

        real_replace = os.replace
        real_rename = os.rename
        real_move = shutil.move

        def tracked_replace(src, dst, *args, **kwargs):
            trace["atomic_calls"].append(["replace", os.fspath(src), os.fspath(dst)])
            return real_replace(src, dst, *args, **kwargs)

        def tracked_rename(src, dst, *args, **kwargs):
            trace["atomic_calls"].append(["rename", os.fspath(src), os.fspath(dst)])
            return real_rename(src, dst, *args, **kwargs)

        def tracked_move(src, dst, *args, **kwargs):
            trace["atomic_calls"].append(["move", os.fspath(src), os.fspath(dst)])
            return real_move(src, dst, *args, **kwargs)

        os.replace = tracked_replace
        os.rename = tracked_rename
        shutil.move = tracked_move

        try:
            runpy.run_path(script_path, run_name="__main__")
        finally:
            with open(trace_path, "w") as f:
                json.dump(trace, f)
    ''')
    with open(wrapper_file, "w") as f:
        f.write(wrapper)

    try:
        completed = subprocess.run(
            [sys.executable, wrapper_file, trace_file, SCRIPT_FILE],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("backup_manager.py did not terminate while traversing a symlink loop")

    assert completed.returncode == 0, (
        "backup_manager.py failed when executed:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(BACKUP_FILE), "Executed script did not create backup.ccf"
    assert os.path.isfile(MANIFEST_FILE), "Executed script did not create manifest.log"
    assert os.path.isfile(trace_file), "Execution trace was not produced"

    with open(trace_file, "r") as f:
        trace = json.load(f)

    assert trace["mmap_calls"] >= len(contents), (
        f"Expected mmap to be used for every unique file; observed {trace['mmap_calls']} calls"
    )
    valid_atomic_calls = [
        call for call in trace["atomic_calls"]
        if os.path.abspath(call[2]) == BACKUP_FILE and os.path.abspath(call[1]) != BACKUP_FILE
    ]
    assert valid_atomic_calls, "The archive was not installed via an atomic rename/move from a temporary path"

    with open(MANIFEST_FILE, "r") as f:
        manifest_lines = [line.rstrip("\n") for line in f]
    assert all(manifest_lines), "Manifest contains blank lines"

    actual_manifest = {}
    for line in manifest_lines:
        parts = line.rsplit(": ", 1)
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        rel_path, size_text = parts
        assert rel_path not in actual_manifest, f"Duplicate manifest entry: {rel_path}"
        actual_manifest[rel_path] = int(size_text)

    representative = target_rel if target_rel in actual_manifest else alias_rel
    expected_manifest = {
        plain_rel: len(contents[plain_rel].encode("utf-8")),
        nested_a_rel: len(contents[nested_a_rel].encode("utf-8")),
        nested_run_rel: len(contents[nested_run_rel].encode("utf-8")),
        representative: len(contents[target_rel].encode("utf-8")),
    }
    assert actual_manifest == expected_manifest, (
        f"Manifest mismatch. Expected {expected_manifest}, got {actual_manifest}"
    )

    selected_contents = {
        plain_rel: contents[plain_rel],
        nested_a_rel: contents[nested_a_rel],
        nested_run_rel: contents[nested_run_rel],
        representative: contents[target_rel],
    }

    def resolved_sort_key(rel_path):
        return target_rel if rel_path == alias_rel else rel_path

    ordered_paths = sorted(selected_contents, key=resolved_sort_key)
    expected_archive = "".join(
        f"---FILE: {rel_path}---\n{compute_rle(selected_contents[rel_path])}\n"
        for rel_path in ordered_paths
    )
    with open(BACKUP_FILE, "r") as f:
        actual_archive = f.read()
    assert actual_archive == expected_archive, (
        "Archive must contain exactly one correctly ordered block per unique file; "
        f"expected {expected_archive!r}, got {actual_archive!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
