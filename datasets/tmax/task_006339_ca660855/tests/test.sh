#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tarfile


def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def assert_archive_contents(archive_path, expected_files):
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        saw_root = False
        archived_files = {}

        for member in members:
            parts = [p for p in member.name.lstrip("./").split("/") if p not in ("", ".")]
            assert "raw_data" in parts, f"Archive member is outside raw_data: {member.name}"
            raw_index = len(parts) - 1 - parts[::-1].index("raw_data")
            suffix = parts[raw_index + 1:]

            if not suffix:
                assert member.isdir(), f"raw_data archive entry is not a directory: {member.name}"
                saw_root = True
                continue

            assert len(suffix) == 1, f"Unexpected archive directory structure: {member.name}"
            filename = suffix[0]
            assert filename in expected_files, f"Unexpected file in archive: {member.name}"
            assert member.isfile(), f"Archived item is not a regular file: {member.name}"
            assert filename not in archived_files, f"Duplicate archived file: {filename}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file: {member.name}"
            archived_files[filename] = extracted.read()

        assert saw_root, "Archive does not include the raw_data directory itself."
        assert archived_files == expected_files, "Archived files or contents do not match raw_data."


def test_backup_manager_script_exists():
    script_path = "/home/user/backup_manager.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."


def test_renamed_files():
    target_dir = "/home/user/raw_data"
    assert os.path.isdir(target_dir), f"{target_dir} does not exist."

    expected_files = {
        "Financial_Report_2023.csv": "Q1 Revenue: $1000\n",
        "Meeting_notes.txt": "Discussed architecture.\n",
        "daily_log.txt": "All systems operational.\n"
    }

    actual_files = os.listdir(target_dir)
    assert set(actual_files) == set(expected_files.keys()), f"Files in {target_dir} do not match expected renamed files. Found: {actual_files}"

    for filename, content in expected_files.items():
        filepath = os.path.join(target_dir, filename)
        with open(filepath, "r") as f:
            actual_content = f.read()
        assert actual_content == content, f"Content of {filename} was altered."


def test_manifest():
    manifest_path = "/home/user/manifest.sha256"
    assert os.path.isfile(manifest_path), f"{manifest_path} does not exist."

    expected_hashes = {
        "Financial_Report_2023.csv": "10e08f8dc1c7ef5ab7492cda19dd8880fc4aef2b8eec1daab9a06cc5b3ebcfb9",
        "Meeting_notes.txt": "ea6fb59b151cb829cb8c5a2c2864caef20c5dbcd6c6dfbf46e01a8ed291a27e7",
        "daily_log.txt": "5ce83344a04d6e902b4bc65839b207eb3d3bd088e8b0fb6b4f7626fc965f37bc"
    }

    with open(manifest_path, "r") as f:
        manifest_lines = f.read().strip().splitlines()

    assert len(manifest_lines) == 3, f"Manifest should contain exactly 3 lines, found {len(manifest_lines)}."

    manifest_dict = {}
    for line in manifest_lines:
        parts = line.strip().split()
        assert len(parts) >= 2, f"Invalid manifest line format: {line}"
        hash_val = parts[0]
        filename = os.path.basename(parts[1])
        manifest_dict[filename] = hash_val

    for filename, expected_hash in expected_hashes.items():
        assert filename in manifest_dict, f"{filename} missing from manifest."
        assert manifest_dict[filename] == expected_hash, f"Hash mismatch for {filename} in manifest."


def test_archive():
    archive_path = "/home/user/archive.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()

    expected_basenames = ["Financial_Report_2023.csv", "Meeting_notes.txt", "daily_log.txt"]
    found_files = 0
    for name in names:
        basename = os.path.basename(name)
        if basename in expected_basenames:
            found_files += 1

    assert found_files == 3, f"Archive does not contain all expected files. Found names: {names}"

    assert_archive_contents(archive_path, {
        "Financial_Report_2023.csv": b"Q1 Revenue: $1000\n",
        "Meeting_notes.txt": b"Discussed architecture.\n",
        "daily_log.txt": b"All systems operational.\n",
    })


def test_backup_log():
    log_path = "/home/user/backup_log.txt"
    archive_path = "/home/user/archive.tar.gz"

    assert os.path.isfile(log_path), f"{log_path} does not exist."
    assert os.path.isfile(archive_path), "Archive must exist to test backup log."

    actual_archive_hash = get_sha256(archive_path)

    with open(log_path, "r") as f:
        log_content = f.read().strip().splitlines()

    assert len(log_content) == 2, f"Backup log should have exactly 2 lines, found {len(log_content)}."
    assert log_content[0].startswith("Archive Checksum: "), "First line of backup log must start with 'Archive Checksum: '"
    logged_hash = log_content[0].replace("Archive Checksum: ", "").strip()
    assert logged_hash == actual_archive_hash, f"Logged archive checksum ({logged_hash}) does not match actual checksum ({actual_archive_hash})."
    assert log_content[1].startswith("Files Archived: "), "Second line of backup log must start with 'Files Archived: '"
    logged_count = log_content[1].replace("Files Archived: ", "").strip()
    assert logged_count == "3", f"Logged files archived count should be 3, found '{logged_count}'."


def test_script_executes_on_fresh_inputs():
    script_path = "/home/user/backup_manager.sh"
    target_dir = "/home/user/raw_data"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    shutil.rmtree(target_dir)
    os.makedirs(target_dir, mode=0o777)

    inputs = {
        "Quarterly Results.XML": b"<result>novel-481</result>\n",
        "Team Photo.JpEg": b"not-a-real-image\x00\x81\n",
        "No Extension": b"extensionless data\n",
        "already_clean.bin": b"\x00\x01\x02dynamic payload\xff",
    }
    expected = {
        "Quarterly_Results.xml": inputs["Quarterly Results.XML"],
        "Team_Photo.jpeg": inputs["Team Photo.JpEg"],
        "No_Extension": inputs["No Extension"],
        "already_clean.bin": inputs["already_clean.bin"],
    }

    for filename, content in inputs.items():
        path = os.path.join(target_dir, filename)
        with open(path, "wb") as f:
            f.write(content)
        os.chmod(path, 0o666)

    for artifact in ("/home/user/manifest.sha256", "/home/user/archive.tar.gz", "/home/user/backup_log.txt"):
        if os.path.lexists(artifact):
            os.remove(artifact)

    result = subprocess.run(
        ["/bin/bash", script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"backup_manager.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"

    assert set(os.listdir(target_dir)) == set(expected), "Script did not rename every fresh input correctly."
    for filename, content in expected.items():
        with open(os.path.join(target_dir, filename), "rb") as f:
            assert f.read() == content, f"Script altered the content of {filename}."

    manifest_path = "/home/user/manifest.sha256"
    assert os.path.isfile(manifest_path), "Script did not generate manifest.sha256."
    with open(manifest_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert len(lines) == len(expected), "Fresh manifest has the wrong number of entries."

    manifest = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
        assert match, f"Manifest is not in standard sha256sum format: {line!r}"
        filename = os.path.basename(match.group(2))
        assert filename not in manifest, f"Duplicate manifest entry for {filename}."
        manifest[filename] = match.group(1)

    expected_hashes = {name: hashlib.sha256(content).hexdigest() for name, content in expected.items()}
    assert manifest == expected_hashes, "Fresh manifest does not describe the renamed files and their actual contents."

    archive_path = "/home/user/archive.tar.gz"
    assert os.path.isfile(archive_path), "Script did not generate archive.tar.gz."
    assert tarfile.is_tarfile(archive_path), "Generated archive.tar.gz is not a tar archive."
    assert_archive_contents(archive_path, expected)

    log_path = "/home/user/backup_log.txt"
    assert os.path.isfile(log_path), "Script did not generate backup_log.txt."
    with open(log_path, "r", encoding="utf-8") as f:
        log_lines = f.read().splitlines()
    assert log_lines == [
        f"Archive Checksum: {get_sha256(archive_path)}",
        f"Files Archived: {len(expected)}",
    ], "Fresh backup log does not exactly match the generated archive and file count."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
