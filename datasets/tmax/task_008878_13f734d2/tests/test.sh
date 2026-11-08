#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import shutil
import stat
import subprocess

import pytest

BACKUP_DIR = "/home/user/incremental_backup"
MANIFEST_PATH = os.path.join(BACKUP_DIR, "manifest.json")
SCRIPT_PATH = "/home/user/do_backup.py"


def test_manifest_exists_and_content():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file does not exist at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest file is not valid JSON")

    assert isinstance(manifest, list), "Manifest must be a JSON array"

    expected_manifest = ["config/settings.xml", "logs/app.json", "logs/data.csv"]

    assert manifest == expected_manifest, (
        f"Manifest content mismatch. Expected {expected_manifest}, but got {manifest}. "
        "Ensure paths are relative, filtered correctly, and sorted alphabetically."
    )


def test_copied_files_match_manifest():
    expected_files = ["config/settings.xml", "logs/app.json", "logs/data.csv"]

    copied_files = []
    if os.path.exists(BACKUP_DIR):
        for root, _, files in os.walk(BACKUP_DIR):
            for file in files:
                if file not in ("manifest.json", "manifest.tmp"):
                    rel_path = os.path.relpath(os.path.join(root, file), BACKUP_DIR)
                    copied_files.append(rel_path)

    assert sorted(copied_files) == sorted(expected_files), (
        f"Copied files mismatch. Expected {sorted(expected_files)}, but got {sorted(copied_files)}. "
        "Ensure files are filtered by extension, excluded directories, and mtime strictly after last_run."
    )

    # Verify each expected file actually exists and is a file
    for f in expected_files:
        full_path = os.path.join(BACKUP_DIR, f)
        assert os.path.isfile(full_path), f"Expected backed up file {full_path} is missing or not a file."


def test_z_script_behavior_and_atomic_manifest():
    assert os.path.lexists(SCRIPT_PATH), f"Backup script does not exist at {SCRIPT_PATH}"
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "do_backup.py must be a regular file"

    app_dir = pathlib.Path("/home/user/app_data")
    rules_path = pathlib.Path("/home/user/backup_rules.json")
    state_path = pathlib.Path("/home/user/state.json")
    backup_dir = pathlib.Path(BACKUP_DIR)

    shutil.rmtree(app_dir, ignore_errors=True)
    shutil.rmtree(backup_dir, ignore_errors=True)
    app_dir.mkdir(parents=True)

    rules = {
        "include_extensions": [".json", ".xml", ".odd"],
        "exclude_dirs": ["skipme", "nestedskip"],
    }
    last_run = 1700000000
    rules_path.write_text(json.dumps(rules), encoding="utf-8")
    state_path.write_text(json.dumps({"last_run": last_run}), encoding="utf-8")
    state_before = state_path.read_bytes()

    fixtures = {
        "root.json": (1700000001, b"new root json\n"),
        "deep/item.xml": (1700000456, b"<item>dynamic</item>\n"),
        "deep/more/value.odd": (1700000002, b"odd extension data\n"),
        "equal.json": (last_run, b"must not be copied\n"),
        "old.xml": (last_run - 1, b"old data\n"),
        "upper.JSON": (last_run + 10, b"wrong case\n"),
        "notes.txt": (last_run + 20, b"wrong extension\n"),
        "archive.json.bak": (last_run + 30, b"wrong final extension\n"),
        "skipme/hidden.json": (last_run + 40, b"excluded directory\n"),
        "deep/nestedskip/hidden.xml": (last_run + 50, b"nested excluded directory\n"),
    }
    for relative, (mtime, content) in fixtures.items():
        path = app_dir / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        os.utime(path, (mtime, mtime))

    expected = []
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in rules["exclude_dirs"]]
        for name in files:
            source = pathlib.Path(root) / name
            if source.suffix in rules["include_extensions"] and source.stat().st_mtime > last_run:
                expected.append(source.relative_to(app_dir).as_posix())
    expected.sort()

    hook_dir = pathlib.Path("/tmp/backup_verify_hook")
    shutil.rmtree(hook_dir, ignore_errors=True)
    hook_dir.mkdir()
    event_log = pathlib.Path("/tmp/backup_rename_events.jsonl")
    event_log.unlink(missing_ok=True)

    (hook_dir / "sitecustomize.py").write_text(r'''
import json
import os

_event_log = "/tmp/backup_rename_events.jsonl"
_original_rename = os.rename
_original_replace = os.replace

def _record(operation, src, dst):
    try:
        src_text = os.fsdecode(src)
        dst_text = os.fsdecode(dst)
        event = {
            "operation": operation,
            "src": os.path.abspath(src_text),
            "dst": os.path.abspath(dst_text),
            "src_existed": os.path.isfile(src_text),
        }
        with open(_event_log, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(event) + "\n")
    except Exception:
        pass

def _rename(src, dst, *args, **kwargs):
    _record("rename", src, dst)
    return _original_rename(src, dst, *args, **kwargs)

def _replace(src, dst, *args, **kwargs):
    _record("replace", src, dst)
    return _original_replace(src, dst, *args, **kwargs)

os.rename = _rename
os.replace = _replace
''', encoding="utf-8")

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing do_backup.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    manifest_path = backup_dir / "manifest.json"
    assert manifest_path.is_file(), "Script did not create manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Generated manifest is invalid JSON: {exc}")
    assert isinstance(manifest, list), "Generated manifest must be a JSON array"
    assert manifest == expected, f"Expected dynamically derived manifest {expected}, got {manifest}"
    assert manifest == sorted(manifest), "Manifest paths are not sorted alphabetically"

    copied = []
    for root, _, files in os.walk(backup_dir):
        for name in files:
            if name not in ("manifest.json", "manifest.tmp"):
                copied.append((pathlib.Path(root) / name).relative_to(backup_dir).as_posix())
    assert sorted(copied) == expected, f"Expected copied files {expected}, got {sorted(copied)}"

    for relative in expected:
        source = app_dir / relative
        destination = backup_dir / relative
        assert destination.is_file(), f"Missing copied file {relative}"
        assert destination.read_bytes() == source.read_bytes(), f"Copied contents differ for {relative}"

    assert not (backup_dir / "manifest.tmp").exists(), "manifest.tmp remained after the atomic rename"
    assert state_path.read_bytes() == state_before, "state.json must not be updated"

    events = []
    if event_log.exists():
        for line in event_log.read_text(encoding="utf-8").splitlines():
            events.append(json.loads(line))
    expected_src = os.path.abspath(backup_dir / "manifest.tmp")
    expected_dst = os.path.abspath(manifest_path)
    assert any(
        event.get("src") == expected_src
        and event.get("dst") == expected_dst
        and event.get("src_existed") is True
        for event in events
    ), "Manifest was not atomically renamed from manifest.tmp to manifest.json"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
