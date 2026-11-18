#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

DATA_DIR = "/home/user/data"
ARCHIVE_DIR = "/home/user/archive"
DEPLOY_RC = "/home/user/.deploy_rc"
SCRIPT_PATH = "/home/user/storage_janitor.py"
REPORT_PATH = "/home/user/janitor_report.json"


def test_deploy_rc_exists_and_exports():
    assert os.path.exists(DEPLOY_RC), f"{DEPLOY_RC} does not exist"
    with open(DEPLOY_RC, "r") as f:
        content = f.read()

    assert "JANITOR_DATA_DIR=/home/user/data" in content, "Missing or incorrect JANITOR_DATA_DIR export in .deploy_rc"
    assert "JANITOR_ARCHIVE_DIR=/home/user/archive" in content, "Missing or incorrect JANITOR_ARCHIVE_DIR export in .deploy_rc"
    assert "JANITOR_QUOTA_KB=1500" in content, "Missing or incorrect JANITOR_QUOTA_KB export in .deploy_rc"


def test_archive_dir_exists():
    assert os.path.isdir(ARCHIVE_DIR), f"{ARCHIVE_DIR} is not a directory or does not exist"


def test_files_moved_correctly():
    for f in ["file1.txt", "file3.txt"]:
        archive_path = os.path.join(ARCHIVE_DIR, f)
        assert os.path.exists(archive_path), f"{f} was not moved to the archive directory"
        data_path = os.path.join(DATA_DIR, f)
        assert not os.path.exists(data_path), f"{f} should no longer exist in the data directory"

    for f in ["file2.txt", "file4.txt"]:
        data_path = os.path.join(DATA_DIR, f)
        assert os.path.exists(data_path), f"{f} should remain in the data directory"
        archive_path = os.path.join(ARCHIVE_DIR, f)
        assert not os.path.exists(archive_path), f"{f} should not have been moved to the archive directory"


def test_script_exists_and_uses_subprocess():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "subprocess" in content, "The script does not seem to use the subprocess module"
    assert "grep" in content, "The script does not seem to use grep"
    assert "awk" in content, "The script does not seem to use awk"


def test_janitor_report_json():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} does not exist"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON")

    assert "initial_size_kb" in report, "Missing 'initial_size_kb' in report"
    assert "quota_exceeded" in report, "Missing 'quota_exceeded' in report"
    assert "files_archived" in report, "Missing 'files_archived' in report"
    assert "final_size_kb" in report, "Missing 'final_size_kb' in report"

    assert report["quota_exceeded"] is True, "'quota_exceeded' should be true"

    archived = report["files_archived"]
    assert isinstance(archived, list), "'files_archived' must be a list"
    assert set(archived) == {"file1.txt", "file3.txt"}, f"Expected file1.txt and file3.txt to be archived, got {archived}"

    assert isinstance(report["initial_size_kb"], (int, float)), "'initial_size_kb' must be a number"
    assert report["initial_size_kb"] > 2000, "Initial size should be > 2000 KB"

    assert isinstance(report["final_size_kb"], (int, float)), "'final_size_kb' must be a number"
    assert report["final_size_kb"] < 1500, "Final size should be < 1500 KB"


def directory_size_kb(path):
    return sum(p.stat().st_size for p in Path(path).rglob("*") if p.is_file()) / 1024.0


def load_report():
    with open(REPORT_PATH, "r") as f:
        return json.load(f)


def run_janitor(data_dir, archive_dir, quota):
    env = os.environ.copy()
    env.update({
        "JANITOR_DATA_DIR": str(data_dir),
        "JANITOR_ARCHIVE_DIR": str(archive_dir),
        "JANITOR_QUOTA_KB": str(quota),
    })
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"storage_janitor.py failed on a fresh fixture.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def install_tool_wrappers(log_path):
    backups = []
    for tool in ("grep", "awk"):
        original = Path("/usr/bin") / tool
        backup = Path("/usr/bin") / (tool + ".verifier-real")
        assert original.exists(), f"Required utility {original} is missing"
        assert not backup.exists(), f"Unexpected stale verifier backup {backup}"
        os.replace(original, backup)
        original.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' '{tool}' >> '{log_path}'\n"
            f"exec '{backup}' \"$@\"\n"
        )
        original.chmod(0o755)
        backups.append((original, backup))
    return backups


def restore_tool_wrappers(backups):
    for original, backup in reversed(backups):
        try:
            if original.exists() or original.is_symlink():
                original.unlink()
        finally:
            if backup.exists() or backup.is_symlink():
                os.replace(backup, original)


def test_script_executes_on_unseen_fixtures_and_computes_report(tmp_path):
    token = secrets.token_hex(6)
    names = {
        "processed_a": f"done_{token}_a.dat",
        "pending": f"waiting_{token}.dat",
        "processed_b": f"done_{token}_b.dat",
        "error": f"failed_{token}.dat",
    }

    data_dir = tmp_path / "over_quota_data"
    archive_dir = tmp_path / "over_quota_archive"
    data_dir.mkdir()
    archive_dir.mkdir()

    sizes = {
        names["processed_a"]: 131072 + secrets.randbelow(4096),
        names["pending"]: 125952 + secrets.randbelow(4096),
        names["processed_b"]: 136192 + secrets.randbelow(4096),
        names["error"]: 122880 + secrets.randbelow(4096),
    }
    for index, (name, size) in enumerate(sizes.items()):
        (data_dir / name).write_bytes(bytes([65 + index]) * size)

    manifest = data_dir / "manifest.txt"
    manifest.write_text(
        f"{names['processed_a']} STATUS=PROCESSED\n"
        f"{names['pending']} STATUS=PENDING\n"
        f"{names['processed_b']} STATUS=PROCESSED\n"
        f"{names['error']} STATUS=ERROR\n"
    )

    expected_initial = directory_size_kb(data_dir)
    quota = 300
    assert expected_initial > quota

    tool_log = tmp_path / "tools-used.log"
    backups = []
    try:
        backups = install_tool_wrappers(tool_log)
        run_janitor(data_dir, archive_dir, quota)
    finally:
        restore_tool_wrappers(backups)

    assert tool_log.exists(), "The executed script did not invoke grep or awk"
    invoked = tool_log.read_text().splitlines()
    assert "grep" in invoked, "The executed script did not invoke grep"
    assert "awk" in invoked, "The executed script did not invoke awk"

    processed = {names["processed_a"], names["processed_b"]}
    unprocessed = {names["pending"], names["error"]}
    for name in processed:
        assert not (data_dir / name).exists(), f"Processed fixture {name} was not removed from data"
        assert (archive_dir / name).is_file(), f"Processed fixture {name} was not archived"
    for name in unprocessed:
        assert (data_dir / name).is_file(), f"Unprocessed fixture {name} was incorrectly removed"
        assert not (archive_dir / name).exists(), f"Unprocessed fixture {name} was incorrectly archived"

    expected_final = directory_size_kb(data_dir)
    report = load_report()
    assert set(report) == {"initial_size_kb", "quota_exceeded", "files_archived", "final_size_kb"}
    assert report["quota_exceeded"] is True
    assert isinstance(report["files_archived"], list)
    assert set(report["files_archived"]) == processed
    assert isinstance(report["initial_size_kb"], (int, float)) and not isinstance(report["initial_size_kb"], bool)
    assert isinstance(report["final_size_kb"], (int, float)) and not isinstance(report["final_size_kb"], bool)
    assert report["initial_size_kb"] == pytest.approx(expected_initial, abs=1e-6)
    assert report["final_size_kb"] == pytest.approx(expected_final, abs=1e-6)

    below_data = tmp_path / "below_quota_data"
    below_archive = tmp_path / "below_quota_archive"
    below_data.mkdir()
    below_archive.mkdir()
    below_name = f"small_{secrets.token_hex(5)}.txt"
    (below_data / below_name).write_bytes(b"x" * 8193)
    (below_data / "manifest.txt").write_text(f"{below_name} STATUS=PROCESSED\n")
    below_initial = directory_size_kb(below_data)

    run_janitor(below_data, below_archive, 10000)

    assert (below_data / below_name).is_file(), "A processed file was archived even though quota was not exceeded"
    assert not (below_archive / below_name).exists()
    below_report = load_report()
    assert set(below_report) == {"initial_size_kb", "quota_exceeded", "files_archived", "final_size_kb"}
    assert below_report["quota_exceeded"] is False
    assert below_report["files_archived"] == []
    assert below_report["initial_size_kb"] == pytest.approx(below_initial, abs=1e-6)
    assert below_report["final_size_kb"] == pytest.approx(below_initial, abs=1e-6)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
