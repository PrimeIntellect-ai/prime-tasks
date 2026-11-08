#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import tarfile

APP_LOGS_DIR = "/home/user/app_logs"
OLD_LOG = os.path.join(APP_LOGS_DIR, "log_old.txt")
RECENT_LOG1 = os.path.join(APP_LOGS_DIR, "log_recent1.txt")
RECENT_LOG2 = os.path.join(APP_LOGS_DIR, "log_recent2.txt")
ERROR_SUMMARY = "/home/user/error_summary.txt"
ARCHIVE_PATH = "/home/user/processed_logs.tar.gz"

EXPECTED_OLD = (
    b"[INFO] System started\n"
    b"[TRACE] Loading modules\n"
    b"[ERROR] Module A failed\n"
    b"[TRACE] Retrying\n"
)
EXPECTED_RECENT = {
    "log_recent1.txt": (
        b"[INFO] System running\n"
        b"[ERROR] Memory limit exceeded\n"
        b"[ERROR] GC failed\n"
    ),
    "log_recent2.txt": b"[INFO] User logged in\n",
}
EXPECTED_SUMMARY = (
    b"[ERROR] Memory limit exceeded\n"
    b"[ERROR] GC failed\n"
)


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def test_old_log_untouched():
    """Verify that log_old.txt was not modified and still contains all original lines."""
    assert os.path.isfile(OLD_LOG), f"Old log file {OLD_LOG} is missing."
    content = read_bytes(OLD_LOG)
    assert b"[TRACE]" in content, f"Old log file {OLD_LOG} should not have been modified and should still contain [TRACE]."
    assert content == EXPECTED_OLD, f"Old log file {OLD_LOG} was modified."


def test_recent_logs_cleaned_without_losing_other_lines():
    """Verify that only TRACE lines were removed from each recent log."""
    for log_path in [RECENT_LOG1, RECENT_LOG2]:
        assert os.path.isfile(log_path), f"Recent log file {log_path} is missing."
        content = read_bytes(log_path)
        assert b"[TRACE]" not in content, f"Recent log file {log_path} still contains [TRACE] lines."
        expected = EXPECTED_RECENT[os.path.basename(log_path)]
        assert content == expected, f"Recent log file {log_path} did not preserve exactly the non-TRACE lines."


def test_error_summary_contents():
    """Verify that the summary consists exactly of errors from recent logs."""
    assert os.path.isfile(ERROR_SUMMARY), f"Error summary file {ERROR_SUMMARY} is missing."
    content = read_bytes(ERROR_SUMMARY)
    assert b"[ERROR] Memory limit exceeded" in content, "Error summary is missing '[ERROR] Memory limit exceeded'."
    assert b"[ERROR] GC failed" in content, "Error summary is missing '[ERROR] GC failed'."
    assert b"Module A failed" not in content, "Error summary incorrectly contains errors from the old log."
    assert content == EXPECTED_SUMMARY, "Error summary has missing, duplicate, reordered, or extra content."


def test_archive_contents_and_payloads():
    """Verify that the archive contains only the two cleaned logs with exact contents."""
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} is missing."

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]
        base_names = [os.path.basename(name.rstrip("/")) for name in names]

        assert "log_recent1.txt" in base_names, "log_recent1.txt is missing from the archive."
        assert "log_recent2.txt" in base_names, "log_recent2.txt is missing from the archive."
        assert "log_old.txt" not in base_names, "log_old.txt should not be in the archive."

        for name in names:
            assert not name.startswith("/"), f"Archive contains absolute path: {name}"
            normalized = posixpath.normpath(name)
            assert normalized != ".." and not normalized.startswith("../"), f"Archive contains a parent-traversal path: {name}"

        file_members = [member for member in members if not member.isdir()]
        archived_basenames = [os.path.basename(member.name.rstrip("/")) for member in file_members]
        assert sorted(archived_basenames) == sorted(EXPECTED_RECENT), "Archive contains missing, duplicate, or extra non-directory members."
        assert all(member.isreg() for member in file_members), "Archived logs must be regular files, not links or special files."

        normalized_files = [posixpath.normpath(member.name) for member in file_members]
        allowed_directories = {"."}
        for path in normalized_files:
            parent = posixpath.dirname(path)
            while parent and parent != ".":
                allowed_directories.add(parent)
                parent = posixpath.dirname(parent)
        for member in members:
            if member.isdir():
                assert posixpath.normpath(member.name) in allowed_directories, f"Archive contains an unrelated directory: {member.name}"

        for member in file_members:
            basename = os.path.basename(member.name)
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived member {member.name}."
            payload = extracted.read()
            assert payload == EXPECTED_RECENT[basename], f"Archived file {member.name} has incorrect content."
            assert payload == read_bytes(os.path.join(APP_LOGS_DIR, basename)), f"Archived file {member.name} does not match the cleaned on-disk log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
