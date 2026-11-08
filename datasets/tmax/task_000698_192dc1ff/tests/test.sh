#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT
export PATH="/opt/rust/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_safe_backup.py
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/workspace/safe_backup")
MANIFEST = PROJECT / "Cargo.toml"
MAIN_RS = PROJECT / "src/main.rs"
TARGET_DIR = Path("/tmp/safe_backup_verifier_target")


def run_checked(command, timeout=60):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed with status {result.returncode}: {' '.join(map(str, command))}\n"
        f"{result.stdout}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def compiled_and_executed_tool():
    assert PROJECT.is_dir(), "/workspace/safe_backup is not a directory"
    assert MANIFEST.is_file(), "/workspace/safe_backup/Cargo.toml is missing"
    assert MAIN_RS.is_file(), "/workspace/safe_backup/src/main.rs is missing"

    metadata_result = run_checked([
        "cargo", "metadata", "--no-deps", "--format-version", "1",
        "--manifest-path", str(MANIFEST),
    ])
    metadata = json.loads(metadata_result.stdout)
    manifest_real = MANIFEST.resolve()
    package = next(
        (p for p in metadata["packages"] if Path(p["manifest_path"]).resolve() == manifest_real),
        None,
    )
    assert package is not None, "Cargo metadata did not contain the submitted package"
    bin_targets = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bin_targets, "The submitted Cargo project has no Rust binary target"
    named = [t for t in bin_targets if t["name"] == "safe_backup"]
    assert len(named) == 1 or (not named and len(bin_targets) == 1), (
        "Could not uniquely identify the backup binary target"
    )
    binary_name = (named[0] if named else bin_targets[0])["name"]

    shutil.rmtree(TARGET_DIR, ignore_errors=True)
    run_checked([
        "cargo", "build", "--manifest-path", str(MANIFEST),
        "--target-dir", str(TARGET_DIR), "--bin", binary_name,
    ], timeout=180)

    binary = TARGET_DIR / "debug" / binary_name
    assert binary.is_file(), f"Compiled binary was not produced at {binary}"
    assert os.access(binary, os.X_OK), f"Compiled artifact at {binary} is not executable"

    shutil.rmtree("/workspace/backup", ignore_errors=True)
    log = Path("/workspace/backup.log")
    if log.exists() or log.is_symlink():
        log.unlink()
    run_checked([str(binary), "/workspace/backup_config.json"], timeout=30)

    yield binary


def test_backup_files_exist():
    # Check that new files are backed up
    assert os.path.exists("/workspace/backup/file_new.txt"), "/workspace/backup/file_new.txt was not backed up."
    assert os.path.exists("/workspace/backup/dirA/file_new_2.txt"), "/workspace/backup/dirA/file_new_2.txt was not backed up."
    assert os.path.exists("/workspace/backup/dirB/nested/link_to_A/file_new_2.txt"), "/workspace/backup/dirB/nested/link_to_A/file_new_2.txt was not backed up."


def test_old_file_not_backed_up():
    # Check that old files are NOT backed up
    assert not os.path.exists("/workspace/backup/file_old.txt"), "/workspace/backup/file_old.txt should not be backed up because it is older than last_backup_time."


def test_backup_log_contains_loops():
    log_path = "/workspace/backup.log"
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        log_content = f.read()

    expected_lines = [
        "LOOP DETECTED: /workspace/data/dirA/loop_link",
        "LOOP DETECTED: /workspace/data/dirB/nested/link_to_A/loop_link",
        "LOOP DETECTED: /workspace/data/dirC/self_loop"
    ]

    for expected_line in expected_lines:
        assert expected_line in log_content, f"Expected log line '{expected_line}' not found in {log_path}."


def test_tool_on_independent_configuration(compiled_and_executed_tool):
    binary = compiled_and_executed_tool
    case = Path("/tmp/safe_backup_verifier_case")
    shutil.rmtree(case, ignore_errors=True)
    source1 = case / "source_one"
    source2 = case / "source_two"
    destination = case / "result"
    (source1 / "tree").mkdir(parents=True)
    (source1 / "empty").mkdir()
    source2.mkdir(parents=True)

    files = {
        source1 / "root_new.txt": ("root-new-content\n", 1800000001),
        source1 / "old.txt": ("must-not-copy-old\n", 1799999999),
        source1 / "exact_threshold.txt": ("must-not-copy-equal\n", 1800000000),
        source1 / "tree/deep.txt": ("deep-target-content\n", 1800000002),
        source2 / "second.txt": ("second-source-content\n", 1800000003),
    }
    for path, (content, timestamp) in files.items():
        path.write_text(content)
        os.utime(path, (timestamp, timestamp))

    os.symlink("tree/deep.txt", source1 / "alias_file.txt")
    os.symlink("tree", source1 / "alias_tree")
    os.symlink(str(source1), source1 / "tree/up_to_root")
    os.symlink(str(source1 / "empty"), source1 / "empty/self_loop")

    config = case / "dynamic_config.json"
    config.write_text(json.dumps({
        "sources": [str(source1), str(source2)],
        "destination": str(destination),
        "last_backup_time": 1800000000,
    }))

    workspace_log = Path("/workspace/backup.log")
    saved_log = workspace_log.read_bytes()
    try:
        workspace_log.unlink()
        run_checked([str(binary), str(config)], timeout=30)

        expected_contents = {
            destination / "root_new.txt": "root-new-content\n",
            destination / "tree/deep.txt": "deep-target-content\n",
            destination / "alias_file.txt": "deep-target-content\n",
            destination / "alias_tree/deep.txt": "deep-target-content\n",
            destination / "second.txt": "second-source-content\n",
        }
        for path, expected in expected_contents.items():
            assert path.is_file(), f"Expected backup file was not created: {path}"
            assert path.read_text() == expected, f"Backup content was incorrect for {path}"

        assert not (destination / "old.txt").exists(), "A file older than the threshold was copied"
        assert not (destination / "exact_threshold.txt").exists(), (
            "A file whose timestamp equals last_backup_time was copied"
        )

        assert workspace_log.is_file(), "/workspace/backup.log was not created during loop detection"
        log_lines = workspace_log.read_text().splitlines()
        expected_loops = [
            f"LOOP DETECTED: {source1}/tree/up_to_root",
            f"LOOP DETECTED: {source1}/alias_tree/up_to_root",
            f"LOOP DETECTED: {source1}/empty/self_loop",
        ]
        for line in expected_loops:
            assert line in log_lines, f"Expected exact loop log line was missing: {line}"
    finally:
        workspace_log.write_bytes(saved_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_safe_backup.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi
