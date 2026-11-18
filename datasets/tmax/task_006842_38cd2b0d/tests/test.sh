#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import re
import shutil
import secrets
import stat
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET


def manifest_parts(path):
    tree = ET.parse(path)
    root = tree.getroot()
    return [(part.attrib.get("id"), part.text) for part in root.findall(".//part")]


def broken_manifest_parts():
    with open("/home/user/manifest.xml.broken", "r") as f:
        data = f.read()
    return re.findall(r'\[part id="([^"]+)"\]([^\r\n<]+)</prt>', data)


def test_manifest_fixed():
    manifest_path = "/home/user/manifest.xml"
    assert os.path.isfile(manifest_path), f"Fixed manifest {manifest_path} is missing."

    try:
        tree = ET.parse(manifest_path)
        root = tree.getroot()
    except ET.ParseError as e:
        assert False, f"Manifest {manifest_path} is not valid XML: {e}"

    parts = root.findall(".//part")
    assert len(parts) > 0, "No <part> elements found in the fixed manifest."
    for part in parts:
        assert "id" in part.attrib, "Missing 'id' attribute in <part> element."
        assert part.text.startswith("backup_part_"), f"Unexpected part text: {part.text}"


def test_manifest_is_the_repaired_source_manifest():
    expected = broken_manifest_parts()
    actual = manifest_parts("/home/user/manifest.xml")
    assert expected, "Broken source manifest did not contain any archive parts."
    assert actual == expected, "Fixed manifest does not preserve the source part IDs and filenames."

    ids = [int(part_id) for part_id, _ in actual]
    assert ids == list(range(1, len(ids) + 1)), "Manifest part IDs are not contiguous and ordered."
    for _, filename in actual:
        assert os.path.isfile(os.path.join("/home/user/parts", filename)), f"Manifest references missing part {filename}."


def test_assembled_archive():
    archive_path = "/home/user/complete_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Assembled archive {archive_path} is missing."

    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar file."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert "logs/system.log" in names, "Archive is missing logs/system.log."
        assert "logs/auth.log" in names, "Archive is missing logs/auth.log."
        assert "/etc/shadow_backup" in names, "Archive is missing the absolute path malicious file."
        assert "../../../root/secret.txt" in names, "Archive is missing the relative path malicious file."


def test_archive_is_exact_manifest_ordered_concatenation():
    parts = manifest_parts("/home/user/manifest.xml")
    ordered = sorted(parts, key=lambda item: int(item[0]))
    expected = bytearray()
    for _, filename in ordered:
        part_path = os.path.join("/home/user/parts", filename)
        with open(part_path, "rb") as f:
            expected.extend(f.read())

    with open("/home/user/complete_backup.tar.gz", "rb") as f:
        actual = f.read()
    assert actual == bytes(expected), "Complete archive is not the exact concatenation of manifest parts in ID order."


def test_safe_extraction_results():
    system_log = "/home/user/safe_restore/logs/system.log"
    auth_log = "/home/user/safe_restore/logs/auth.log"

    assert os.path.isfile(system_log), f"Safe file {system_log} was not extracted."
    with open(system_log, "r") as f:
        assert f.read() == "system is ok", f"Content of {system_log} is incorrect."

    assert os.path.isfile(auth_log), f"Safe file {auth_log} was not extracted."
    with open(auth_log, "r") as f:
        assert f.read() == "auth fail", f"Content of {auth_log} is incorrect."


def test_malicious_files_not_extracted():
    malicious_abs = "/etc/shadow_backup"
    if os.path.exists(malicious_abs):
        with open(malicious_abs, "r") as f:
            content = f.read()
            assert content != "hacked", f"Malicious absolute path file {malicious_abs} was extracted!"

    malicious_rel = "/root/secret.txt"
    if os.path.exists(malicious_rel):
        with open(malicious_rel, "r") as f:
            content = f.read()
            assert content != "hacked", f"Malicious relative path file {malicious_rel} was extracted!"


def test_quarantine_json():
    quarantine_path = "/home/user/quarantine.json"
    assert os.path.isfile(quarantine_path), f"Quarantine JSON file {quarantine_path} is missing."

    with open(quarantine_path, "r") as f:
        try:
            quarantine_data = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"File {quarantine_path} is not valid JSON: {e}"

    assert isinstance(quarantine_data, list), "Quarantine JSON should be an array."
    assert "/etc/shadow_backup" in quarantine_data, "Missing absolute path in quarantine JSON."
    assert "../../../root/secret.txt" in quarantine_data, "Missing relative path in quarantine JSON."
    assert len(quarantine_data) == 2, "Quarantine JSON should contain exactly 2 malicious paths."


def test_safe_extract_script_exists():
    script_path = "/home/user/safe_extract.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."
    mode = os.stat(script_path, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"Python script {script_path} is not a regular file."


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_safe_extract_script_executes_safely_on_fresh_archive():
    token = secrets.token_hex(12)
    archive = "/home/user/complete_backup.tar.gz"
    restore = "/home/user/safe_restore"
    quarantine = "/home/user/quarantine.json"
    archive_backup = f"/home/user/.archive_backup_{token}"
    restore_backup = f"/home/user/.restore_backup_{token}"
    quarantine_backup = f"/home/user/.quarantine_backup_{token}"

    safe_members = {
        f"dynamic_{token}/nested/data.bin": secrets.token_bytes(41),
        f"dynamic_{token}/..hidden/valid.txt": secrets.token_bytes(23),
    }
    absolute_name = f"/tmp/verifier_abs_{token}"
    escape_name = f"../../../tmp/verifier_rel_{token}"
    internal_traversal = f"dynamic_{token}/folder/../traversal.txt"
    dangerous_names = [absolute_name, escape_name, internal_traversal]
    external_targets = [absolute_name, f"/tmp/verifier_rel_{token}"]
    internal_target = os.path.join(restore, f"dynamic_{token}", "traversal.txt")

    os.replace(archive, archive_backup)
    had_restore = os.path.lexists(restore)
    if had_restore:
        os.replace(restore, restore_backup)
    had_quarantine = os.path.lexists(quarantine)
    if had_quarantine:
        os.replace(quarantine, quarantine_backup)

    for target in external_targets:
        if os.path.lexists(target):
            remove_path(target)

    try:
        with tarfile.open(archive, "w:gz") as tar:
            for name, content in safe_members.items():
                info = tarfile.TarInfo(name)
                info.size = len(content)
                tar.addfile(info, io.BytesIO(content))
            for name in dangerous_names:
                content = b"verifier-dangerous-content"
                info = tarfile.TarInfo(name)
                info.size = len(content)
                tar.addfile(info, io.BytesIO(content))

        result = subprocess.run(
            [sys.executable, "/home/user/safe_extract.py"],
            cwd="/tmp",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"safe_extract.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert os.path.isdir(restore), "safe_extract.py did not create the extraction directory."

        for name, expected_content in safe_members.items():
            output = os.path.join(restore, *name.split("/"))
            assert os.path.isfile(output), f"Fresh safe member {name} was not extracted."
            with open(output, "rb") as f:
                assert f.read() == expected_content, f"Fresh safe member {name} has incorrect content."

        for target in external_targets:
            assert not os.path.lexists(target), f"Dangerous member escaped extraction to {target}."
        assert not os.path.lexists(internal_target), "A member containing '../' was extracted instead of quarantined."

        assert os.path.isfile(quarantine), "safe_extract.py did not produce quarantine.json when executed."
        with open(quarantine, "r") as f:
            reported = json.load(f)
        assert isinstance(reported, list), "Runtime quarantine output is not a JSON array."
        assert len(reported) == len(dangerous_names), "Runtime quarantine output has an incorrect number of entries."
        assert set(reported) == set(dangerous_names), "Runtime quarantine output does not contain the generated dangerous paths exactly."
    finally:
        for target in external_targets:
            if os.path.lexists(target):
                remove_path(target)
        if os.path.lexists(archive):
            remove_path(archive)
        os.replace(archive_backup, archive)
        if os.path.lexists(restore):
            remove_path(restore)
        if had_restore and os.path.lexists(restore_backup):
            os.replace(restore_backup, restore)
        if os.path.lexists(quarantine):
            remove_path(quarantine)
        if had_quarantine and os.path.lexists(quarantine_backup):
            os.replace(quarantine_backup, quarantine)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
