#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import tarfile
import subprocess
import time
import secrets
from pathlib import Path
import pytest


def test_script_exists_and_executable():
    script_path = "/home/user/config_tracker.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_directories_exist():
    dirs = [
        "/home/user/legacy_configs",
        "/home/user/staging",
        "/home/user/backups"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."


def test_backup_files():
    backups_dir = "/home/user/backups"
    tar_files = glob.glob(os.path.join(backups_dir, "backup_*.tar.gz"))
    assert len(tar_files) == 2, f"Expected exactly 2 tar.gz files in {backups_dir}, found {len(tar_files)}."

    snar_file = os.path.join(backups_dir, "snapshot.snar")
    assert os.path.isfile(snar_file), f"Snapshot file {snar_file} does not exist."
    with open(snar_file, "rb") as f:
        assert f.read(8).startswith(b"GNU tar-"), "snapshot.snar is not GNU tar listed-incremental metadata."


def test_latest_tarball_contents():
    backups_dir = "/home/user/backups"
    tar_files = glob.glob(os.path.join(backups_dir, "backup_*.tar.gz"))
    assert tar_files, "No backup tar.gz files found."

    # Sort by modification time to get the latest
    latest_tar = max(tar_files, key=os.path.getmtime)

    with tarfile.open(latest_tar, "r:gz") as tar:
        names = tar.getnames()

        # Check that app.conf is in the archive
        has_app_conf = any(name.endswith("app.conf") for name in names)
        assert has_app_conf, f"app.conf not found in the latest tarball {latest_tar}."

        # Check that db.conf is NOT in the archive
        has_db_conf = any(name.endswith("db.conf") for name in names)
        assert not has_db_conf, f"db.conf should not be in the latest incremental tarball {latest_tar}."

        # Extract app.conf to verify its content and encoding
        app_conf_member = next(m for m in tar.getmembers() if m.name.endswith("app.conf"))
        f = tar.extractfile(app_conf_member)
        content = f.read()

        try:
            text_content = content.decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail("app.conf in the latest tarball is not valid UTF-8.")

        assert "téléphone=12345" in text_content, "Expected text 'téléphone=12345' not found in app.conf."
        assert "serveur=dédié" in text_content, "Expected text 'serveur=dédié' not found in app.conf."


def test_latest_archived_log():
    log_file = "/home/user/latest_archived.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
        log_content = f.read()

    assert "app.conf" in log_content, "app.conf is missing from latest_archived.log."
    assert "db.conf" not in log_content, "db.conf should not be in latest_archived.log."


def _run_script(script, source, staging, backups):
    result = subprocess.run(
        [script, str(source), str(staging), str(backups)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def _regular_members(archive):
    with tarfile.open(archive, "r:gz") as tar:
        return [m for m in tar.getmembers() if m.isfile()]


def test_script_on_independent_inputs(tmp_path):
    script = "/home/user/config_tracker.sh"

    # Verify the required exact argument count without touching the main test data.
    no_args = subprocess.run([script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert no_args.returncode != 0, "Script must reject calls with fewer than three arguments."

    arity_root = tmp_path / "arity"
    arity_source = arity_root / "source"
    arity_staging = arity_root / "staging"
    arity_backups = arity_root / "backups"
    arity_source.mkdir(parents=True)
    arity_staging.mkdir()
    arity_backups.mkdir()
    (arity_source / "arity.conf").write_bytes(b"value=test\n")
    too_many = subprocess.run(
        [script, str(arity_source), str(arity_staging), str(arity_backups), "extra"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert too_many.returncode != 0, "Script must reject calls with more than three arguments."

    token = secrets.token_hex(6)
    source = tmp_path / ("source_" + token)
    staging = tmp_path / ("staging_" + token)
    backups = tmp_path / ("backups_" + token)
    nested = source / ("nested_" + token)
    nested.mkdir(parents=True)
    staging.mkdir()
    backups.mkdir()

    changed_name = "primary_" + token + ".conf"
    unchanged_name = "secondary_" + token + ".conf"
    ignored_name = "ignored_" + token + ".txt"
    changed = source / changed_name
    unchanged = nested / unchanged_name

    initial_text = "clé_" + token + "=café\n"
    appended_text = "serveur_" + token + "=dédié\n"
    unchanged_text = "données_" + token + "=été\n"
    changed.write_bytes(initial_text.encode("iso-8859-1"))
    unchanged.write_bytes(unchanged_text.encode("iso-8859-1"))
    (source / ignored_name).write_bytes(b"not a configuration file\n")
    (staging / "stale.conf").write_bytes(b"must be removed\n")

    _run_script(script, source, staging, backups)

    first_archives = set(backups.glob("backup_*.tar.gz"))
    assert len(first_archives) == 1, "First execution must create exactly one timestamped gzip tar archive."
    snapshot = backups / "snapshot.snar"
    assert snapshot.is_file(), "First execution did not create snapshot.snar."
    assert snapshot.read_bytes().startswith(b"GNU tar-"), "snapshot.snar is not GNU tar listed-incremental metadata."
    assert not (staging / "stale.conf").exists(), "The script did not clear stale staging contents."
    assert (staging / changed_name).read_bytes() == initial_text.encode("utf-8")
    assert (staging / nested.name / unchanged_name).read_bytes() == unchanged_text.encode("utf-8")
    assert not (staging / ignored_name).exists(), "A non-.conf file was copied into staging."

    first_archive = next(iter(first_archives))
    first_members = _regular_members(first_archive)
    first_basenames = {Path(m.name).name for m in first_members}
    assert first_basenames == {changed_name, unchanged_name}, (
        f"First archive contained the wrong regular files: {first_basenames}"
    )
    with tarfile.open(first_archive, "r:gz") as tar:
        contents = {Path(m.name).name: tar.extractfile(m).read() for m in tar.getmembers() if m.isfile()}
    assert contents[changed_name].decode("utf-8") == initial_text
    assert contents[unchanged_name].decode("utf-8") == unchanged_text

    first_log = Path("/home/user/latest_archived.log").read_text(encoding="utf-8", errors="replace")
    assert changed_name in first_log and unchanged_name in first_log
    assert ignored_name not in first_log

    time.sleep(2.1)
    changed.write_bytes((initial_text + appended_text).encode("iso-8859-1"))
    _run_script(script, source, staging, backups)

    all_archives = set(backups.glob("backup_*.tar.gz"))
    assert len(all_archives) == 2, "Second execution must create a second timestamped gzip tar archive."
    second_archive = next(iter(all_archives - first_archives))
    second_members = _regular_members(second_archive)
    second_basenames = {Path(m.name).name for m in second_members}
    assert second_basenames == {changed_name}, (
        "The second incremental archive must contain only the modified .conf file; "
        f"found {second_basenames}"
    )

    with tarfile.open(second_archive, "r:gz") as tar:
        member = next(m for m in tar.getmembers() if m.isfile() and Path(m.name).name == changed_name)
        archived_bytes = tar.extractfile(member).read()
    assert archived_bytes.decode("utf-8") == initial_text + appended_text
    assert (staging / changed_name).read_bytes() == (initial_text + appended_text).encode("utf-8")

    second_log = Path("/home/user/latest_archived.log").read_text(encoding="utf-8", errors="replace")
    assert changed_name in second_log, "Modified file is missing from latest_archived.log."
    assert unchanged_name not in second_log, "Unchanged file was incorrectly logged as archived."
    assert ignored_name not in second_log
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
