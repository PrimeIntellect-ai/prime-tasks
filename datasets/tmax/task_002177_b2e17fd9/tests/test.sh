#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import tarfile
import pytest


def test_bad_links_logged_and_removed():
    log_file = "/home/user/bad_links.txt"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_bad_links = [
        "/home/user/project_root/dirA/link_to_B",
        "/home/user/project_root/dirB/link_to_A",
        "/home/user/project_root/docs/broken_link"
    ]

    assert lines == sorted(expected_bad_links), f"Contents of {log_file} are incorrect or not sorted properly."

    for link in expected_bad_links:
        assert not os.path.exists(link) and not os.path.islink(link), f"Problematic symlink {link} was not deleted."


def test_configs_redacted():
    conf_files = [
        "/home/user/project_root/configs/db.conf",
        "/home/user/project_root/configs/api.conf"
    ]

    for conf in conf_files:
        assert os.path.isfile(conf), f"Config file {conf} is missing."
        with open(conf, "r") as f:
            lines = f.readlines()

        password_found = False
        for line in lines:
            if line.startswith("PASSWORD="):
                assert line.strip() == "PASSWORD=REDACTED", f"Password not redacted correctly in {conf}."
                password_found = True

        assert password_found, f"No PASSWORD= line found in {conf}."


def test_skipped_symlinks_logged():
    log_file = "/home/user/skipped_symlinks.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_skipped = [
        "/home/user/project_root/dirA/readme_link"
    ]

    assert lines == sorted(expected_skipped), f"Contents of {log_file} are incorrect."


def test_safe_archive_created_and_contents():
    archive_file = "/home/user/safe_archive.tar.gz"
    assert os.path.isfile(archive_file), f"Archive {archive_file} does not exist."

    expected_files = {
        "dirA/fileA.txt",
        "dirB/fileB.txt",
        "configs/db.conf",
        "configs/api.conf",
        "docs/readme.txt"
    }

    found_files = set()
    with tarfile.open(archive_file, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile():
                # Allow paths to be prefixed with project_root/ or just relative
                name = member.name
                if name.startswith("project_root/"):
                    name = name[len("project_root/"):]
                elif name.startswith("/home/user/project_root/"):
                    name = name[len("/home/user/project_root/"):]
                elif name.startswith("./"):
                    name = name[2:]
                found_files.add(name)

    for f in expected_files:
        assert f in found_files, f"Expected file {f} is missing from the tar archive."

    # Ensure no bad links are in the tar
    bad_names = {"dirA/link_to_B", "dirB/link_to_A", "docs/broken_link"}
    for b in bad_names:
        assert b not in found_files, f"Problematic link {b} was included in the archive."


def test_backup_script_fixed():
    script = "/home/user/backup_script.py"
    assert os.path.isfile(script), f"Backup script {script} is missing."

    with open(script, "r") as f:
        content = f.read()

    assert "followlinks=True" not in content, "Backup script still contains 'followlinks=True'."


def _normalized_archive_name(name):
    while name.startswith("./"):
        name = name[2:]
    if name.startswith("/home/user/project_root/"):
        return name[len("/home/user/project_root/"):]
    if name.startswith("home/user/project_root/"):
        return name[len("home/user/project_root/"):]
    if name.startswith("project_root/"):
        return name[len("project_root/"):]
    return name


def _derive_source_state(root):
    regular_files = {}
    valid_links = []

    for current, dirs, files in os.walk(root, followlinks=False):
        for dirname in list(dirs):
            path = os.path.join(current, dirname)
            if os.path.islink(path):
                dirs.remove(dirname)
                if os.path.exists(path):
                    valid_links.append(os.path.abspath(path))

        for filename in files:
            path = os.path.join(current, filename)
            if os.path.islink(path):
                if os.path.exists(path):
                    valid_links.append(os.path.abspath(path))
            elif os.path.isfile(path):
                relative = os.path.relpath(path, root).replace(os.sep, "/")
                with open(path, "rb") as source_file:
                    regular_files[relative] = source_file.read()

    return regular_files, sorted(valid_links)


def test_backup_script_executes_safely_on_derived_inputs():
    root = "/home/user/project_root"
    script = "/home/user/backup_script.py"
    archive = "/home/user/safe_archive.tar.gz"
    link_log = "/home/user/skipped_symlinks.log"

    token = secrets.token_hex(12)
    probe = os.path.join(root, "verifier_probe_" + token)
    target_dir = os.path.join(probe, "target")
    os.makedirs(target_dir)

    payloads = {
        os.path.join(probe, "payload.bin"): secrets.token_bytes(193),
        os.path.join(target_dir, "nested.txt"): ("derived-" + token).encode("ascii"),
    }
    for path, payload in payloads.items():
        with open(path, "wb") as f:
            f.write(payload)

    os.symlink(os.path.join(probe, "payload.bin"), os.path.join(probe, "payload_link"))
    os.symlink(target_dir, os.path.join(probe, "directory_link"))

    expected_files, expected_links = _derive_source_state(root)

    for output in (archive, link_log):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["python3", script],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Backup script failed when executed: {result.stderr}"
    assert os.path.isfile(archive), "Executing the backup script did not create the archive."
    assert os.path.isfile(link_log), "Executing the backup script did not create the symlink log."

    with open(link_log, "r") as f:
        actual_links = [line.strip() for line in f if line.strip()]
    assert actual_links == expected_links, "The executed script did not log all valid symlinks as sorted absolute paths."

    archived_files = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            name = _normalized_archive_name(member.name)
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_files[name] = extracted.read()

    assert set(archived_files) == set(expected_files), (
        "The executed script did not archive exactly the regular source files; "
        "it may have followed a directory symlink or omitted files."
    )
    for name, expected_content in expected_files.items():
        assert archived_files[name] == expected_content, f"Archived content differs from source file {name}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
