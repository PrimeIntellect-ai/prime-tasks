#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import tarfile
import pytest

IPV4_PATTERN = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
PLACEHOLDER = "XXX.XXX.XXX.XXX"


def expected_manifest_lines():
    data_dir = "/home/user/recovery/data"
    lines = []
    if os.path.isdir(data_dir):
        for filename in os.listdir(data_dir):
            if filename.endswith(".dat"):
                filepath = os.path.join(data_dir, filename)
                if os.path.isfile(filepath) and os.path.getsize(filepath) > 10240:
                    with open(filepath, "rb") as f:
                        lines.append(f"{filename}: {f.read(4).hex().lower()}")
    return sorted(lines)


def expected_logs():
    recovery_logs_dir = "/home/user/recovery/logs"
    result = {}
    if os.path.isdir(recovery_logs_dir):
        for filename in os.listdir(recovery_logs_dir):
            source = os.path.join(recovery_logs_dir, filename)
            if filename.endswith(".log") and os.path.isfile(source):
                with open(source, "r") as f:
                    original = f.read()
                result[filename] = IPV4_PATTERN.sub(PLACEHOLDER, original)
    return result


def test_archive_manifest_content():
    manifest_path = "/home/user/archive_manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_manifest_lines(), \
        "Manifest contents do not match expected format, files, or sort order."


def test_clean_logs_redaction():
    clean_logs_dir = "/home/user/clean_logs"
    assert os.path.isdir(clean_logs_dir), f"Directory {clean_logs_dir} is missing"

    for filename, expected_content in expected_logs().items():
        clean_log_path = os.path.join(clean_logs_dir, filename)
        assert os.path.isfile(clean_log_path), \
            f"Redacted log file {filename} missing in {clean_logs_dir}"

        with open(clean_log_path, "r") as f:
            content = f.read()

        found_ips = IPV4_PATTERN.findall(content)
        assert not found_ips, f"Found unredacted IP addresses in {filename}: {found_ips}"
        assert PLACEHOLDER in content, \
            f"Expected redacted placeholder {PLACEHOLDER} not found in {filename}"
        assert content == expected_content, \
            f"Redacted log {filename} does not equal its source with IPv4 addresses substituted"


def normalize_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def test_tarball_contents():
    tarball_path = "/home/user/safe_backup.tar.gz"
    assert os.path.isfile(tarball_path), f"Tarball missing at {tarball_path}"

    expected_log_contents = expected_logs()
    expected_names = {"archive_manifest.txt", "clean_logs"}
    expected_names.update(f"clean_logs/{name}" for name in expected_log_contents)

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getmembers()
            normalized = [normalize_member_name(member.name) for member in members]

            assert all(name and not name.startswith("/") and ".." not in name.split("/")
                       for name in normalized), "Archive contains an unsafe or invalid path"
            assert len(normalized) == len(set(normalized)), "Archive contains duplicate entries"

            root_items = {name.split("/", 1)[0] for name in normalized}
            assert root_items == {"archive_manifest.txt", "clean_logs"}, \
                "Archive must contain exactly archive_manifest.txt and clean_logs at its root"
            assert set(normalized) == expected_names, \
                "Archive does not contain exactly the manifest, clean_logs directory, and all required logs"

            assert any(name.endswith("archive_manifest.txt") for name in normalized), \
                "archive_manifest.txt missing from tarball"
            assert any(name.endswith("clean_logs/access.log") or
                       name.endswith("clean_logs/system.log") for name in normalized), \
                "clean_logs directory or its contents missing from tarball"
            for name in normalized:
                assert "recovery" not in name, "Original recovery directory found in tarball"

            by_name = dict(zip(normalized, members))
            assert by_name["archive_manifest.txt"].isfile(), \
                "Archived archive_manifest.txt is not a regular file"
            assert by_name["clean_logs"].isdir(), \
                "Archived clean_logs entry is not a directory"

            manifest_file = tar.extractfile(by_name["archive_manifest.txt"])
            assert manifest_file is not None, "Could not read archived manifest"
            archived_manifest = manifest_file.read().decode("utf-8")
            archived_manifest_lines = [line.strip() for line in archived_manifest.splitlines() if line.strip()]
            assert archived_manifest_lines == expected_manifest_lines(), \
                "Archived manifest content does not match the required manifest"

            with open("/home/user/archive_manifest.txt", "r") as f:
                disk_manifest = f.read()
            assert archived_manifest == disk_manifest, \
                "Archived manifest differs from /home/user/archive_manifest.txt"

            for filename, expected_content in expected_log_contents.items():
                archive_name = f"clean_logs/{filename}"
                member = by_name[archive_name]
                assert member.isfile(), f"Archived log {archive_name} is not a regular file"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archived log {archive_name}"
                content = extracted.read().decode("utf-8")

                assert not IPV4_PATTERN.findall(content), \
                    f"Unredacted IP found in tarball log: {archive_name}"
                assert PLACEHOLDER in content, \
                    f"Redacted placeholder missing in tarball log: {archive_name}"
                assert content == expected_content, \
                    f"Archived log {archive_name} does not equal its source after substitution"

                with open(os.path.join("/home/user/clean_logs", filename), "r") as f:
                    assert content == f.read(), \
                        f"Archived log {archive_name} differs from the clean log on disk"

    except (tarfile.ReadError, EOFError):
        pytest.fail(f"File at {tarball_path} is not a valid gzip-compressed tarball")


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
